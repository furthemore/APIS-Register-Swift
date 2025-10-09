//
//  BluetoothManager.swift
//  Register
//

import Combine
import ComposableArchitecture
import CoreBluetooth

@DependencyClient
struct BluetoothManager {
  var authorization: () -> CBManagerAuthorization = { .denied }
  var requestAuthorization: () -> Void
  var delegate: () -> AsyncStream<BluetoothAction> = { .never }
}

extension BluetoothManager: DependencyKey {
  @MainActor static var liveValue: BluetoothManager {
    let bluetoothManagerClient = BluetoothManagerClient()

    return Self(
      authorization: { CBCentralManager.authorization },
      requestAuthorization: bluetoothManagerClient.requestAuthorization,
      delegate: bluetoothManagerClient.delegate
    )
  }
}

extension BluetoothManager: TestDependencyKey {
  static var previewValue = Self(
    authorization: { .allowedAlways },
    requestAuthorization: {},
    delegate: { .never }
  )

  static var testValue = Self()
}

extension DependencyValues {
  var bluetoothManager: BluetoothManager {
    get { self[BluetoothManager.self] }
    set { self[BluetoothManager.self] = newValue }
  }
}

enum BluetoothAction: Equatable {
  case didChangeAuthorization(CBManagerAuthorization)
}

@MainActor
class BluetoothManagerClient: NSObject {
  @MainActor var bluetoothManager: CBCentralManager? = nil
  let passthroughSubject = PassthroughSubject<BluetoothAction, Never>()

  @MainActor
  override init() {
    super.init()
  }

  func requestAuthorization() {
    bluetoothManager = CBCentralManager(delegate: self, queue: .main)
  }

  func delegate() -> AsyncStream<BluetoothAction> {
    return AsyncStream { continuation in
      var previousAuthorization: CBManagerAuthorization? = nil
      let subscription = self.passthroughSubject.sink { value in
        switch value {
        case .didChangeAuthorization(let newAuthorization):
          if previousAuthorization != newAuthorization {
            continuation.yield(value)
            previousAuthorization = newAuthorization
          }
        }
      }

      continuation.onTermination = { _ in subscription.cancel() }
    }
  }
}

@MainActor
extension BluetoothManagerClient: @preconcurrency CBCentralManagerDelegate {
  func centralManagerDidUpdateState(_ central: CBCentralManager) {
    passthroughSubject.send(.didChangeAuthorization(CBCentralManager.authorization))
  }
}
