//
//  SquareSettingsDelegate.swift
//  Register
//

#if canImport(SquareReaderSDK)

  import ComposableArchitecture
  import SquareReaderSDK

  class SquareSettingsDelegate: SQRDReaderSettingsControllerDelegate {
    let subscriber: EffectTask<SquareSettingsAction>.Subscriber

    init(subscriber: EffectTask<SquareSettingsAction>.Subscriber) {
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
