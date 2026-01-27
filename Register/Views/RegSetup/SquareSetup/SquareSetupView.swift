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

    var recordPermission: RecordPermission? = nil
    var locationAuthorizationStatus: CLAuthorizationStatus? = nil
    var bluetoothAuthorizationStatus: CBManagerAuthorization? = nil

    var isAuthorizingSquare = false
    var hasAuthorizedSquare = false
    var squareAuthorizedLocation: SquareLocation? = nil

    var config: Config

    var viewController = UIViewController()
  }

  enum Action: Equatable {
    case appeared

    case requestLocation
    case requestBluetooth
    case requestRecordPermission

    case locationManager(LocationAction)
    case bluetoothManager(BluetoothAction)
    case gotRecordPermission(RecordPermission)

    case openSettings
    case openSquareSettings
    case getAuthorizationCode
    case authorized
    case removeAuthorization
    case didRemoveAuthorization
    case setErrorMessage(String, String)

    case alert(PresentationAction<Alert>)

    enum Alert: Equatable {}
  }

  private enum CancelID { case authorizationManagers }

  var body: some ReducerOf<Self> {
    Reduce { state, action in
      switch action {
      case .appeared:
        state.recordPermission = avAudioSession.recordPermission()
        state.squareAuthorizedLocation = square.authorizedLocation()
        state.hasAuthorizedSquare = square.isAuthorized()
        state.bluetoothAuthorizationStatus = bluetoothManager.authorization()
        return .run { @MainActor send in
          let locationActions = locationManager.delegate().map(Action.locationManager)
          let bluetoothActions = bluetoothManager.delegate().map(Action.bluetoothManager)
          for await action in merge(locationActions, bluetoothActions) {
            send(action)
          }
        }
        .cancellable(id: CancelID.authorizationManagers, cancelInFlight: true)

      case .requestLocation:
        locationManager.requestWhenInUseAuthorization()
        return .none
      case .requestBluetooth:
        bluetoothManager.requestAuthorization()
        return .none
      case .requestRecordPermission:
        return avAudioSession.requestRecordPermission().map(Action.gotRecordPermission)

      case .locationManager(.didChangeAuthorization(let status)):
        state.locationAuthorizationStatus = status
        return .none
      case .bluetoothManager(.didChangeAuthorization(let status)):
        state.bluetoothAuthorizationStatus = status
        return .none
      case .gotRecordPermission(let permission):
        state.recordPermission = permission
        return .none

      case .openSettings:
        if let url = URL(string: UIApplication.openSettingsURLString) {
          UIApplication.shared.open(url)
        }
        return .none
      case .openSquareSettings:
        return .run { [viewController = state.viewController] send in
          do {
            try await square.openSettings(viewController)
          } catch {
            await send(
              .setErrorMessage(
                "App Error",
                error.localizedDescription
              ))
          }
        }
      case .getAuthorizationCode:
        state.isAuthorizingSquare = true
        return authorize(config: state.config)
      case .authorized:
        state.isAuthorizingSquare = false
        state.hasAuthorizedSquare = true
        state.squareAuthorizedLocation = square.authorizedLocation()
        return .none
      case .removeAuthorization:
        state.isAuthorizingSquare = true
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
        state.isAuthorizingSquare = false
        state.hasAuthorizedSquare = false
        state.squareAuthorizedLocation = nil
        return .none
      case .setErrorMessage(let title, let message):
        state.isAuthorizingSquare = false
        state.alert = AlertState {
          TextState(title)
        } message: {
          TextState(message)
        }
        return .none

      case .alert:
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
    ZStack {
      ViewHolder(controller: store.viewController)

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
      if store.hasAuthorizedSquare {
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
            if store.isAuthorizingSquare {
              ProgressView()
            }
          }
        }
        .disabled(store.isAuthorizingSquare)
      }
    }
  }

  @ViewBuilder
  var location: some View {
    Section("Location") {
      if let location = store.squareAuthorizedLocation {
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
      } else if store.hasAuthorizedSquare {
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
        initialState: .init(config: .mock),
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
          recordPermission: .granted,
          locationAuthorizationStatus: .authorizedWhenInUse,
          hasAuthorizedSquare: true,
          config: .mock
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
          },
          config: .mock
        )
      ) {
        SquareSetupFeature()
      }
    )
    .previewLayout(.fixed(width: 400, height: 400))
    .previewDisplayName("Alerting State")
  }
}
