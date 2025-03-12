//
//  APISClient+DependencyKey.swift
//  Register
//

import Combine
import ComposableArchitecture
import Foundation
import MQTTNIO

extension ApisClient {
  private static func url(_ host: String) throws -> URL {
    guard let url = URL(string: host) else {
      throw ApisError.invalidHost
    }

    return url
  }

  private static func makeHttpRequest<Req: Encodable, Resp: Decodable>(
    endpoint: URL,
    path: String,
    req: Req,
    token: String? = nil
  ) async throws -> Resp {
    let url = endpoint.appending(path: path)
    Self.logger.debug("Attempting to make request to \(url, privacy: .public)")

    let jsonEncoder = JSONEncoder()
    let httpBody = try jsonEncoder.encode(req)

    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.httpBody = httpBody
    request.setValue("application/json", forHTTPHeaderField: "content-type")
    if let token {
      request.setValue("Bearer \(token)", forHTTPHeaderField: "authorization")
    }

    let (data, response) = try await URLSession.shared.data(for: request)
    guard let httpResponse = response as? HTTPURLResponse else {
      Self.logger.error("Response was not HTTPURLResponse")
      throw ApisError.badResponse(-1)
    }

    guard httpResponse.statusCode == 200 else {
      Self.logger.warning("Got wrong status code: \(httpResponse.statusCode, privacy: .public)")
      throw ApisError.badResponse(httpResponse.statusCode)
    }

    let jsonDecoder = JSONDecoder()
    let config = try jsonDecoder.decode(Resp.self, from: data)
    return config
  }
}

extension ApisClient: DependencyKey {
  static let liveValue: ApisClient = Self(
    requestSquareToken: { config in
      let _: Bool = try await Self.makeHttpRequest(
        endpoint: config.endpoint,
        path: "/registration/terminal/square/token",
        req: true,
        token: config.token
      )
    },
    squareTransactionCompleted: { config, transaction in
      struct TransactionData: Encodable {
        let reference: String
        let paymentId: String
      }

      let transactionData = TransactionData(
        reference: transaction.reference,
        paymentId: transaction.paymentId
      )

      struct TransactionResponse: Decodable {
        let success: Bool
      }

      let resp: TransactionResponse = try await Self.makeHttpRequest(
        endpoint: config.endpoint,
        path: "/registration/terminal/square/completed",
        req: transactionData,
        token: config.token
      )

      return resp.success
    },
    subscribeToEvents: { config in
      var host = config.mqttHost

      var mqttConfig: MQTTClient.Configuration = .init(
        version: .v5_0,
        userName: config.mqttUsername,
        password: config.mqttPassword
      )

      if let url = URL(string: host) {
        if url.scheme == "wss" {
          Self.logger.debug("MQTT host was secure websocket, updating config")
          mqttConfig = .init(
            version: .v5_0,
            userName: config.mqttUsername,
            password: config.mqttPassword,
            useSSL: true,
            webSocketConfiguration: .init(urlPath: url.path())
          )
          host = url.host() ?? config.mqttHost
          Self.logger.trace("Updated MQTT info: host=\(host)")
        }
      }

      let client = MQTTClient(
        host: host,
        port: config.mqttPort,
        identifier: "terminal-\(config.terminalName.lowercased())",
        eventLoopGroupProvider: .createNew,
        configuration: mqttConfig
      )

      return Effect<TaskResult<TerminalEvent>>.run { sub in
        do {
          Self.logger.debug("Attempting to connect to MQTT server")
          let ack = try await client.v5.connect(
            cleanStart: false,
            properties: [.sessionExpiryInterval(300)]
          )
          Self.logger.debug("Connected to MQTT server, sessionPresent: \(ack.sessionPresent)")

          let listener = client.createPublishListener()
          let jsonDecoder = JSONDecoder()

          let subscription = MQTTSubscribeInfo(topicFilter: config.mqttTopic, qos: .atLeastOnce)
          _ = try await client.subscribe(to: [subscription])
          Self.logger.debug("Created MQTT subscription to: \(config.mqttTopic, privacy: .public)")

          sub(.success(.connected))

          await withTaskCancellationHandler {
            listenerLoop: for await result in listener {
              let publish: MQTTPublishInfo
              switch result {
              case let .success(pub):
                publish = pub
              case let .failure(error):
                sub(.failure(error))
                break listenerLoop
              }

              var buffer = publish.payload
              guard let data = buffer.readData(length: buffer.readableBytes) else {
                continue
              }

              do {
                let event = try jsonDecoder.decode(TerminalEvent.self, from: data)
                sub(.success(event))
              } catch {
                Self.logger.error("Got unknown event: \(error, privacy: .public)")
                sub(.failure(ApisError.unknownEvent))
              }
            }
          } onCancel: {
            try? client.syncShutdownGracefully()
          }
        } catch {
          Self.logger.error("Got MQTT error: \(error, privacy: .public)")
          try? client.syncShutdownGracefully()
          sub(.failure(ApisError.subscriptionError))
        }
      }
    }
  )
}
