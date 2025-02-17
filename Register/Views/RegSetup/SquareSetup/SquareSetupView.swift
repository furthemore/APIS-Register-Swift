//
//  SquareSetupView.swift
//  Register
//

import AVFoundation
import Combine
import ComposableArchitecture
import CoreLocation
import SwiftUI

@Reducer
struct SquareSetupFeature {
  @Dependency(\.apis) var apis
  @Dependency(\.square) var square
  @Dependency(\.avAudioSession) var avAudioSession
  @Dependency(\.locationManager) var locationManager

  @ObservableState
  struct State: Equatable {
    @Presents var alert: AlertState<Action.Alert>? = nil
    var locationAuthorizationStatus: CLAuthorizationStatus? = nil
    var recordPermission: RecordPermission? = nil
    var isAuthorized = false
    var authorizedLocation: SquareLocation? = nil
    var isFetchingAuthCode = false
    var config: Config = .empty
  }

  enum Action: Equatable {
    case appeared
    case locationManager(LocationAction)
    case requestLocation
    case recordPermission(RecordPermission)
    case requestRecordPermission
    case openSettings
    case setPairingDevice(Bool)
    case getAuthorizationCode
    case fetchedAuthToken(SquareLocation)
    case removeAuthorization
    case didRemoveAuthorization
    case alert(PresentationAction<Alert>)
    case setErrorMessage(String, String)
    case squareSettingsAction(SquareSettingsAction)

    enum Alert: Equatable {}
  }

  private enum CancelID { case locationManager }

  var body: some ReducerOf<Self> {
    Reduce { state, action in
      switch action {
      case .appeared:
        state.recordPermission = avAudioSession.recordPermission()
        state.authorizedLocation = square.authorizedLocation()
        state.isAuthorized = square.isAuthorized()
        return .run { @MainActor send in
          for await action in locationManager.delegate() {
            send(.locationManager(action))
          }
        }
        .cancellable(id: CancelID.locationManager, cancelInFlight: true)
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
        return avAudioSession.requestRecordPermission().map(Action.recordPermission)
      case .openSettings:
        if let url = URL(string: UIApplication.openSettingsURLString) {
          UIApplication.shared.open(url)
        }
        return .none
      case let .setPairingDevice(pairing):
        if pairing == true {
          return .run { send in
            do {
              for await action in try await square.openSettings() {
                await send(.squareSettingsAction(action))
              }
            } catch {
              await send(.setErrorMessage("App Error", error.localizedDescription))
            }
          }
        }
        return .none
      case .getAuthorizationCode:
        state.isFetchingAuthCode = true
        return getAuthCode(config: state.config)
      case let .fetchedAuthToken(location):
        state.isFetchingAuthCode = false
        state.isAuthorized = true
        state.authorizedLocation = location
        return .none
      case .removeAuthorization:
        state.isFetchingAuthCode = true
        return .run { send in
          do {
            try await square.deauthorize()
            await send(.didRemoveAuthorization)
          } catch {
            await send(.setErrorMessage("Square Error", error.localizedDescription))
          }
        }.animation(.easeInOut)
      case .didRemoveAuthorization:
        state.isFetchingAuthCode = false
        state.isAuthorized = false
        state.authorizedLocation = nil
        return .none
      case .alert:
        return .none
      case let .setErrorMessage(title, message):
        state.isFetchingAuthCode = false
        state.alert = AlertState {
          TextState(title)
        } message: {
          TextState(message)
        }
        return .none
      case .squareSettingsAction:
        return .none
      }
    }
    .ifLet(\.alert, action: \.alert)
  }

  private func getAuthCode(config: Config) -> Effect<Action> {
    return .run { send in
      let code: String
      do {
        code = try await apis.getSquareToken(config)
      } catch {
        return await send(
          .setErrorMessage("Error Fetching Token", error.localizedDescription)
        )
      }

      do {
        let location = try await square.authorize(code)
        await send(.fetchedAuthToken(location))
      } catch {
        await send(.setErrorMessage("Reader SDK Error", error.localizedDescription))
      }
    }.animation(.easeInOut)
  }
}

struct SquareSetupView: View {
  @Bindable var store: StoreOf<SquareSetupFeature>

  var body: some View {
    NavigationStack {
      Form {
        permissions
        authorization

        Section("Devices") {
          Button {
            store.send(.setPairingDevice(true))
          } label: {
            Label("Pair Device", systemImage: "arrow.triangle.2.circlepath")
          }.disabled(!store.isAuthorized)
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
        Label("Reader Authorized", systemImage: "checkmark")
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
          Label("Get Authorization Code", systemImage: "key.horizontal")
        }.disabled(store.isFetchingAuthCode)
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
          name: "Business Name",
          value: location.businessName
        )
        LocationDetailView(
          name: "Card Processing",
          value: location.isCardProcessingActivated ? "Activated" : "Disabled"
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
      store: Store(initialState: .init()) {
        SquareSetupFeature()
      }
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
