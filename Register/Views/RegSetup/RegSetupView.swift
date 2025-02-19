//
//  ContentView.swift
//  Register
//

import Combine
import ComposableArchitecture
import SquareMobilePaymentsSDK
import SwiftUI

@Reducer
struct RegSetupFeature {
  @Dependency(\.config) var config
  @Dependency(\.apis) var apis
  @Dependency(\.square) var square
  @Dependency(\.date) var date
  @Dependency(\.uuid) var uuid

  enum Mode: Equatable {
    case acceptPayments, close, setup

    var isPresenting: Bool {
      switch self {
      case .acceptPayments, .close:
        return true
      default:
        return false
      }
    }
  }

  @ObservableState
  struct RegState: Equatable {
    var needsConfigLoad = true

    var isConnecting = false
    var isConnected = false
    var lastEvent: Date? = nil

    var mode = Mode.setup

    var isConfiguringSquare = false
    var squareIsReady = false
    var squareWasInitialized = false
  }

  @ObservableState
  struct State: Equatable {
    @Presents var alert: AlertState<Action.Alert>? = nil

    var config: Config? = nil

    var regState: RegState = .init()
    var configState: RegSetupConfigFeature.State = .init()

    var squareSetupState: SquareSetupFeature.State? = nil
    var paymentState: PaymentFeature.State? = nil

    mutating func setAlert(title: String, message: String) {
      alert = AlertState {
        TextState(title)
      } actions: {
        ButtonState(action: .dismiss) {
          TextState("OK")
        }
      } message: {
        TextState(message)
      }
    }

    func readyForPayments(square: SquareClient) -> Bool {
      return config != nil && regState.squareIsReady && square.wasInitialized()
    }
  }

  enum Action: Equatable {
    case appeared
    case scenePhaseChanged(ScenePhase)

    case setMode(Mode)
    case setConfiguringSquare(Bool)
    case setErrorMessage(title: String, message: String)

    case configLoaded(TaskResult<Config>)
    case connectToggle

    case terminalEvent(TaskResult<TerminalEvent>)
    case squareTransactionCompleted(Bool)

    case alert(PresentationAction<Alert>)
    case configAction(RegSetupConfigFeature.Action)
    case squareSetupAction(SquareSetupFeature.Action)
    case squareCheckoutAction(SquareCheckoutAction)
    case paymentAction(PaymentFeature.Action)

    enum Alert: Equatable {
      case dismiss
    }
  }

  private enum CancelID { case sub, square }

