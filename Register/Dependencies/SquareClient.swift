//
//  SquareClient.swift
//  Register
//

import Combine
import ComposableArchitecture
import UIKit

// MARK: API models

struct SquareLocation: Equatable, Identifiable {
  let id: String
  let name: String
  let businessName: String
  let isCardProcessingActivated: Bool

  init(id: String, name: String, businessName: String, isCardProcessingActivated: Bool) {
    self.id = id
    self.name = name
    self.businessName = businessName
    self.isCardProcessingActivated = isCardProcessingActivated
  }

  static let mock = Self(
    id: "ABC123",
    name: "Test Location",
    businessName: "Test Business",
    isCardProcessingActivated: true
  )
}

struct SquareCheckoutParams: Equatable {
  let amountMoney: Int
  let note: String?
  let allowCash: Bool
}

struct SquareCheckoutResult: Equatable {
  let transactionId: String?
  let transactionClientId: String

  init(transactionId: String, transactionClientId: String) {
    self.transactionId = transactionId
    self.transactionClientId = transactionClientId
  }

  static let mock = Self(
    transactionId: "MOCK-TX-ID",
    transactionClientId: "MOCK-CLIENT-TX-ID"
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

  var errorDescription: String? {
    switch self {
    case .missingViewController:
      return "Could not find UIViewController needed to present."
    }
  }
}

// MARK: API client interface

@DependencyClient
struct SquareClient {
  var initialize: ([UIApplication.LaunchOptionsKey: Any]?) -> Void

  var isAuthorized: () -> Bool = { false }
  var authorizedLocation: () -> SquareLocation?

  var authorize: (String) async throws -> SquareLocation
  var deauthorize: () async throws -> Void

  var openSettings: () async throws -> AsyncStream<SquareSettingsAction>
  var checkout: (SquareCheckoutParams) async throws -> AsyncStream<SquareCheckoutAction>

  @MainActor
  static var presentingViewController: UIViewController? {
    return UIApplication.shared.connectedScenes.filter {
      $0.activationState == .foregroundActive
    }
    .compactMap { $0 as? UIWindowScene }
    .first?
    .windows
    .filter { $0.isKeyWindow }
    .first?
    .rootViewController?
    .presentedViewController
  }
}

extension SquareClient: TestDependencyKey {
  static let previewValue = Self(
    initialize: { _ in },
    isAuthorized: { true },
    authorizedLocation: { .mock },
    authorize: { _ in .mock },
    deauthorize: {},
    openSettings: { .never },
    checkout: { _ in .never }
  )

  static let testValue = Self()
}

extension DependencyValues {
  var square: SquareClient {
    get { self[SquareClient.self] }
    set { self[SquareClient.self] = newValue }
  }
}
