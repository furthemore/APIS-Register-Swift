//
//  SquareSettingsDelegate.swift
//  Register
//

#if canImport(SquareReaderSDK)

  import Combine
  import ComposableArchitecture
  import SquareReaderSDK

  class SquareSettingsDelegate: SQRDReaderSettingsControllerDelegate {
    let continuation: AsyncStream<SquareSettingsAction>.Continuation

    init(_ continuation: AsyncStream<SquareSettingsAction>.Continuation) {
      self.continuation = continuation
    }
    
    deinit {
      continuation.finish()
    }

    func readerSettingsControllerDidPresent(
      _ readerSettingsController: SQRDReaderSettingsController
    ) {
      continuation.yield(.presented(.success(true)))
    }

    func readerSettingsController(
      _ readerSettingsController: SQRDReaderSettingsController,
      didFailToPresentWith error: Error
    ) {
      continuation.yield(.presented(.failure(error)))
      continuation.finish()
    }
  }

#endif