  var body: some Reducer<State, Action> {
    Scope(state: \.configState, action: \.configAction) {
      RegSetupConfigFeature()
    }

    Reduce { state, action in
      switch action {
      case .appeared:
        state.regState.squareIsReady = square.isAuthorized()
        state.regState.squareWasInitialized = square.wasInitialized()
        return .run { send in
          do {
            if let config = try await config.load() {
              await send(.configLoaded(.success(config)))
            } else {
              await send(.configLoaded(.failure(ConfigError.missingConfig)))
            }
          } catch {
            await send(.configLoaded(.failure(error)))
          }
        }
      case let .scenePhaseChanged(phase):
        if state.regState.isConnected && phase == .active {
          return connect(&state)
        } else if state.regState.isConnected && phase == .background {
          return .cancel(id: CancelID.sub)
        } else {
          return .none
        }

      case let .setMode(mode):
        state.regState.mode = mode
        return .none
      case let .setConfiguringSquare(configuring):
        state.regState.isConfiguringSquare = false
        state.squareSetupState = nil

        if configuring {
          guard let config = state.config else {
            state.setAlert(
              title: "Error",
              message: "Must load configuration before configuring Square"
            )
            return .none
          }

          state.regState.isConfiguringSquare = true
          state.squareSetupState = .init(config: config)
        }

        return .none
      case let .setErrorMessage(title, message):
        state.setAlert(title: title, message: message)
        return .none

      case let .configLoaded(.success(config)):
        state.config = config
        state.regState.needsConfigLoad = false
        return connect(&state)
      case .configLoaded(.failure(ConfigError.missingConfig)):
        state.regState.needsConfigLoad = false
        return .none
      case let .configLoaded(.failure(error)):
        state.regState.needsConfigLoad = false
        state.setAlert(
          title: "Config Load Error",
          message: error.localizedDescription
        )
        return .run { _ in
          try await config.clear()
        }
      case .connectToggle:
        if state.regState.isConnected {
          return disconnect(state: &state)
        } else {
          return connect(&state)
        }

      case let .terminalEvent(event):
        return handleTerminalEvent(&state, event: event)
      case .squareTransactionCompleted(true):
        return .none
      case .squareTransactionCompleted(false):
        state.paymentState?.alert = AlertState {
          TextState("Error")
        } message: {
          TextState("Payment was not successful.")
        }
        return .none

      case .alert(.dismiss):
        state.alert = nil
        return .none
      case .alert:
        return .none

      case let .configAction(.scannerResult(.success(payload))):
        return decodeQRCode(state: &state, payload: payload)
      case let .configAction(.scannerResult(.failure(error))):
        state.setAlert(
          title: "QR Code Error",
          message: error.localizedDescription
        )
        return .none
      case .configAction(.clear):
        return .concatenate(
          .run { _ in
            try await square.deauthorize()
          },
          disconnect(state: &state)
        )
      case .configAction:
        return .none

      case .squareSetupAction(.authorized):
        state.regState.squareIsReady = square.wasInitialized()
        return .none
      case .squareSetupAction(.didRemoveAuthorization):
        state.regState.squareIsReady = false
        return .none
      case .squareSetupAction:
        return .none

      case .squareCheckoutAction(.cancelled):
        return .none
      case let .squareCheckoutAction(.finished(.failure(error))):
        state.paymentState?.alert = AlertState {
          TextState("Error")
        } message: {
          TextState(error.localizedDescription)
        }
        return .none
      case let .squareCheckoutAction(.finished(.success(result))):
        guard let config = state.config, var paymentState = state.paymentState else {
          return .none
        }

        guard let paymentId = result.paymentId, let referenceId = result.referenceId else {
          paymentState.alert = AlertState {
            TextState("Error")
          } message: {
            TextState("Finished payment was missing ID or reference.")
          }
          return .none
        }

        let transaction = SquareCompletedTransaction(
          reference: referenceId,
          paymentId: paymentId
        )

        return .run { send in
          let isValidTransaction: Bool
          do {
            isValidTransaction = try await apis.squareTransactionCompleted(config, transaction)
          } catch {
            Register.logger.error("Checkout failed: \(error, privacy: .public)")
            isValidTransaction = false
          }
          await send(.squareTransactionCompleted(isValidTransaction))
        }.animation(.easeInOut)

      case .paymentAction(.dismissView):
        state.regState.mode = .setup
        return .none
      case .paymentAction:
        return .none
      }
    }
    .ifLet(\.$alert, action: \.alert)
    .ifLet(\.squareSetupState, action: \.squareSetupAction) {
      SquareSetupFeature()
    }
    .ifLet(\.paymentState, action: \.paymentAction) {
      PaymentFeature()
    }
    #if DEBUG
      ._printChanges()
    #endif
  }

  private func decodeQRCode(state: inout State, payload: String) -> Effect<Action> {
    guard let data = payload.data(using: .utf8) else {
      state.setAlert(title: "QR Code Error", message: "Not Valid UTF8")
      return .none
    }

    do {
      let jsonDecoder = JSONDecoder()
      let updatedConfig = try jsonDecoder.decode(Config.self, from: data)
      state.config = updatedConfig
      state.setAlert(
        title: "Imported QR Code",
        message: "Successfully imported data."
      )
      return .run { send in
        do {
          try await config.save(updatedConfig)
        } catch {
          await send(
            .setErrorMessage(
              title: "Config Error",
              message: error.localizedDescription
            ))
        }
      }
    } catch {
      state.setAlert(
        title: "QR Code Error",
        message: error.localizedDescription
      )
      return .none
    }
  }

