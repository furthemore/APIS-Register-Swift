//
//  SquareClient.swift
//  Register
//

import Combine
import ComposableArchitecture
import SquareMobilePaymentsSDK
import UIKit
import os

// MARK: API models

class SquareLocation: NSObject, Identifiable, Location {
  let id: String
  let name: String
  let mcc: String
  let currency: Currency

  required init(id: String, name: String, mcc: String, currency: Currency) {
    self.id = id
    self.name = name
    self.mcc = mcc
    self.currency = currency
  }

  static let mock = SquareLocation(
    id: "ABC123",
    name: "Test Location",
    mcc: "TEST",
    currency: .USD
  )
}

struct SquareCheckoutParams: Equatable {
  let amountMoney: Int
  let note: String?
}

struct SquareCheckoutResult: Equatable {
  let paymentId: String?
  let referenceId: String?

  static let mock = Self(
    paymentId: "MOCK-TX-ID",
    referenceId: "MOCK-CLIENT-TX-ID"
  )
}

struct SquarePaymentParams: Equatable {
  let paymentAttemptId: String
  let amountMoney: Money
  let referenceId: String
  let orderId: String?
  let note: String?
}

enum SquareSettingsAction: Equatable {
  case presented(TaskResult<Bool>)
}

enum SquareCheckoutAction: Equatable {
  case cancelled
  case finished(TaskResult<SquareCheckoutResult>)
}

enum SquareError: Equatable, LocalizedError {
  case missingViewController
  case noMockReaderUI
  case notInitialized

  var errorDescription: String? {
    switch self {
    case .missingViewController:
      return "Could not find UIViewController needed to present."
    case .noMockReaderUI:
      return "No mock reader UI was present."
    case .notInitialized:
      return "Square SDK was not initialized on app launch."
    }
  }
}

// MARK: API client interface

@DependencyClient
struct SquareClient {
  internal static let logger = Logger(subsystem: Register.bundle, category: "Square")

  var initialize: ([UIApplication.LaunchOptionsKey: Any]?) -> Void
  var wasInitialized: () -> Bool = { false }
  var environment: () -> Environment = { .sandbox }

  var isAuthorized: () -> Bool = { false }
  var authorizedLocation: () -> SquareLocation?

  var authorize: (String, String) async throws -> Void
  var deauthorize: () async throws -> Void

  var openSettings: () async throws -> Void
  var checkout: (SquarePaymentParams) async throws -> AsyncStream<SquareCheckoutAction>

  var showMockReader: () throws -> Void
  var hideMockReader: () -> Void

  @MainActor
  static var presentingViewController: UIViewController? {
    return UIApplication.shared.connectedScenes.filter {
      $0.activationState == .foregroundActive
    }
    .compactMap { $0 as? UIWindowScene }
    .flatMap { $0.windows }
    .filter { $0.isKeyWindow }
    .compactMap { $0.rootViewController }
    .compactMap { $0.presentedViewController }
    .first
  }
}

extension SquareClient: TestDependencyKey {
  static let previewValue = Self(
    initialize: { _ in },
    wasInitialized: { true },
    environment: { .sandbox },
    isAuthorized: { true },
    authorizedLocation: { SquareLocation.mock },
    authorize: { _, _ in },
    deauthorize: {},
    openSettings: {},
    checkout: { _ in .never },
    showMockReader: {},
    hideMockReader: {}
  )

  static let testValue = Self()
}

extension DependencyValues {
  var square: SquareClient {
    get { self[SquareClient.self] }
    set { self[SquareClient.self] = newValue }
  }
}
