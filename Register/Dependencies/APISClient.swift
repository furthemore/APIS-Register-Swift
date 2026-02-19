//
//  APIS.swift
//  Register
//

import ComposableArchitecture
import Foundation
import os

// MARK: API models

enum FrontendNotification: String, Equatable, Codable {
  case paymentOpened = "payment_opened"
  case paymentCancelled = "payment_cancelled"
  case paymentFailed = "payment_failed"
  case paymentCompleted = "payment_completed"

  case registrationOpened = "registration_opened"
  case registrationCompleted = "registration_completed"
}

enum TerminalEvent: Equatable {
  case setUp, connected, disconnected

  case cartClear
  case cartUpdate(TerminalCart)
  case print(TerminalPrint)
  case process(TerminalProcess)
  case registrationCancel
  case registrationDisplay(TerminalRegistrationDisplay)
  case state(TerminalState)
  case updateConfig(Config)
  case updateToken(TerminalSquareToken)
}

extension TerminalEvent {
  init(topic: String, data: Data) throws {
    switch topic {
    case "payment/cart/clear":
      self = .cartClear
    case "payment/cart/update":
      let cart = try JSONDecoder().decode(TerminalCart.self, from: data)
      self = .cartUpdate(cart)
    case "payment/print":
      let print = try JSONDecoder().decode(TerminalPrint.self, from: data)
      self = .print(print)
    case "payment/process":
      let process = try JSONDecoder().decode(TerminalProcess.self, from: data)
      self = .process(process)
    case "payment/registration/cancel":
      self = .registrationCancel
    case "payment/registration/display":
      let display = try JSONDecoder().decode(TerminalRegistrationDisplay.self, from: data)
      self = .registrationDisplay(display)
    case "payment/state":
      let state = try JSONDecoder().decode(TerminalState.self, from: data)
      self = .state(state)
    case "payment/update/config":
      let config = try JSONDecoder().decode(Config.self, from: data)
      self = .updateConfig(config)
    case "payment/update/token":
      let token = try JSONDecoder().decode(TerminalSquareToken.self, from: data)
      self = .updateToken(token)
    default:
      throw ApisError.unknownEvent
    }
  }

  var isFakeEvent: Bool {
    switch self {
    case .setUp, .connected, .disconnected:
      return true
    default:
      return false
    }
  }
}

struct TerminalPrint: Equatable, Codable {
  let url: URL
  let serialNumber: String?
}

struct TerminalProcess: Equatable, Codable {
  let paymentAttemptId: String
  let orderId: String?
  let total: UInt
  let note: String
  let reference: String
}

struct TerminalRegistrationDisplay: Equatable, Codable {
  let url: URL
  let token: String
}

enum TerminalState: Equatable, Decodable {
  case open, close, ready
  case other(String)

  init(from decoder: any Decoder) throws {
    if let value = try? decoder.singleValueContainer().decode(String.self) {
      switch value {
      case "open":
        self = .open
      case "close":
        self = .close
      case "ready":
        self = .ready
      default:
        self = .other(value)
      }
    } else {
      throw ApisError.unknownEvent
    }
  }
}

struct TerminalSquareToken: Equatable, Codable {
  let accessToken: String
  let refreshToken: String
}

struct TerminalBadge: Identifiable, Equatable, Codable {
  let id: Int
  let firstName: String
  let lastName: String
  let badgeName: String
  let effectiveLevel: EffectiveLevel
  let discountedPrice: Decimal?

  init(
    id: Int,
    firstName: String,
    lastName: String,
    badgeName: String,
    effectiveLevel: EffectiveLevel,
    discountedPrice: Decimal? = nil
  ) {
    self.id = id
    self.firstName = firstName
    self.lastName = lastName
    self.badgeName = badgeName
    self.effectiveLevel = effectiveLevel
    self.discountedPrice = discountedPrice
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.id = try container.decode(Int.self, forKey: .id)
    self.firstName = try container.decode(String.self, forKey: .firstName)
    self.lastName = try container.decode(String.self, forKey: .lastName)
    self.badgeName = try container.decode(String.self, forKey: .badgeName)
    self.effectiveLevel = try container.decode(EffectiveLevel.self, forKey: .effectiveLevel)
    self.discountedPrice = Decimal(
      string: try container.decodeIfPresent(String.self, forKey: .discountedPrice) ?? "")
  }

