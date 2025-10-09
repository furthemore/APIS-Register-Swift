//
//  SquareCheckoutDelegate.swift
//  Register
//

import Combine
import ComposableArchitecture
import ObjectiveC
import SquareMobilePaymentsSDK

final class SquareCheckoutDelegate: NSObject, Sendable, PaymentManagerDelegate {
  let continuation: AsyncStream<SquareCheckoutAction>.Continuation

  init(_ continuation: AsyncStream<SquareCheckoutAction>.Continuation) {
    self.continuation = continuation
  }

  deinit {
    continuation.finish()
  }

  func paymentManager(_ paymentManager: any PaymentManager, didFinish payment: any Payment) {
    continuation.yield(.finished(.success(SquareCheckoutResult(payment))))
    continuation.finish()
  }

  func paymentManager(
    _ paymentManager: any PaymentManager, didFail payment: any Payment, withError error: any Error
  ) {
    continuation.yield(.finished(.failure(error)))
    continuation.finish()
  }

  func paymentManager(_ paymentManager: any PaymentManager, didCancel payment: any Payment) {
    continuation.yield(.cancelled)
    continuation.finish()
  }
}
