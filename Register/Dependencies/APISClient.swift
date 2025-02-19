//
//  APIS.swift
//  Register
//

import ComposableArchitecture
import Foundation
import os

// MARK: API models

enum TerminalEvent: Equatable, Codable {
  case connected
  case open, close, ready
  case clearCart
  case processPayment(orderId: String?, total: UInt, note: String, reference: String)
  case updateCart(cart: TerminalCart)
  case updateToken(accessToken: String)
  case updateConfig(config: Config)
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
    }
  }
}

// MARK: API client interface

@DependencyClient
struct ApisClient {
  internal static let logger = Logger(subsystem: Register.bundle, category: "APIS")

  var requestSquareToken: (Config) async throws -> Void
  var squareTransactionCompleted: (Config, SquareCompletedTransaction) async throws -> Bool

  var subscribeToEvents: (Config) throws -> Effect<TaskResult<TerminalEvent>>
}

extension ApisClient: TestDependencyKey {
  static var previewValue = Self(
    requestSquareToken: { _ in },
    squareTransactionCompleted: { _, _ in true },
    subscribeToEvents: { _ in .none }
  )

  static let testValue = Self()
}

extension DependencyValues {
  var apis: ApisClient {
    get { self[ApisClient.self] }
    set { self[ApisClient.self] = newValue }
  }
}
