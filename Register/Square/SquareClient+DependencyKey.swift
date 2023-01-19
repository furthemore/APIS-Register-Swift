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
        guard let presentingView = Register.presentingViewController else {
          throw SquareError.missingViewController
        }

        return Effect<SquareSettingsAction, Never>.run { sub in
          let delegate = SquareSettingsDelegate(subscriber: sub)

          DispatchQueue.main.async {
            let controller = SQRDReaderSettingsController(delegate: delegate)
            controller.present(from: presentingView)
          }

          return AnyCancellable {
            _ = delegate
          }
        }
      },
      checkout: { params in
        guard let presentingView = Register.presentingViewController else {
          throw SquareError.missingViewController
        }

        let amountMoney = SQRDMoney(amount: params.amountMoney)
        let checkoutParams = SQRDCheckoutParameters(amountMoney: amountMoney)
        checkoutParams.note = params.note
        checkoutParams.additionalPaymentTypes = params.allowCash ? [.cash] : []

        return Effect<SquareCheckoutAction, Never>.run { sub in
          let delegate = SquareCheckoutDelegate(sub)

          DispatchQueue.main.async {
            let controller = SQRDCheckoutController(parameters: checkoutParams, delegate: delegate)
            controller.present(from: presentingView)
          }

          return AnyCancellable {
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
        return .task {
          return .presented(.success(true))
        }
      },
      checkout: { params in
        return .task {
          return .finished(
            .success(
              .init(
                transactionId: "TEST-TX-ID",
                transactionClientId: "TEST-CLIENT-TX-ID"
              )))
        }
      }
    )
  }

#endif
