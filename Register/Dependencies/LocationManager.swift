//
//  LocationManager.swift
//  Register
//

import Combine
import ComposableArchitecture
import CoreLocation

@DependencyClient
struct LocationManager {
  var authorizationStatus: () -> CLAuthorizationStatus = { .denied }
  var requestWhenInUseAuthorization: () -> Void
  var delegate: () -> AsyncStream<LocationAction> = { .never }
}

extension LocationManager: DependencyKey {
  @MainActor static var liveValue: LocationManager {
    let locationManagerClient = LocationManagerClient()

    return Self(
      authorizationStatus: { locationManagerClient.authorizationStatus },
      requestWhenInUseAuthorization: locationManagerClient.requestWhenInUseAuthorization,
      delegate: locationManagerClient.delegate
    )
  }
}

extension LocationManager: TestDependencyKey {
  static var previewValue = Self(
    authorizationStatus: { .authorizedAlways },
    requestWhenInUseAuthorization: {},
    delegate: { .never }
  )

  static var testValue = Self()
}

extension DependencyValues {
  var locationManager: LocationManager {
    get { self[LocationManager.self] }
    set { self[LocationManager.self] = newValue }
  }
}

enum LocationAction: Equatable {
  case didChangeAuthorization(CLAuthorizationStatus)
}

@MainActor
class LocationManagerClient: NSObject {
  @MainActor let locationManager = CLLocationManager()
  let passthroughSubject = PassthroughSubject<LocationAction, Never>()

  @MainActor
  override init() {
    super.init()
    self.locationManager.delegate = self
  }

  var authorizationStatus: CLAuthorizationStatus {
    locationManager.authorizationStatus
  }

  func requestWhenInUseAuthorization() {
    locationManager.requestWhenInUseAuthorization()
  }

  func delegate() -> AsyncStream<LocationAction> {
    return AsyncStream { continuation in
      let subscription = self.passthroughSubject.sink { value in
        continuation.yield(value)
      }

      continuation.onTermination = { _ in subscription.cancel() }
    }
  }
}

@MainActor
extension LocationManagerClient: @preconcurrency CLLocationManagerDelegate {
  func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
    passthroughSubject.send(.didChangeAuthorization(manager.authorizationStatus))
  }
}