  private func connect(_ state: inout State) -> Effect<Action> {
    state.regState.isConnected = false

    guard let config = state.config else {
      state.setAlert(title: "Error", message: "Configuration was not set.")
      return .none
    }

    do {
      state.regState.isConnecting = true
      return
        try apis
        .subscribeToEvents(config)
        .map(Action.terminalEvent)
        .cancellable(id: CancelID.sub, cancelInFlight: true)
        .animation(.easeInOut)
    } catch {
      state.regState.isConnecting = false
      state.setAlert(title: "Error", message: error.localizedDescription)
      return .none
    }
  }

  private func disconnect(state: inout State) -> Effect<Action> {
    state.regState.isConnecting = false
    state.regState.isConnected = false
    return .cancel(id: CancelID.sub)
  }

  private func handleTerminalEvent(
    _ state: inout State,
    event: TaskResult<TerminalEvent>
  ) -> Effect<Action> {
    state.regState.isConnecting = false
    state.regState.isConnected = true
    state.regState.lastEvent = date.now

    switch event {
    case .success(.connected):
      return .none
    case .success(.open):
      if let config = state.config, state.readyForPayments(square: square) {
        state.paymentState = .init(
          webViewUrl: config.webViewUrl,
          themeColor: config.parsedColor
        )
        state.regState.mode = .acceptPayments
      } else {
        state.setAlert(
          title: "Opening Failed",
          message: "Terminal has not been fully configured."
        )
      }
      return .none
    case .success(.close):
      state.regState.mode = .close
      return .none
    case .success(.ready):
      return .none
    case .success(.clearCart):
      state.paymentState?.alert = nil
      state.paymentState?.cart = nil
      return .none
    case let .success(.updateCart(cart)):
      state.paymentState?.alert = nil
      state.paymentState?.cart = cart
      return .none
    case let .success(.processPayment(orderId, total, note, reference)):
      guard var paymentState = state.paymentState else {
        state.setAlert(
          title: "No Payment State",
          message: "Payments have not yet been enabled."
        )
        return .none
      }

      if paymentState.showingMockReaderUI {
        paymentState.alert = AlertState(title: {
          TextState("Cannot accept payments while mock reader UI is displayed")
        })
        return .none
      }

      let params = PaymentParameters(
        idempotencyKey: uuid().uuidString,
        amountMoney: Money(amount: total, currency: .USD)
      )

      if let orderId {
        params.orderID = orderId
      } else {
        params.note = note
      }

      params.referenceID = reference

      return .run { send in
        do {
          for await action in try await square.checkout(params) {
            await send(.squareCheckoutAction(action))
          }
        } catch {
          await send(
            .setErrorMessage(
              title: "Error",
              message: "Could not create checkout: \(error.localizedDescription)"
            ))
        }
      }
      .cancellable(id: CancelID.square)
    case let .success(.updateToken(accessToken)):
      guard let currentConfig = state.config else {
        state.setAlert(
          title: "Error",
          message: "Must have configuration before authorizing Square"
        )
        return .none
      }

      return .run { send in
        do {
          try await config.save(currentConfig)
          try await square.authorize(accessToken, currentConfig.squareLocationId)
          await send(.squareSetupAction(.authorized))
        } catch {
          await send(
            .setErrorMessage(
              title: "Error",
              message: error.localizedDescription
            )
          )
        }
      }
    case let .success(.updateConfig(updatedConfig)):
      state.config = updatedConfig

      switch state.regState.mode {
      case .acceptPayments:
        state.paymentState?.themeColor = updatedConfig.parsedColor
      default:
        break
      }

      if state.regState.isConfiguringSquare {
        state.regState.isConfiguringSquare = false
        state.squareSetupState = nil
      }

      var events = [
        disconnect(state: &state),
        .run { _ in
          do {
            try await config.save(updatedConfig)
          }
        },
      ]

      if let existingConfig = state.config,
        existingConfig.squareApplicationId != updatedConfig.squareApplicationId
      {
        state.setAlert(
          title: "Updated Config",
          message: "Square Application ID changed, you must relaunch the app."
        )
      } else {
        events.append(connect(&state))
      }

      return .concatenate(events)
    case let .failure(error):
      state.setAlert(
        title: "Event Error",
        message: error.localizedDescription
      )
      return disconnect(state: &state)
    }
  }
}

