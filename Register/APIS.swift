//
//  APIS.swift
//  Register
//

import ComposableArchitecture
import Dependencies
import Foundation
import IdentifiedCollections
import MQTTNIO
import SwiftUI
import os

enum TerminalEvent: Equatable, Codable {
  case open, close
  case clearCart
  case processPayment(total: Int, note: String, reference: String)
  case updateCart(cart: TerminalCart)
}

struct TerminalBadge: Identifiable, Equatable, Codable {
  let id: Int
  let firstName: String
  let lastName: String
  let badgeName: String
  let effectiveLevelName: String
  let effectiveLevelPrice: Decimal

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.id = try container.decode(Int.self, forKey: .id)
    self.firstName = try container.decode(String.self, forKey: .firstName)
    self.lastName = try container.decode(String.self, forKey: .lastName)
    self.badgeName = try container.decode(String.self, forKey: .badgeName)
    self.effectiveLevelName = try container.decode(String.self, forKey: .effectiveLevelName)
    self.effectiveLevelPrice = Decimal(
      string: try container.decode(String.self, forKey: .effectiveLevelPrice))!
  }
}

struct TerminalCart: Equatable, Codable {
  let badges: IdentifiedArrayOf<TerminalBadge>
  let charityDonation: Decimal
  let organizationDonation: Decimal
  let total: Decimal

  static let empty = Self(
    badges: .init(),
    charityDonation: 0,
    organizationDonation: 0,
    total: 0
  )

  init(
    badges: IdentifiedArrayOf<TerminalBadge>, charityDonation: Decimal,
    organizationDonation: Decimal, total: Decimal
  ) {
    self.badges = badges
    self.charityDonation = charityDonation
    self.organizationDonation = organizationDonation
    self.total = total
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.badges = IdentifiedArray(
      uniqueElements: try container.decode([TerminalBadge].self, forKey: .badges))
    self.charityDonation = Decimal(
      string: try container.decode(String.self, forKey: .charityDonation))!
    self.organizationDonation = Decimal(
      string: try container.decode(String.self, forKey: .organizationDonation))!
    self.total = Decimal(string: try container.decode(String.self, forKey: .total))!
  }
}

struct RegisterRequest: Equatable, Codable {
  @BindableState var terminalName = ""
  @BindableState var host = ""
  @BindableState var token = ""

  init(terminalName: String = "", host: String = "", token: String = "") {
    self.terminalName = terminalName
    self.host = host
    self.token = token
  }

  init(config: Config) {
    self.terminalName = config.terminalName
    self.host = config.host
    self.token = config.token
  }

  var hostIsValidURL: Bool {
    guard let url = URL(string: host) else {
      return false
    }

    let scheme = url.scheme
    return scheme == "http" || scheme == "https"
  }

  var isReady: Bool {
    return !terminalName.isEmpty && !host.isEmpty && !token.isEmpty && hostIsValidURL
  }
}

struct ApisClient {
  static let logger = Logger(subsystem: "net.syfaro.Register", category: "APIS")

  enum ApisError: LocalizedError {
    case invalidHost
    case badResponse(Int)
    case subscriptionError

    var errorDescription: String? {
      switch self {
      case .invalidHost:
        return "API host did not appear to be a valid URL"
      case .badResponse(let statusCode):
        return "Got wrong status code from API: \(statusCode)"
      case .subscriptionError:
        return "Could not subscribe to events"
      }
    }
  }

  var registerTerminal: (RegisterRequest) async throws -> Config
  var subscribeToEvents: (Config) async throws -> (MQTTClient, MQTTPublishListener)
  var getSquareToken: (Config) async throws -> String
  var squareTransactionCompleted: (Config, String, String, String) async throws -> Bool

  private static func url(_ host: String) throws -> URL {
    guard let url = URL(string: host) else {
      throw ApisError.invalidHost
    }

    return url
  }
}

