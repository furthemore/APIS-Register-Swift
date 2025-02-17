//
//  SquareCheckoutDelegate.swift
//  Register
//

#if canImport(SquareReaderSDK)

  import Combine
  import ComposableArchitecture
  import SquareReaderSDK

  class SquareCheckoutDelegate: NSObject, SQRDCheckoutControllerDelegate {
    let continuation: AsyncStream<SquareCheckoutAction>.Continuation

    init(_ continuation: AsyncStream<SquareCheckoutAction>.Continuation) {
      self.continuation = continuation
    }
    
    deinit {
      continuation.finish()
    }

    func checkoutControllerDidCancel(_ checkoutController: SQRDCheckoutController) {
      continuation.yield(.cancelled)
      continuation.finish()
    }

    func checkoutController(
      _ checkoutController: SQRDCheckoutController,
      didFailWith error: Error
    ) {
      continuation.yield(.finished(.failure(error)))
      continuation.finish()
    }

    func checkoutController(
      _ checkoutController: SQRDCheckoutController,
      didFinishCheckoutWith result: SQRDCheckoutResult
    ) {
      continuation.yield(.finished(.success(SquareCheckoutResult(result))))
      continuation.finish()
    }
  }

#endif
