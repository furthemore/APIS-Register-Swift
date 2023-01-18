//
//  SquareSetupView.swift
//  Register
//

import AVFoundation
import Combine
import ComposableArchitecture
import CoreLocation
import SquareReaderSDK
import SwiftUI

struct SquareSetupFeature: ReducerProtocol {
  @Dependency(\.apis) var apis
  @Dependency(\.locationManager) var locationManager

  private enum LocationManagerId: Hashable {}

  struct State: Equatable {
    var locationAuthorizationStatus: CLAuthorizationStatus? = nil
    var recordPermission: AVAudioSession.RecordPermission? = nil
    var isAuthorized = false
    var isFetchingAuthCode = false
    var alertState: AlertState<Action>? = nil
    var config: Config = .empty
  }

  enum Action: Equatable {
    case appeared
    case locationManager(LocationAction)
    case requestLocation
    case recordPermission(AVAudioSession.RecordPermission)
    case requestRecordPermission
    case openSettings
    case setPairingDevice(Bool)
    case getAuthorizationCode
    case fetchedAuthToken
    case alertDismissed
    case setErrorMessage(String, String)
  }

  func reduce(into state: inout State, action: Action) -> EffectTask<Action> {
    switch action {
    case .appeared:
      state.recordPermission = AVAudioSession.sharedInstance().recordPermission
      state.isAuthorized = SQRDReaderSDK.shared.isAuthorized
      let locationManager =
        locationManager
        .delegate()
        .map(Action.locationManager)
        .cancellable(id: LocationManagerId.self)
      return locationManager
    case let .locationManager(.didChangeAuthorization(status)):
      state.locationAuthorizationStatus = status
      return .none
    case .requestLocation:
      locationManager.requestWhenInUseAuthorization()
      return .none
    case let .recordPermission(permission):
      state.recordPermission = permission
      return .none
    case .requestRecordPermission:
      return .task {
        let permission = await withCheckedContinuation { continuation in
          AVAudioSession.sharedInstance().requestRecordPermission { permitted in
            let permission: AVAudioSession.RecordPermission = permitted ? .granted : .denied
            continuation.resume(with: .success(permission))
          }
        }
        return .recordPermission(permission)
      }
    case .openSettings:
      if let url = URL(string: UIApplication.openSettingsURLString) {
        UIApplication.shared.open(url)
      }
      return .none
    case let .setPairingDevice(pairing):
      if pairing == true {
        if let presentedViewController = Register.presentingViewController {
          let settings = SQRDReaderSettingsController(delegate: SquareSettingsDelegate())
          settings.present(from: presentedViewController)
        } else {
          return .task {
            return .setErrorMessage("App Error", "Could not find view to present from.")
          }
        }
      }
      return .none
    case .getAuthorizationCode:
      state.isFetchingAuthCode = true
      return getAuthCode(config: state.config)
    case .fetchedAuthToken:
      state.isFetchingAuthCode = false
      state.isAuthorized = true
      return .none
    case .alertDismissed:
      state.alertState = nil
      return .none
    case let .setErrorMessage(title, message):
      state.isFetchingAuthCode = false
      state.alertState = AlertState(
        title: TextState(title),
        message: TextState(message),
        buttons: [.default(TextState("OK"))]
      )
      return .none
    }
  }

  private func getAuthCode(config: Config) -> EffectTask<Action> {
    return .task {
      let code: String
      do {
        code = try await apis.getSquareToken(config)
      } catch {
        return .setErrorMessage("Error Fetching Token", error.localizedDescription)
      }

      let result: TaskResult<SQRDLocation?> = await withCheckedContinuation { continuation in
        DispatchQueue.main.async {
          SQRDReaderSDK.shared.authorize(
            withCode: code
          ) { loc, error in
            if let error = error {
              continuation.resume(returning: .failure(error))
            } else {
              continuation.resume(returning: .success(loc))
            }
          }
        }
      }

      switch result {
      case .success:
        return .fetchedAuthToken
      case let .failure(error):
        return .setErrorMessage("Reader SDK Error", error.localizedDescription)
      }
    }
  }
}

struct SquareSetupView: View {
  let store: StoreOf<SquareSetupFeature>

  var body: some View {
    NavigationStack {
      WithViewStore(store) { viewStore in
        Form {
          Section("Permissions") {
            switch viewStore.locationAuthorizationStatus {
            case .authorizedWhenInUse, .authorizedAlways:
              Label("Location Authorized", systemImage: "checkmark")
            case .notDetermined:
              Button {
                viewStore.send(.requestLocation)
              } label: {
                Label("Request Location", systemImage: "location")
              }
            default:
              Label("Unknown Location State", systemImage: "wrongwaysign")
            }

            switch viewStore.recordPermission {
            case .granted:
              Label("Microphone Authorized", systemImage: "checkmark")
            case .undetermined:
              Button {
                viewStore.send(.requestRecordPermission)
              } label: {
                Label("Request Microphone", systemImage: "mic")
              }
            default:
              Label("Unknown Microphone State", systemImage: "wrongwaysign")
            }
          }

          Section("Authorization") {
            if viewStore.isAuthorized {
              Label("Reader Authorized", systemImage: "checkmark")
            } else {
              Button {
                viewStore.send(.getAuthorizationCode)
              } label: {
                Label("Get Authorization Code", systemImage: "key.radiowaves.forward.fill")
              }.disabled(viewStore.isFetchingAuthCode)
            }
          }

          Section("Devices") {
            Button {
              viewStore.send(.setPairingDevice(true))
            } label: {
              Label("Pair Device", systemImage: "arrow.triangle.2.circlepath")
            }.disabled(!viewStore.isAuthorized)
          }

          Section("Utilities") {
            Button {
              viewStore.send(.openSettings)
            } label: {
              Label("Open System Preferences", systemImage: "gear")
            }
          }
        }
        .onAppear { viewStore.send(.appeared) }
        .navigationTitle("Square Config")
        .navigationBarTitleDisplayMode(.inline)
        .alert(store.scope(state: \.alertState), dismiss: .alertDismissed)
      }
    }
  }
}

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

class SquareSettingsDelegate: SQRDReaderSettingsControllerDelegate {
  func readerSettingsControllerDidPresent(
    _ readerSettingsController: SQRDReaderSettingsController
  ) {}

  func readerSettingsController(
    _ readerSettingsController: SQRDReaderSettingsController,
    didFailToPresentWith error: Error
  ) {
    fatalError("Could not present reader settings: \(error)")
  }
}

struct SquarePermissionsView_Previews: PreviewProvider {
  static var previews: some View {
    SquareSetupView(
      store: Store(
        initialState: .init(),
        reducer: SquareSetupFeature()
      )
    )
    .previewLayout(.fixed(width: 400, height: 400))
    .previewDisplayName("Default Unknown State")

    SquareSetupView(
      store: Store(
        initialState: .init(
          locationAuthorizationStatus: .authorizedWhenInUse,
          recordPermission: .granted
        ),
        reducer: SquareSetupFeature()
      )
    )
    .previewLayout(.fixed(width: 400, height: 400))
    .previewDisplayName("Approved State")
  }
}
