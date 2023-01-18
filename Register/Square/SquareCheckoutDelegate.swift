//
//  SquareCheckoutDelegate.swift
//  Register
//

import ComposableArchitecture
import SquareReaderSDK

enum SquareCheckoutAction: Equatable {
  case cancelled
  case finished(TaskResult<SQRDCheckoutResult>)
}

class SquareCheckoutDelegate: NSObject, SQRDCheckoutControllerDelegate {
  let subscriber: Effect<SquareCheckoutAction, Never>.Subscriber

  init(_ subscriber: Effect<SquareCheckoutAction, Never>.Subscriber) {
    self.subscriber = subscriber
  }

  func checkoutControllerDidCancel(_ checkoutController: SQRDCheckoutController) {
    subscriber.send(.cancelled)
  }

  func checkoutController(_ checkoutController: SQRDCheckoutController, didFailWith error: Error) {
    subscriber.send(.finished(.failure(error)))
  }

  func checkoutController(
    _ checkoutController: SQRDCheckoutController, didFinishCheckoutWith result: SQRDCheckoutResult
  ) {
    subscriber.send(.finished(.success(result)))
  }
}
