//
//  SquareSettingsDelegate.swift
//  Register
//

#if canImport(SquareReaderSDK)

  import ComposableArchitecture
  import SquareReaderSDK

  class SquareSettingsDelegate: SQRDReaderSettingsControllerDelegate {
    let subscriber: Effect<SquareSettingsAction, Never>.Subscriber

    init(subscriber: Effect<SquareSettingsAction, Never>.Subscriber) {
      self.subscriber = subscriber
    }

    func readerSettingsControllerDidPresent(
      _ readerSettingsController: SQRDReaderSettingsController
    ) {
      subscriber.send(.presented(.success(true)))
    }

    func readerSettingsController(
      _ readerSettingsController: SQRDReaderSettingsController,
      didFailToPresentWith error: Error
    ) {
      subscriber.send(.presented(.failure(error)))
    }
  }

#endif
