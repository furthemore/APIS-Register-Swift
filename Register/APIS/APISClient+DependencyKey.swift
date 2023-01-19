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
    host: String,
    endpoint: String,
    req: Req,
    key: String? = nil
  ) async throws -> Resp {
    let url = try Self.url(host)
    let endpoint = url.appending(path: endpoint)
    Self.logger.debug("Attempting to make request to \(endpoint, privacy: .public)")

    let jsonEncoder = JSONEncoder()
    let httpBody = try jsonEncoder.encode(req)

    var request = URLRequest(url: endpoint)
    request.httpMethod = "POST"
    request.httpBody = httpBody
    request.setValue("application/json", forHTTPHeaderField: "content-type")
    if let key = key {
      request.setValue(key, forHTTPHeaderField: "x-register-key")
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
    registerTerminal: { req in
      return try await Self.makeHttpRequest(
        host: req.host,
        endpoint: "/terminal/register",
        req: req
      )
    },
    getSquareToken: { config in
      return try await Self.makeHttpRequest(
        host: config.host,
        endpoint: "/terminal/square/token",
        req: true,
        key: config.key
      )
    },
    squareTransactionCompleted: { config, transaction in
      struct TransactionData: Encodable {
        let key: String
        let reference: String
        let clientTransactionId: String
        let serverTransactionId: String
      }

      let transactionData = TransactionData(
        key: config.key,
        reference: transaction.reference,
        clientTransactionId: transaction.clientTransactionID,
        serverTransactionId: transaction.transactionID
      )

      struct TransactionResponse: Decodable {
        let success: Bool
      }

      let resp: TransactionResponse = try await Self.makeHttpRequest(
        host: config.host,
        endpoint: "/terminal/square/completed",
        req: transactionData,
        key: config.key
      )
      return resp.success
    },
    subscribeToEvents: { config in
      let client = MQTTClient(
        host: config.mqttHost,
        port: config.mqttPort,
        identifier: config.terminalName,
        eventLoopGroupProvider: .createNew,
        configuration: .init(
          userName: config.mqttUserName,
          password: config.mqttPassword,
          useWebSockets: true
        )
      )

      return EffectTask<TaskResult<TerminalEvent>>.run { sub in
        do {
          try await client.connect()
          Self.logger.debug("Connected to MQTT server")

          let subscription = MQTTSubscribeInfo(topicFilter: config.mqttTopic, qos: .atLeastOnce)
          _ = try await client.subscribe(to: [subscription])
          Self.logger.debug("Created MQTT subscription to: \(config.mqttTopic, privacy: .public)")

          let jsonDecoder = JSONDecoder()

          await withTaskCancellationHandler {
            let listener = client.createPublishListener()

            await sub.send(.success(.connected))

            listenerLoop: for await result in listener {
              let publish: MQTTPublishInfo
              switch result {
              case let .success(pub):
                publish = pub
              case let .failure(error):
                await sub.send(.failure(error))
                break listenerLoop
              }

              var buffer = publish.payload
              guard let data = buffer.readData(length: buffer.readableBytes) else {
                continue
              }

              do {
                let event = try jsonDecoder.decode(TerminalEvent.self, from: data)
                await sub.send(.success(event))
              } catch {
                await sub.send(.failure(ApisError.unknownEvent))
              }
            }
          } onCancel: {
            try? client.syncShutdownGracefully()
          }
        } catch {
          Self.logger.error("Got MQTT error: \(error, privacy: .public)")
          try? client.syncShutdownGracefully()
          throw error
        }
      }
    }
  )
}
