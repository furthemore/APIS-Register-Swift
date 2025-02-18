//
//  SquareClient.swift
//  Register
//

import Combine
import ComposableArchitecture
import SquareMobilePaymentsSDK
import UIKit

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

  init(paymentId: String?, referenceId: String?) {
    self.paymentId = paymentId
    self.referenceId = referenceId
  }

  static let mock = Self(
    paymentId: "MOCK-TX-ID",
    referenceId: "MOCK-CLIENT-TX-ID"
  )
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

  var errorDescription: String? {
    switch self {
    case .missingViewController:
      return "Could not find UIViewController needed to present."
    case .noMockReaderUI:
      return "No mock reader UI was present."
    }
  }
}

// MARK: API client interface

@DependencyClient
struct SquareClient {
  var initialize: ([UIApplication.LaunchOptionsKey: Any]?) -> Void

  var isAuthorized: () -> Bool = { false }
  var authorizedLocation: () -> SquareLocation?

  var authorize: (String, String) async throws -> Void
  var deauthorize: () async throws -> Void

  var openSettings: () async throws -> Void
  var checkout: (PaymentParameters) async throws -> AsyncStream<SquareCheckoutAction>

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
