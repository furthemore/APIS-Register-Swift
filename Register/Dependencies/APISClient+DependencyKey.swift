//
//  APISClient+DependencyKey.swift
//  Register
//

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
    case paymentNotification = "payment_notification"
  }

  private static let eventLoopGroup = NIOTSEventLoopGroup()
  private let byteBufferAllocator = ByteBufferAllocator()

  private let jsonDecoder = JSONDecoder()
  private let jsonEncoder = JSONEncoder()

  private let eventSubject: PassthroughSubject<TaskResult<TerminalEvent>, Never>

  private var client: MQTTClient? = nil
  private var task: Task<Void, Never>? = nil
  private var config: Config? = nil

  var isConnected: Bool {
    client?.isActive() ?? false
  }

  var events: AnyPublisher<TaskResult<TerminalEvent>, Never> {
    eventSubject.eraseToAnyPublisher()
  }

  init() {
    eventSubject = PassthroughSubject<TaskResult<TerminalEvent>, Never>()
  }

  func setUp(config: Config) async throws {
    self.config = config

    var host = config.mqttHost

    var mqttConfig: MQTTClient.Configuration = .init(
      version: .v5_0,
      userName: config.mqttUsername,
      password: config.mqttPassword
    )

    if let url = URL(string: host) {
      if url.scheme == "wss" {
        ApisClient.logger.trace("MQTT host was secure websocket, updating config")
        mqttConfig = .init(
          version: .v5_0,
          userName: config.mqttUsername,
          password: config.mqttPassword,
          useSSL: true,
          webSocketConfiguration: .init(urlPath: url.path())
        )
        host = url.host() ?? config.mqttHost
        ApisClient.logger.trace("Updated MQTT info: host=\(host)")
      }
    }

    try? await disconnect()
    try client?.syncShutdownGracefully()

    let newClient = MQTTClient(
      host: host,
      port: config.mqttPort,
      identifier: "terminal-\(config.terminalName.lowercased())",
      eventLoopGroupProvider: .shared(Self.eventLoopGroup),
      configuration: mqttConfig
    )

    client = newClient

    newClient.addCloseListener(named: "close") { [weak self] _ in
      Task.detached {
        ApisClient.logger.info("MQTT connection closed")
        await self?.eventSubject.send(.success(.disconnected))
      }
    }

    let listener = newClient.createPublishListener()

    task = Task.detached {
      await withTaskCancellationHandler {
        listenerLoop: for await result in listener {
          let publish: MQTTPublishInfo
          switch result {
          case .success(let pub):
            publish = pub
          case .failure(let error):
            self.eventSubject.send(.failure(error))
            break listenerLoop
          }

          var buffer = publish.payload
          guard let data = buffer.readData(length: buffer.readableBytes) else {
            ApisClient.logger.error("Could not read buffer of \(buffer.readableBytes) length")
            continue
          }

          do {
            let event = try self.jsonDecoder.decode(TerminalEvent.self, from: data)
            self.eventSubject.send(.success(event))
          } catch {
            ApisClient.logger.error("Got unknown event: \(error)")
          }
        }
      } onCancel: {
        Task {
          ApisClient.logger.info("Got task cancellation, disconnecting client")
          try await newClient.disconnect()
        }
      }
    }
  }

  func connect() async throws {
    guard let config, let client else {
      ApisClient.logger.error("Attempted to connect with no MQTT config or client")
      return
    }

    if client.isActive() {
      return
    }

    do {
      ApisClient.logger.debug("Attempting to connect to MQTT server")
      let ack = try await client.v5.connect(
        cleanStart: false,
        properties: [.sessionExpiryInterval(300)]
      )
      ApisClient.logger.debug("Connected to MQTT server, sessionPresent: \(ack.sessionPresent)")

      let subscription = MQTTSubscribeInfo(topicFilter: config.mqttTopic, qos: .atLeastOnce)
      _ = try await client.subscribe(to: [subscription])
      ApisClient.logger.debug("Created MQTT subscription to: \(config.mqttTopic, privacy: .public)")
    } catch {
      ApisClient.logger.error("Could not create MQTT connection: \(error, privacy: .public)")

      throw ApisError.subscriptionError
    }
  }

  func disconnect() async throws {
    task?.cancel()

    if let client, client.isActive() {
      try await client.disconnect()
    }
  }

  func publish<M: Encodable>(_ message: M, topic: Topic) async throws {
    guard let config, let client, let publishTopicPrefix = config.mqttPublishTopicPrefix else {
      ApisClient.logger.error(
        "Attempted to publish with no MQTT config, client, or publish topic prefix")
      return
    }

    try await client.publish(
      to: "\(publishTopicPrefix)/\(topic.rawValue)",
      payload: try jsonEncoder.encodeAsByteBuffer(message, allocator: byteBufferAllocator),
      qos: .atLeastOnce
    )
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
      getEvents: {
        return .run { send in
          for await event in await apisMqtt.events.values {
            await send(event)
          }
        }
      },
      prepareEvents: { config in
        return .run { send in
          do {
            try await apisMqtt.setUp(config: config)
          } catch {
            await send(.failure(error))
          }
        }
      },
      connectEvents: {
        return .run { send in
          do {
            try await apisMqtt.connect()
            await send(.success(.connected))
          } catch {
            await send(.failure(error))
          }
        }
      },
      disconnectEvents: {
        return .run { send in
          do {
            try await apisMqtt.disconnect()
            await send(.success(.disconnected))
          } catch {
            await send(.failure(error))
          }
        }
      },
      notifyFrontend: { config, notification in
        return .run { _ in
          try? await apisMqtt.publish(notification, topic: .paymentNotification)
        }
      }
    )
  }
}