struct RegSetupView: View {
  @SwiftUICore.Environment(\.scenePhase) var scenePhase

  @Bindable var store: StoreOf<RegSetupFeature>

  var body: some View {
    NavigationStack {
      Form {
        RegSetupStatusView(
          terminalName: Binding(
            get: { store.config?.terminalName },
            set: { _ in }
          ),
          isConnecting: Binding(
            get: { store.regState.isConnecting },
            set: { _ in }
          ),
          isConnected: Binding(
            get: { store.regState.isConnected },
            set: { _ in }
          ),
          lastEvent: Binding(
            get: { store.regState.lastEvent },
            set: { _ in }
          ),
          canConnect: Binding(
            get: { store.config != nil },
            set: { _ in }
          ),
          connectToggle: { store.send(.connectToggle) }
        )

        launch

        Section("Square") {
          Button {
            store.send(.setConfiguringSquare(true))
          } label: {
            Label("Square Setup", systemImage: "square")
          }.disabled(store.config == nil || !store.regState.squareWasInitialized)
        }

        RegSetupConfigView(
          store: store.scope(
            state: \.configState,
            action: \.configAction
          )
        ).disabled(store.regState.needsConfigLoad)
      }
      .navigationTitle("Terminal Setup")
      .alert(
        store: store.scope(state: \.$alert, action: \.alert)
      )
      .fullScreenCover(
        isPresented: Binding(
          get: { store.regState.mode.isPresenting },
          set: { _ in store.send(.setMode(.setup)) }
        ),
        content: {
          switch store.regState.mode {
          case .acceptPayments:
            if let store = store.scope(state: \.paymentState, action: \.paymentAction) {
              PaymentView(store: store)
                .persistentSystemOverlays(.hidden)
            }

          case .close:
            ClosedView(themeColor: store.config?.parsedColor ?? Register.fallbackThemeColor)
              .persistentSystemOverlays(.hidden)

          default:
            Text("Invalid Mode!")
          }
        }
      )
      .sheet(
        isPresented: $store.regState.isConfiguringSquare.sending(\.setConfiguringSquare)
      ) {
        if let store = store.scope(state: \.squareSetupState, action: \.squareSetupAction) {
          SquareSetupView(store: store)
        }
      }
      .onAppear {
        if store.regState.needsConfigLoad {
          store.send(.appeared)
        }
      }
      .onChange(of: scenePhase) { _, newPhase in
        store.send(.scenePhaseChanged(newPhase))
      }
    }
  }

  @ViewBuilder
  var launch: some View {
    Section("Launch") {
      Button {
        store.send(.setMode(.acceptPayments))
      } label: {
        Label("Accept Payments", systemImage: "creditcard")
      }.disabled(!store.regState.squareIsReady || !store.regState.isConnected)

      Button {
        store.send(.setMode(.close))
      } label: {
        Label("Close Terminal", systemImage: "xmark.square")
      }
    }
  }
}

struct ContentView_Previews: PreviewProvider {
  static var previews: some View {
    RegSetupView(
      store: Store(initialState: .init()) {
        RegSetupFeature()
      }
    )
  }
}
