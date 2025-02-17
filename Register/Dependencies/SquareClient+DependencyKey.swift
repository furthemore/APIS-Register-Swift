//
//  SquareClient+Live.swift
//  Register
//

import Combine
import ComposableArchitecture

#if canImport(SquareReaderSDK)

  import SquareReaderSDK

  extension SquareLocation {
    init(_ location: SQRDLocation) {
      id = location.locationID
      name = location.name
      businessName = location.businessName
      isCardProcessingActivated = location.isCardProcessingActivated
    }
  }

  extension SquareCheckoutResult {
    init(_ checkoutResult: SQRDCheckoutResult) {
      transactionId = checkoutResult.transactionID
      transactionClientId = checkoutResult.transactionClientID
    }
  }

  extension SquareClient: DependencyKey {
    static let liveValue: SquareClient = Self(
      initialize: { launchOptions in
        SQRDReaderSDK.initialize(applicationLaunchOptions: launchOptions)
      },
      isAuthorized: { SQRDReaderSDK.shared.isAuthorized },
      authorizedLocation: { SQRDReaderSDK.shared.authorizedLocation.map { SquareLocation($0) } },
      authorize: { code in
        return try await withCheckedThrowingContinuation { cont in
          DispatchQueue.main.async {
            SQRDReaderSDK.shared.authorize(withCode: code) { loc, error in
              if let error = error {
                cont.resume(throwing: error)
              } else if let loc = loc {
                cont.resume(returning: SquareLocation(loc))
              } else {
                fatalError("Square SDK did not return location or error")
              }
            }
          }
        }
      },
      deauthorize: {
        return try await withCheckedThrowingContinuation { cont in
          DispatchQueue.main.async {
            SQRDReaderSDK.shared.deauthorize { error in
              if let error = error {
                cont.resume(throwing: error)
              } else {
                cont.resume(returning: ())
              }
            }
          }
        }
      },
      openSettings: {
        guard let presentingView = SquareClient.presentingViewController else {
          throw SquareError.missingViewController
        }

        return AsyncStream { continuation in
          let delegate = SquareSettingsDelegate(continuation)

          DispatchQueue.main.async {
            let controller = SQRDReaderSettingsController(delegate: delegate)
            controller.present(from: presentingView)
          }

          continuation.onTermination = { _ in
            _ = delegate
          }
        }
      },
      checkout: { params in
        guard let presentingView = SquareClient.presentingViewController else {
          throw SquareError.missingViewController
        }

        let amountMoney = SQRDMoney(amount: params.amountMoney)
        let checkoutParams = SQRDCheckoutParameters(amountMoney: amountMoney)
        checkoutParams.note = params.note
        checkoutParams.additionalPaymentTypes = params.allowCash ? [.cash] : []

        return AsyncStream { continuation in
          let delegate = SquareCheckoutDelegate(continuation)
          
          DispatchQueue.main.async {
            let controller = SQRDCheckoutController(parameters: checkoutParams, delegate: delegate)
            controller.present(from: presentingView)
          }

          continuation.onTermination = { _ in
            _ = delegate
          }
        }
      }
    )
  }

#else

  extension SquareClient: DependencyKey {
    static let liveValue: SquareClient = Self(
      initialize: { _ in },
      isAuthorized: { true },
      authorizedLocation: { .mock },
      authorize: { _ in .mock },
      deauthorize: {},
      openSettings: {
        AsyncStream { continuation in
          continuation.yield(.presented(.success(true)))
        }
      },
      checkout: { params in
        AsyncStream { continuation in
          continuation.yield(
            .finished(
              .success(
                .init(
                  transactionId: "TEST-TX-ID",
                  transactionClientId: "TEST-CLIENT-TX-ID"
                )
              )))
          continuation.finish()
        }
      }
    )
  }

#endif