  static let mock = Self(
    id: 1,
    firstName: "First",
    lastName: "Last",
    badgeName: "Badge",
    effectiveLevel: EffectiveLevel(name: "Level", price: 30),
    discountedPrice: nil
  )
}

struct EffectiveLevel: Equatable, Codable {
  let name: String
  let price: Decimal

  init(name: String, price: Decimal) {
    self.name = name
    self.price = price
  }

  init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.name = try container.decode(String.self, forKey: .name)
    self.price = Decimal(string: try container.decode(String.self, forKey: .price))!
  }
}

struct TerminalCart: Equatable, Codable {
  let badges: IdentifiedArrayOf<TerminalBadge>
  let charityDonation: Decimal
  let organizationDonation: Decimal
  let totalDiscount: Decimal?
  let total: Decimal
  let paid: Decimal

  init(
    badges: IdentifiedArrayOf<TerminalBadge>,
    charityDonation: Decimal,
    organizationDonation: Decimal,
    totalDiscount: Decimal?,
    total: Decimal,
    paid: Decimal
  ) {
    self.badges = badges
    self.charityDonation = charityDonation
    self.organizationDonation = organizationDonation
    self.totalDiscount = totalDiscount
    self.total = total
    self.paid = paid
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
    self.paid = Decimal(string: try container.decode(String.self, forKey: .paid))!
  }

  static let empty = Self(
    badges: .init(),
    charityDonation: 0,
    organizationDonation: 0,
    totalDiscount: nil,
    total: 0,
    paid: 0
  )

  static let mock = Self(
    badges: .init(uniqueElements: [.mock]),
    charityDonation: 10,
    organizationDonation: 20,
    totalDiscount: nil,
    total: 60,
    paid: 0
  )
}

struct SquareCompletedTransaction: Equatable, Codable {
  let reference: String
  let paymentId: String

  static let mock = Self(
    reference: SquareCheckoutResult.mock.referenceId ?? "",
    paymentId: SquareCheckoutResult.mock.paymentId ?? ""
  )
}

enum ApisError: LocalizedError {
  case invalidHost
  case badResponse(Int)
  case subscriptionError
  case unknownEvent
  case eventsNotConfigured

  var errorDescription: String? {
    switch self {
    case .invalidHost:
      return "API host did not appear to be a valid URL."
    case .badResponse(let statusCode):
      return "Got wrong status code from API: \(statusCode)."
    case .subscriptionError:
      return "Could not subscribe to events."
    case .unknownEvent:
      return "Got unknown event."
    case .eventsNotConfigured:
      return "Events were not yet configured."
    }
  }
}

// MARK: API client interface

@DependencyClient
struct ApisClient {
  internal static let logger = Logger(subsystem: Register.bundle, category: "APIS")

  var requestSquareToken: (Config) async throws -> Void
  var squareTransactionCompleted: (Config, SquareCompletedTransaction) async throws -> Bool

  var setUpEvents: (Config) -> Effect<Result<TerminalEvent, Error>> = { _ in .none }
  var connectEvents: () async throws -> Void
  var disconnectEvents: () async throws -> Void
  var notifyFrontend: (Config, FrontendNotification) async throws -> Void
}

extension ApisClient: TestDependencyKey {
  static var previewValue = Self(
    requestSquareToken: { _ in },
    squareTransactionCompleted: { _, _ in true },
    setUpEvents: { _ in .none },
    connectEvents: {},
    disconnectEvents: {},
    notifyFrontend: { _, _ in }
  )

  static let testValue = Self()
}

extension DependencyValues {
  var apis: ApisClient {
    get { self[ApisClient.self] }
    set { self[ApisClient.self] = newValue }
  }
}
