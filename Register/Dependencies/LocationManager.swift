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
  var delegate: () -> EffectTask<LocationAction>
}

extension LocationManager: DependencyKey {
  static var liveValue: LocationManager {
    let manager = CLLocationManager()

    let delegate = EffectTask<LocationAction>.run { sub in
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
  let subscriber: EffectTask<LocationAction>.Subscriber

  init(_ subscriber: EffectTask<LocationAction>.Subscriber) {
    self.subscriber = subscriber
  }

  func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
    subscriber.send(.didChangeAuthorization(manager.authorizationStatus))
  }
}
