//
//  SquareSetupView.swift
//  Register
//

import AVFoundation
import AsyncAlgorithms
import Combine
import ComposableArchitecture
import CoreBluetooth
import CoreLocation
import SwiftUI

@Reducer
struct SquareSetupFeature {
  @Dependency(\.apis) var apis
  @Dependency(\.square) var square
  @Dependency(\.avAudioSession) var avAudioSession
  @Dependency(\.locationManager) var locationManager
  @Dependency(\.bluetoothManager) var bluetoothManager

  @ObservableState
  struct State: Equatable {
    @Presents var alert: AlertState<Action.Alert>? = nil
    var locationAuthorizationStatus: CLAuthorizationStatus? = nil
    var recordPermission: RecordPermission? = nil
    var bluetoothAuthorizationStatus: CBManagerAuthorization? = nil
    var isAuthorized = false
    var authorizedLocation: SquareLocation? = nil
    var isAuthorizing = false
    var config: Config = .empty
  }

  enum Action: Equatable {
    case appeared
    case locationManager(LocationAction)
    case bluetoothManager(BluetoothAction)
    case requestLocation
    case requestBluetooth
    case recordPermission(RecordPermission)
    case requestRecordPermission
    case openSettings
    case openSquareSettings
    case getAuthorizationCode
    case authorized
    case removeAuthorization
    case didRemoveAuthorization
    case alert(PresentationAction<Alert>)
    case setErrorMessage(String, String)

    enum Alert: Equatable {}
  }

  private enum CancelID { case authorizationManagers }

  var body: some ReducerOf<Self> {
    Reduce { state, action in
      switch action {
      case .appeared:
        state.recordPermission = avAudioSession.recordPermission()
        state.authorizedLocation = square.authorizedLocation()
        state.isAuthorized = square.isAuthorized()
        state.bluetoothAuthorizationStatus = bluetoothManager.authorization()
        return .run { @MainActor send in
          let locationActions = locationManager.delegate().map(Action.locationManager)
          let bluetoothActions = bluetoothManager.delegate().map(Action.bluetoothManager)
          for await action in merge(locationActions, bluetoothActions) {
            send(action)
          }
        }
        .cancellable(id: CancelID.authorizationManagers, cancelInFlight: true)
      case let .locationManager(.didChangeAuthorization(status)):
        state.locationAuthorizationStatus = status
        return .none
      case let .bluetoothManager(.didChangeAuthorization(status)):
        state.bluetoothAuthorizationStatus = status
        return .none
      case .requestLocation:
        locationManager.requestWhenInUseAuthorization()
        return .none
      case .requestBluetooth:
        bluetoothManager.requestAuthorization()
        return .none
      case let .recordPermission(permission):
        state.recordPermission = permission
        return .none
      case .requestRecordPermission:
        return avAudioSession.requestRecordPermission().map(Action.recordPermission)
      case .openSettings:
        if let url = URL(string: UIApplication.openSettingsURLString) {
          UIApplication.shared.open(url)
        }
        return .none
      case .openSquareSettings:
        return .run { send in
          do {
            try await square.openSettings()
          } catch {
            await send(
              .setErrorMessage(
                "App Error",
                error.localizedDescription
              ))
          }
        }
      case .getAuthorizationCode:
        state.isAuthorizing = true
        return authorize(config: state.config)
      case .authorized:
        state.isAuthorizing = false
        state.isAuthorized = true
        state.authorizedLocation = square.authorizedLocation()
        return .none
      case .removeAuthorization:
        state.isAuthorizing = true
        return .run { send in
          do {
            try await square.deauthorize()
            await send(.didRemoveAuthorization)
          } catch {
            await send(
              .setErrorMessage(
                "Square Error",
                error.localizedDescription
              ))
          }
        }.animation(.easeInOut)
      case .didRemoveAuthorization:
        state.isAuthorizing = false
        state.isAuthorized = false
        state.authorizedLocation = nil
        return .none
      case .alert:
        return .none
      case let .setErrorMessage(title, message):
        state.isAuthorizing = false
        state.alert = AlertState {
          TextState(title)
        } message: {
          TextState(message)
        }
        return .none
      }
    }
    .ifLet(\.alert, action: \.alert)
  }

  private func authorize(config: Config) -> Effect<Action> {
    return .run { send in
      do {
        try await apis.requestSquareToken(config)
      } catch {
        return await send(
          .setErrorMessage(
            "Error Requesting Token",
            error.localizedDescription
          )
        )
      }
    }
  }
}

