//
//  LocationManager.swift
//  Register
//

import Combine
import ComposableArchitecture
import CoreLocation

struct LocationManager {
  var authorizationStatus: () -> CLAuthorizationStatus
  var requestWhenInUseAuthorization: () -> Void
  var delegate: () -> Effect<LocationAction, Never>
}

extension LocationManager: DependencyKey {
  static var liveValue: LocationManager {
    let manager = CLLocationManager()

    let delegate = Effect<LocationAction, Never>.run { sub in
      let delegate = LocationManagerDelegate(sub)
      manager.delegate = delegate

      return AnyCancellable {
        _ = delegate
      }
    }

    return Self(
      authorizationStatus: {
        return manager.authorizationStatus
      },
      requestWhenInUseAuthorization: {
        manager.requestWhenInUseAuthorization()
      },
      delegate: { delegate }
    )
  }
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

private class LocationManagerDelegate: NSObject, CLLocationManagerDelegate {
  let subscriber: Effect<LocationAction, Never>.Subscriber

  init(_ subscriber: Effect<LocationAction, Never>.Subscriber) {
    self.subscriber = subscriber
  }

  func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
    subscriber.send(.didChangeAuthorization(manager.authorizationStatus))
  }
}
