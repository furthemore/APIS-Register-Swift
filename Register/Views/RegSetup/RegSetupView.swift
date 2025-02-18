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

    var isConnected = false
    var lastEvent: Date? = nil

    var mode = Mode.setup

    var isConfiguringSquare = false
    var squareIsReady = false
  }

  @ObservableState
  struct State: Equatable {
    @Presents var alert: AlertState<Action.Alert>? = nil

    private(set) var config: Config = Config.empty

    var regState: RegState = .init()

    var alertState: AlertState<Action>? = nil
    var configState: RegSetupConfigFeature.State = .init()
    var squareSetupState: SquareSetupFeature.State = .init()
    var paymentState: PaymentFeature.State = .init(
      webViewURL: Register.fallbackURL,
      themeColor: Register.fallbackThemeColor
    )

    mutating func setConfig(_ config: Config) {
      self.config = config
      configState.registerRequest = .init(config: config)
      squareSetupState.config = config
      paymentState.webViewURL = config.urlOrFallback
      paymentState.themeColor = config.parsedColor
    }

    mutating func setAlert(title: String, message: String) {
      alertState = AlertState {
        TextState(title)
      } actions: {
        ButtonState(action: .alert(.dismiss)) {
          TextState("OK")
        }
      } message: {
        TextState(message)
      }
    }
  }

  enum Action: Equatable {
    case appeared
    case configLoaded(TaskResult<Config>)
    case terminalEvent(TaskResult<TerminalEvent>)
    case setMode(Mode)
    case setConfiguringSquare(Bool)
    case configAction(RegSetupConfigFeature.Action)
    case squareSetupAction(SquareSetupFeature.Action)
    case squareCheckoutAction(SquareCheckoutAction)
    case squareTransactionCompleted(Bool)
    case paymentAction(PaymentFeature.Action)
    case setErrorMessage(title: String, message: String)
    case alert(PresentationAction<Alert>)
    case scenePhaseChanged(ScenePhase)

    enum Alert: Equatable {}
  }

  private enum CancelID { case sub, square }

  var body: some Reducer<State, Action> {
    Scope(state: \.configState, action: \.configAction) {
      RegSetupConfigFeature()
    }

    Scope(state: \.squareSetupState, action: \.squareSetupAction) {
      SquareSetupFeature()
    }

    Scope(state: \.paymentState, action: \.paymentAction) {
      PaymentFeature()
    }

    Reduce { state, action in
      switch action {
      case .appeared:
        state.regState.squareIsReady = square.isAuthorized()
        return .run { send in
          do {
            let config = try await config.load()
            await send(.configLoaded(.success(config ?? Config.empty)))
          } catch {
            await send(.configLoaded(.failure(error)))
          }
        }
      case let .configLoaded(.success(config)):
        state.setConfig(config)
        state.regState.needsConfigLoad = false
        if config != Config.empty {
          return connect(&state)
        } else {
          return .none
        }
      case let .configLoaded(.failure(error)):
        state.setAlert(
          title: "Config Load Error",
          message: error.localizedDescription
        )
        return .none
      case let .terminalEvent(event):
        return handleTerminalEvent(&state, event: event)
      case let .setMode(mode):
        state.regState.mode = mode
        return .none
      case let .setConfiguringSquare(configuring):
        state.regState.isConfiguringSquare = configuring
        return .none
      case .configAction(.registerTerminal):
        return disconnect(state: &state)
      case let .configAction(.registered(.success(config))):
        state.setConfig(config)
        state.setAlert(
          title: "Registration Complete",
          message: "Successfully registered \(config.terminalName)"
        )
        return connect(&state)
      case let .configAction(.registered(.failure(error))):
        state.setAlert(
          title: "Registration Error",
          message: error.localizedDescription
        )
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
        return disconnect(state: &state)
      case .configAction:
        return .none
      case .squareSetupAction(.authorized):
        state.regState.squareIsReady = true
        return .none
      case .squareSetupAction(.didRemoveAuthorization):
        state.regState.squareIsReady = false
        return .none
      case .squareSetupAction:
        return .none
      case .squareCheckoutAction(.cancelled):
        return .none
      case let .squareCheckoutAction(.finished(.failure(error))):
        state.paymentState.alert = AlertState {
          TextState("Error")
        } message: {
          TextState(error.localizedDescription)
        }
        return .none
      case let .squareCheckoutAction(.finished(.success(result))):
        guard let paymentId = result.paymentId else {
          state.paymentState.alert = AlertState {
            TextState("Error")
          } message: {
            TextState("Finished payment was missing ID.")
          }
          return .none
        }

        let transaction = SquareCompletedTransaction(
          reference: state.paymentState.currentTransactionReference,
          paymentId: paymentId
        )

        return .run { [config = state.config] send in
          let isValidTransaction: Bool
          do {
            isValidTransaction = try await apis.squareTransactionCompleted(config, transaction)
          } catch {
            Register.logger.error("Checkout failed: \(error, privacy: .public)")
            isValidTransaction = false
          }
          await send(.squareTransactionCompleted(isValidTransaction))
        }.animation(.easeInOut)
      case .squareTransactionCompleted(true):
        state.paymentState.currentTransactionReference = ""
        return .none
      case .squareTransactionCompleted(false):
        state.paymentState.alert = AlertState {
          TextState("Error")
        } message: {
          TextState("Payment was not successful.")
        }
        return .none
      case .paymentAction(.dismissView):
        state.regState.mode = .setup
        return .none
      case .paymentAction:
        return .none
      case let .setErrorMessage(title, message):
        state.setAlert(title: title, message: message)
        return .none
      case .alert:
        return .none
      case let .scenePhaseChanged(phase):
        if state.regState.isConnected && phase == .active {
          return connect(&state)
        } else if state.regState.isConnected && phase == .background {
          return .cancel(id: CancelID.sub)
        } else {
          return .none
        }
      }
    }
    .ifLet(\.$alert, action: \.alert)
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
      let registerRequest = try jsonDecoder.decode(RegisterRequest.self, from: data)
      state.configState.registerRequest = registerRequest
      state.setAlert(
        title: "Imported QR Code",
        message: "Successfully imported data."
      )
      return disconnect(state: &state)
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
    state.configState.canUpdateConfig = true

    do {
      return
        try apis
        .subscribeToEvents(state.config)
        .map(Action.terminalEvent)
        .cancellable(id: CancelID.sub, cancelInFlight: true)
        .animation(.easeInOut)
    } catch {
      state.setAlert(title: "Error", message: error.localizedDescription)
      return .none
    }
  }

  private func disconnect(state: inout State) -> Effect<Action> {
    state.regState.isConnected = false
    state.configState.canUpdateConfig = true

    return .cancel(id: CancelID.sub)
  }

  private func handleTerminalEvent(
    _ state: inout State,
    event: TaskResult<TerminalEvent>
  ) -> Effect<Action> {
    state.regState.isConnected = true
    state.regState.lastEvent = date.now
    state.configState.canUpdateConfig = false

    state.paymentState.currentTransactionReference = ""

    switch event {
    case .success(.connected):
      return .none
    case .success(.open):
      if state.regState.squareIsReady {
        state.paymentState = .init(
          webViewURL: state.config.urlOrFallback,
          themeColor: state.config.parsedColor
        )
        state.regState.mode = .acceptPayments
      } else {
        state.setAlert(
          title: "Opening Failed",
          message: "Square is not yet configured."
        )
      }
      return .none
    case .success(.close):
      state.regState.mode = .close
      return .none
    case .success(.clearCart):
      state.paymentState = .init(
        webViewURL: state.config.urlOrFallback,
        themeColor: state.config.parsedColor
      )
      return .none
    case let .success(.updateCart(cart)):
      state.paymentState.cart = cart
      state.paymentState.alert = nil
      return .none
    case let .success(.processPayment(orderId, total, note, reference)):
      if state.paymentState.showingMockReaderUI {
        state.setAlert(
          title: "Error",
          message: "Can't start payment while mock reader is presented."
        )
        return .none
      }

      state.paymentState.currentTransactionReference = reference

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
    case let .success(.updateToken(accessToken, refreshToken)):
      let updatedConfig = state.config.withSquareTokens(
        accessToken: accessToken,
        refreshToken: refreshToken
      )
      state.setConfig(updatedConfig)

      return .run { send in
        do {
          try await config.save(updatedConfig)

          if let locationId = updatedConfig.locationId {
            try await square.authorize(accessToken, locationId)
            await send(.squareSetupAction(.authorized))
          }
        } catch {
          await send(
            .setErrorMessage(
              title: "Error",
              message: error.localizedDescription
            )
          )
        }
      }
    case let .failure(error):
      state.setAlert(
        title: "Event Error",
        message: error.localizedDescription
      )
      return .none
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
          isConnected: Binding(
            get: { store.regState.isConnected },
            set: { _ in }
          ),
          lastEvent: Binding(
            get: { store.regState.lastEvent },
            set: { _ in }
          )
        )

        launch

        Section("Square") {
          Button {
            store.send(.setConfiguringSquare(true))
          } label: {
            Label("Square Setup", systemImage: "square")
          }.disabled(!store.regState.isConnected)
        }

        RegSetupConfigView(
          store: store.scope(
            state: \.configState,
            action: \.configAction
          ))
      }
      .navigationTitle("Reg Setup")
      .alert(
        store: store.scope(state: \.$alert, action: \.alert)
      )
      .fullScreenCover(
        isPresented: Binding(
          get: { store.regState.mode.isPresenting },
          set: { _ in store.send(.setMode(store.regState.mode)) }
        ),
        content: {
          switch store.regState.mode {
          case .acceptPayments:
            PaymentView(
              store: store.scope(
                state: \.paymentState,
                action: \.paymentAction
              )
            )
            .persistentSystemOverlays(.hidden)

          case .close:
            ClosedView(themeColor: store.config.parsedColor)
              .persistentSystemOverlays(.hidden)

          default:
            Text("Invalid Mode!")
          }
        }
      )
      .sheet(
        isPresented: $store.regState.isConfiguringSquare.sending(\.setConfiguringSquare)
      ) {
        SquareSetupView(
          store: store.scope(
            state: \.squareSetupState,
            action: \.squareSetupAction
          ))
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
