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
  let discountedPrice: Decimal?

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.id = try container.decode(Int.self, forKey: .id)
    self.firstName = try container.decode(String.self, forKey: .firstName)
    self.lastName = try container.decode(String.self, forKey: .lastName)
    self.badgeName = try container.decode(String.self, forKey: .badgeName)
    self.effectiveLevelName = try container.decode(String.self, forKey: .effectiveLevelName)
    self.effectiveLevelPrice = Decimal(
      string: try container.decode(String.self, forKey: .effectiveLevelPrice))!
    self.discountedPrice = Decimal(
      string: try container.decodeIfPresent(String.self, forKey: .discountedPrice) ?? "")
  }
}

struct TerminalCart: Equatable, Codable {
  let badges: IdentifiedArrayOf<TerminalBadge>
  let charityDonation: Decimal
  let organizationDonation: Decimal
  let totalDiscount: Decimal?
  let total: Decimal

  static let empty = Self(
    badges: .init(),
    charityDonation: 0,
    organizationDonation: 0,
    totalDiscount: nil,
    total: 0
  )

  init(
    badges: IdentifiedArrayOf<TerminalBadge>,
    charityDonation: Decimal,
    organizationDonation: Decimal,
    totalDiscount: Decimal?,
    total: Decimal
  ) {
    self.badges = badges
    self.charityDonation = charityDonation
    self.organizationDonation = organizationDonation
    self.totalDiscount = totalDiscount
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
    self.totalDiscount = Decimal(
      string: try container.decodeIfPresent(String.self, forKey: .totalDiscount) ?? "")
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

  private var hostIsValidURL: Bool {
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

struct SquareCompletedTransaction {
  let reference: String
  let transactionID: String
  let clientTransactionID: String
}

struct ApisClient {
  static let logger = Logger(subsystem: Register.bundle, category: "APIS")

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
  var getSquareToken: (Config) async throws -> String
  var squareTransactionCompleted: (Config, SquareCompletedTransaction) async throws -> Bool

  var subscribeToEvents: (Config) async throws -> (MQTTClient, MQTTPublishListener)

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
        eventLoopGroupProvider: .createNew
      )

      do {
        try await client.connect()
        Self.logger.debug("Connected to MQTT server")

        let topic = "register/\(config.terminalName)"
        let subscription = MQTTSubscribeInfo(
          topicFilter: "register/\(config.terminalName)",
          qos: .atLeastOnce
        )
        _ = try await client.subscribe(to: [subscription])
        Self.logger.debug("Created MQTT subscription to: \(topic, privacy: .public)")

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
    }
  )
}

extension DependencyValues {
  var apis: ApisClient {
    get { self[ApisClient.self] }
    set { self[ApisClient.self] = newValue }
  }
}
