//
//  APIS.swift
//  Register
//

import ComposableArchitecture
import Dependencies
import Foundation
import IdentifiedCollections
import MQTTNIO
import os

enum TerminalEvent: Equatable, Codable {
  case open, close
  case clearCart
  case processPayment
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
      let identifier = String(
        config.terminalName.unicodeScalars.filter {
          CharacterSet.alphanumerics.contains($0)
        }
      ).lowercased()

      let client = MQTTClient(
        host: "192.168.1.175",
        port: 1883,
        identifier: identifier,
        eventLoopGroupProvider: .createNew
      )

      do {
        try await client.connect()
        Self.logger.debug("Connected to MQTT server")

        let topic = "register/\(identifier)"
        Self.logger.debug("Subscribing to MQTT topic: \(topic, privacy: .public)")
        let subscription = MQTTSubscribeInfo(
          topicFilter: "register/\(identifier)", qos: .atLeastOnce)
        _ = try await client.subscribe(to: [subscription])
        Self.logger.debug("Created MQTT subscription")

        let listener = client.createPublishListener()
        Self.logger.debug("Created MQTT publish listener")

        return (client, listener)
      } catch let error as MQTTError {
        Self.logger.warning("Got MQTT error: \(error, privacy: .public)")
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