extension ApisClient: DependencyKey {
  static let liveValue: ApisClient = Self(
    registerTerminal: { req in
      let url = try Self.url(req.host)
      let endpoint = url.appending(path: "/terminal/register")
      Self.logger.debug("Attempting to register at \(endpoint, privacy: .public)")

      let jsonEncoder = JSONEncoder()
      let httpBody = try jsonEncoder.encode(req)

      var request = URLRequest(url: endpoint)
      request.setValue("application/json", forHTTPHeaderField: "content-type")
      request.httpMethod = "POST"
      request.httpBody = httpBody

      let (data, response) = try await URLSession.shared.data(for: request)
      guard let httpResponse = response as? HTTPURLResponse else {
        Self.logger.error("response was not HTTPURLResponse")
        throw ApisError.badResponse(-1)
      }

      guard httpResponse.statusCode == 200 else {
        Self.logger.warning("Got wrong status code: \(httpResponse.statusCode, privacy: .public)")
        throw ApisError.badResponse(httpResponse.statusCode)
      }

      let jsonDecoder = JSONDecoder()

      let config = try jsonDecoder.decode(Config.self, from: data)
      return config
    },
    subscribeToEvents: { config in
      let client = MQTTClient(
        host: config.mqttHost,
        port: config.mqttPort,
        identifier: config.terminalName,
        eventLoopGroupProvider: .createNew
      )

      do {
        try await client.connect()
        Self.logger.debug("Connected to MQTT server")

        let topic = "register/\(config.terminalName)"
        Self.logger.debug("Subscribing to MQTT topic: \(topic, privacy: .public)")
        let subscription = MQTTSubscribeInfo(
          topicFilter: "register/\(config.terminalName)", qos: .atLeastOnce)
        _ = try await client.subscribe(to: [subscription])
        Self.logger.debug("Created MQTT subscription")

        let listener = client.createPublishListener()
        Self.logger.debug("Created MQTT publish listener")

        return (client, listener)
      } catch let error as MQTTError {
        Self.logger.warning("Got MQTT error: \(error, privacy: .public)")
        try! client.syncShutdownGracefully()
        throw error
      } catch {
        Self.logger.error("Got other error: \(error, privacy: .public)")
        try! client.syncShutdownGracefully()
        throw error
      }
    },
    getSquareToken: { config in
      let url = try Self.url(config.host)
      let endpoint = url.appending(path: "/terminal/square/token")
      Self.logger.debug("Attempting to get Square token at \(endpoint, privacy: .public)")

      var request = URLRequest(url: endpoint)
      request.setValue(config.key, forHTTPHeaderField: "x-register-key")
      request.httpMethod = "POST"

      let (data, response) = try await URLSession.shared.data(for: request)
      guard let httpResponse = response as? HTTPURLResponse else {
        Self.logger.error("response was not HTTPURLResponse")
        throw ApisError.badResponse(-1)
      }

      guard httpResponse.statusCode == 200 else {
        Self.logger.warning("Got wrong status code: \(httpResponse.statusCode, privacy: .public)")
        throw ApisError.badResponse(httpResponse.statusCode)
      }

      let jsonDecoder = JSONDecoder()

      let config = try jsonDecoder.decode(String.self, from: data)
      return config
    },
    squareTransactionCompleted: { config, reference, transactionID, clientTransactionID in
      let url = try Self.url(config.host)
      let endpoint = url.appending(path: "/terminal/square/completed")
      Self.logger.debug("Attempting validate Square purchase at \(endpoint, privacy: .public)")

      struct TransactionData: Encodable {
        let key: String
        let reference: String
        let clientTransactionId: String
        let serverTransactionId: String
      }

      let transactionData = TransactionData(
        key: config.key,
        reference: reference,
        clientTransactionId: clientTransactionID,
        serverTransactionId: transactionID
      )

      let jsonEncoder = JSONEncoder()
      let httpBody = try jsonEncoder.encode(transactionData)

      var request = URLRequest(url: endpoint)
      request.setValue("application/json", forHTTPHeaderField: "content-type")
      request.setValue(config.key, forHTTPHeaderField: "x-register-key")
      request.httpMethod = "POST"
      request.httpBody = httpBody

      let (data, response) = try await URLSession.shared.data(for: request)
      guard let httpResponse = response as? HTTPURLResponse else {
        Self.logger.error("response was not HTTPURLResponse")
        throw ApisError.badResponse(-1)
      }

      guard httpResponse.statusCode == 200 else {
        Self.logger.warning("Got wrong status code: \(httpResponse.statusCode, privacy: .public)")
        throw ApisError.badResponse(httpResponse.statusCode)
      }

      struct TransactionResponse: Decodable {
        let success: Bool
      }

      let jsonDecoder = JSONDecoder()

      let transactionResponse = try jsonDecoder.decode(TransactionResponse.self, from: data)
      return transactionResponse.success
    }
  )
}

extension DependencyValues {
  var apis: ApisClient {
    get { self[ApisClient.self] }
    set { self[ApisClient.self] = newValue }
  }
}
