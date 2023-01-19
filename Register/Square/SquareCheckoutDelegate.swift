//
//  SquareCheckoutDelegate.swift
//  Register
//

#if canImport(SquareReaderSDK)

  import ComposableArchitecture
  import SquareReaderSDK

  class SquareCheckoutDelegate: NSObject, SQRDCheckoutControllerDelegate {
    let subscriber: Effect<SquareCheckoutAction, Never>.Subscriber

    init(_ subscriber: Effect<SquareCheckoutAction, Never>.Subscriber) {
      self.subscriber = subscriber
    }

    func checkoutControllerDidCancel(_ checkoutController: SQRDCheckoutController) {
      subscriber.send(.cancelled)
    }

    func checkoutController(
      _ checkoutController: SQRDCheckoutController,
      didFailWith error: Error
    ) {
      subscriber.send(.finished(.failure(error)))
    }

    func checkoutController(
      _ checkoutController: SQRDCheckoutController,
      didFinishCheckoutWith result: SQRDCheckoutResult
    ) {
      subscriber.send(.finished(.success(SquareCheckoutResult(result))))
    }
  }

#endif
