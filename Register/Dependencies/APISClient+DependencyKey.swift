//
//  APISClient+DependencyKey.swift
//  Register
//

import AsyncAlgorithms
import Combine
import ComposableArchitecture
import Foundation
import MQTTNIO
import NIOCore
import NIOTransportServices

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
    body: Req,
    token: String? = nil
  ) async throws -> Resp {
    let url = endpoint.appending(path: path)
    Self.logger.debug("Attempting to make request to \(url, privacy: .public)")

    let jsonEncoder = JSONEncoder()
    let httpBody = try jsonEncoder.encode(body)

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

private actor ApisMqtt {
  public enum Topic: String {
    case paymentNotification = "web/notify/payment"
  }

  private let eventLoopGroup = NIOTSEventLoopGroup()
  private let byteBufferAllocator = ByteBufferAllocator()
  private let jsonDecoder = JSONDecoder()
  private let jsonEncoder = JSONEncoder()

  private var client: MQTTClient? = nil
  private var config: Config? = nil

  var isConnected: Bool {
    client?.isActive() == true
  }

  func setUp(
    config: Config
  ) async throws -> some AsyncSequence<Result<TerminalEvent, Error>, Never> {
    self.config = config

    let host: String
    let mqttConfig: MQTTClient.Configuration
    if let url = URL(string: config.mqttHost), url.scheme == "wss" {
      host = url.host() ?? config.mqttHost
      mqttConfig = .init(
        version: .v5_0,
        userName: config.mqttUsername,
        password: config.mqttPassword,
        useSSL: true,
        webSocketConfiguration: .init(urlPath: url.path())
      )
    } else {
      host = config.mqttHost
      mqttConfig = .init(
        version: .v5_0,
        userName: config.mqttUsername,
        password: config.mqttPassword
      )
    }

    try? await disconnect()

    let client = MQTTClient(
      host: host,
      port: config.mqttPort,
      identifier: "terminal-\(config.terminalName.lowercased())",
      eventLoopGroupProvider: .shared(eventLoopGroup),
      configuration: mqttConfig
    )
    self.client = client

    let closeEvents = AsyncStream<Result<TerminalEvent, Error>> { continuation in
      client.addCloseListener(named: "close") { result in
        switch result {
        case .success:
          ApisClient.logger.info("MQTT connection closed")
          continuation.yield(.success(.disconnected))
        case .failure(let error):
          ApisClient.logger.error("MQTT connection closed with error \(error)")
          continuation.yield(.failure(error))
        }
      }

      continuation.onTermination = { _ in
        client.removeCloseListener(named: "close")
      }
    }

    let mainEvents = client.createPublishListener().compactMap {
      (result) -> Result<TerminalEvent, Error>? in
      switch result {
      case .success(let publish):
        guard publish.topicName.hasPrefix(config.mqttPrefix) else {
          ApisClient.logger.warning("Got unexpected topic name \(publish.topicName)")
          return nil
        }

        var buffer = publish.payload
        guard let data = buffer.readData(length: buffer.readableBytes) else {
          ApisClient.logger.error("Could not read buffer of \(buffer.readableBytes) length")
          return nil
        }

        let topic = publish.topicName.dropFirst(config.mqttPrefix.count + 1)

        do {
          let event = try TerminalEvent(topic: String(topic), data: data)
          return .success(event)
        } catch {
          ApisClient.logger.error("Got unknown event: topic=\(topic), \(error)")
          return nil
        }
      case .failure(let error):
        return .failure(error)
      }
    }

    return merge(closeEvents, mainEvents)
  }

  func connect() async throws {
    guard let config, let client else {
      throw ApisError.eventsNotConfigured
    }

    if client.isActive() {
      return
    }

    do {
      ApisClient.logger.debug("Attempting to connect to MQTT server")

      let ack = try await client.v5.connect(
        cleanStart: false,
        properties: [.sessionExpiryInterval(300)],
        connectConfiguration: .init(keepAliveInterval: .seconds(10))
      )
      ApisClient.logger.trace("Connected to MQTT server, sessionPresent: \(ack.sessionPresent)")

      let subscription = MQTTSubscribeInfo(
        topicFilter: "\(config.mqttPrefix)/payment/#", qos: .atLeastOnce
      )
      _ = try await client.subscribe(to: [subscription])
    } catch {
      ApisClient.logger.error("Could not create MQTT connection: \(error)")
      throw ApisError.subscriptionError
    }
  }

  func disconnect() async throws {
    if let client {
      if client.isActive() {
        try await client.disconnect()
      }

      try client.syncShutdownGracefully()
    }

    client = nil
  }

  func publish<M: Encodable>(_ message: M, topic: Topic) async throws {
    guard let config, let client else {
      throw ApisError.eventsNotConfigured
    }

    let topic = "\(config.mqttPrefix)/\(topic.rawValue)"
    let payload = try jsonEncoder.encodeAsByteBuffer(message, allocator: byteBufferAllocator)

    ApisClient.logger.debug("Publishing message to \(topic)")
    try await client.publish(to: topic, payload: payload, qos: .atLeastOnce)
  }

  deinit {
    try? client?.syncShutdownGracefully()
  }
}

extension ApisClient: DependencyKey {
  static var liveValue: ApisClient {
    let apisMqtt = ApisMqtt()

    return Self(
      requestSquareToken: { config in
        let _: Bool = try await Self.makeHttpRequest(
          endpoint: config.endpoint,
          path: "/registration/terminal/square/token",
          body: true,
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
          body: transactionData,
          token: config.token
        )

        return resp.success
      },
      setUpEvents: { config in
        return .run { send in
          do {
            let events = try await apisMqtt.setUp(config: config)
            await send(.success(.setUp))

            for await event in events {
              await send(event)
            }
          } catch {
            await send(.failure(error))
          }
        }
      },
      connectEvents: {
        try await apisMqtt.connect()
      },
      disconnectEvents: {
        try await apisMqtt.disconnect()
      },
      notifyFrontend: { config, notification in
        try await apisMqtt.publish(notification, topic: .paymentNotification)
      }
    )
  }
}
