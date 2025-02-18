//
//  SquareClient+Live.swift
//  Register
//

import Combine
import ComposableArchitecture
import MockReaderUI
import SquareMobilePaymentsSDK

extension SquareLocation {
  convenience init(_ location: any Location) {
    self.init(
      id: location.id,
      name: location.name,
      mcc: location.mcc,
      currency: location.currency
    )
  }
}

extension SquareCheckoutResult {
  init(_ payment: Payment) {
    self.paymentId = payment.id
    self.referenceId = payment.referenceID
  }
}

extension SquareClient: DependencyKey {
  private static var mockReaderUI: MockReaderUI? = {
    do {
      return try MockReaderUI(for: MobilePaymentsSDK.shared)
    } catch {
      assertionFailure("Could not instantiate a mock reader UI: \(error.localizedDescription)")
    }

    return nil
  }()

  static let liveValue: SquareClient = Self(
    initialize: { launchOptions in
      MobilePaymentsSDK.initialize(
        applicationLaunchOptions: launchOptions,
        squareApplicationID: Register.squareApplicationId
      )
    },
    isAuthorized: { MobilePaymentsSDK.shared.authorizationManager.state == .authorized },
    authorizedLocation: {
      if let location = MobilePaymentsSDK.shared.authorizationManager.location {
        SquareLocation(location)
      } else {
        nil
      }
    },
    authorize: { accessToken, locationId in
      return try await withCheckedThrowingContinuation { continuation in
        DispatchQueue.main.async {
          MobilePaymentsSDK.shared.authorizationManager.authorize(
            withAccessToken: accessToken, locationID: locationId
          ) { error in
            if let error {
              continuation.resume(throwing: error)
            } else {
              continuation.resume(returning: ())
            }
          }
        }
      }
    },
    deauthorize: {
      return try await withCheckedThrowingContinuation { continuation in
        DispatchQueue.main.async {
          MobilePaymentsSDK.shared.authorizationManager.deauthorize {
            continuation.resume(returning: ())
          }
        }
      }
    },
    openSettings: {
      guard let presentingView = SquareClient.presentingViewController else {
        throw SquareError.missingViewController
      }

      return try await withCheckedThrowingContinuation { continuation in
        DispatchQueue.main.async {
          MobilePaymentsSDK.shared.settingsManager.presentSettings(with: presentingView) { error in
            if let error {
              continuation.resume(throwing: error)
            } else {
              continuation.resume(returning: ())
            }
          }
        }
      }
    },
    checkout: { paymentParams in
      guard let presentingView = SquareClient.presentingViewController else {
        throw SquareError.missingViewController
      }

      return AsyncStream { continuation in
        let delegate = SquareCheckoutDelegate(continuation)

        DispatchQueue.main.async {
          let paymentHandle = MobilePaymentsSDK.shared.paymentManager.startPayment(
            paymentParams,
            promptParameters: PromptParameters(
              mode: .default,
              additionalMethods: AdditionalPaymentMethods()
            ),
            from: presentingView,
            delegate: delegate
          )

          continuation.onTermination = { _ in
            _ = delegate
            _ = paymentHandle
          }
        }
      }
    },
    showMockReader: {
      if let mockReaderUI {
        try mockReaderUI.present()
      } else {
        throw SquareError.noMockReaderUI
      }
    },
    hideMockReader: {
      mockReaderUI?.dismiss()
    }
  )
}
