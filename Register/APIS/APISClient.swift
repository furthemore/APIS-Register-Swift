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

struct SquareCompletedTransaction: Equatable, Codable {
  let reference: String
  let transactionID: String
  let clientTransactionID: String
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

struct ApisClient {
  static let logger = Logger(subsystem: Register.bundle, category: "APIS")

  var registerTerminal: (RegisterRequest) async throws -> Config
  var getSquareToken: (Config) async throws -> String
  var squareTransactionCompleted: (Config, SquareCompletedTransaction) async throws -> Bool

  var subscribeToEvents: (Config) throws -> EffectTask<TaskResult<TerminalEvent>>
}

extension ApisClient: TestDependencyKey {
  static var previewValue = Self(
    registerTerminal: { _ in .mock },
    getSquareToken: { _ in "MOCK-SQUARE_TOKEN" },
    squareTransactionCompleted: { _, _ in true },
    subscribeToEvents: { _ in .none }
  )

  static let testValue = Self(
    registerTerminal: unimplemented("\(Self.self).registerTerminal"),
    getSquareToken: unimplemented("\(Self.self).getSquareToken"),
    squareTransactionCompleted: unimplemented("\(Self.self).squareTransactionCompleted"),
    subscribeToEvents: unimplemented("\(Self.self).subscribeToEvents")
  )
}

extension DependencyValues {
  var apis: ApisClient {
    get { self[ApisClient.self] }
    set { self[ApisClient.self] = newValue }
  }
}