struct SquareSetupView: View {
  @Bindable var store: StoreOf<SquareSetupFeature>

  var body: some View {
    NavigationStack {
      Form {
        permissions
        authorization

        Section("Square") {
          Button {
            store.send(.openSquareSettings)
          } label: {
            Label("Square Settings", systemImage: "gearshape")
          }
        }

        location
      }
      .onAppear { store.send(.appeared) }
      .navigationTitle("Square Config")
      .navigationBarTitleDisplayMode(.inline)
      .alert(
        store: store.scope(state: \.$alert, action: \.alert)
      )
    }
  }

  @ViewBuilder
  var permissions: some View {
    Section("Permissions") {
      switch store.locationAuthorizationStatus {
      case .authorizedWhenInUse, .authorizedAlways:
        Label("Location Authorized", systemImage: "checkmark")
      case .notDetermined:
        Button {
          store.send(.requestLocation)
        } label: {
          Label("Request Location", systemImage: "location")
        }
      default:
        Label("Unknown Location State", systemImage: "wrongwaysign")
      }

      switch store.bluetoothAuthorizationStatus {
      case .allowedAlways:
        Label("Bluetooth Authorized", systemImage: "checkmark")
      case .notDetermined:
        Button {
          store.send(.requestBluetooth)
        } label: {
          Label("Request Bluetooth", systemImage: "location")
        }
      default:
        Label("Unknown Bluetooth State", systemImage: "wrongwaysign")
      }

      switch store.recordPermission {
      case .granted:
        Label("Microphone Authorized", systemImage: "checkmark")
      case .undetermined:
        Button {
          store.send(.requestRecordPermission)
        } label: {
          Label("Request Microphone", systemImage: "mic")
        }
      default:
        Label("Unknown Microphone State", systemImage: "wrongwaysign")
      }

      Button {
        store.send(.openSettings)
      } label: {
        Label("Open System Preferences", systemImage: "gear")
      }
    }
  }

  @ViewBuilder
  var authorization: some View {
    Section("Authorization") {
      if store.isAuthorized {
        Label("Payments Authorized", systemImage: "checkmark")
          .contextMenu {
            Button(role: .destructive) {
              store.send(.removeAuthorization, animation: .easeInOut)
            } label: {
              Label("Remove Authorization", systemImage: "trash")
            }
          }
      } else {
        Button {
          store.send(.getAuthorizationCode, animation: .easeInOut)
        } label: {
          HStack {
            Label("Request Authorization Code", systemImage: "key.horizontal")
            if store.isAuthorizing {
              ProgressView()
            }
          }
        }
        .disabled(store.isAuthorizing)
      }
    }
  }

  @ViewBuilder
  var location: some View {
    Section("Location") {
      if let location = store.authorizedLocation {
        LocationDetailView(
          name: "Location ID",
          value: location.id
        )
        LocationDetailView(
          name: "Location Name",
          value: location.name
        )
        LocationDetailView(
          name: "Merchant Category Code",
          value: location.mcc
        )
        LocationDetailView(
          name: "Currency",
          value: location.currency.currencyCode
        )
      } else if store.isAuthorized {
        Label("Unknown Location", systemImage: "exclamationmark.questionmark")
      } else {
        Label("Pending Authorization", systemImage: "globe.desk")
      }
    }
  }
}

struct SquareSetupView_Previews: PreviewProvider {
  static var previews: some View {
    SquareSetupView(
      store: Store(
        initialState: .init(),
        reducer: {
          SquareSetupFeature()
        },
        withDependencies: {
          $0.square.authorizedLocation = { nil }
        })
    )
    .previewLayout(.fixed(width: 400, height: 400))
    .previewDisplayName("Default Unknown State")

    SquareSetupView(
      store: Store(
        initialState: .init(
          locationAuthorizationStatus: .authorizedWhenInUse,
          recordPermission: .granted,
          isAuthorized: true
        )
      ) {
        SquareSetupFeature()
      }
    )
    .previewLayout(.fixed(width: 400, height: 400))
    .previewDisplayName("Approved State")

    SquareSetupView(
      store: Store(
        initialState: .init(
          alert: AlertState {
            TextState("Title")
          } message: {
            TextState("Message")
          }
        )
      ) {
        SquareSetupFeature()
      }
    )
    .previewLayout(.fixed(width: 400, height: 400))
    .previewDisplayName("Alerting State")
  }
}
