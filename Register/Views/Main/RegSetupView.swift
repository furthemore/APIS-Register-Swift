//
//  ContentView.swift
//  Register
//

import Combine
import ComposableArchitecture
import SquareReaderSDK
import SwiftUI

struct RegSetupFeature: ReducerProtocol {
  @Dependency(\.apis) var apis

  struct State: Equatable {
    var isLoadingConfig: Bool = true
    private(set) var config: Config = Config.empty

    var isConnected: Bool = false
    var lastUpdate: Date? = nil

    private(set) var isAcceptingPayments: Bool = false
    private(set) var isClosed: Bool = false
    var isConfiguringSquare = false
    var squareIsReady = false

    var configState: RegSetupConfigFeature.State = .init()
    var squareSetupState: SquareSetupFeature.State = .init()

    var paymentState: PaymentFeature.State = .init(webViewURL: Register.fallbackURL)
    var checkoutDelegate: SquareCheckoutDelegate? = nil

    private(set) var alertState: AlertState<Action>? = nil

    mutating func setMode(_ mode: Mode) {
      isClosed = mode == .close
      isAcceptingPayments = mode == .acceptPayments
    }

    mutating func setConfig(_ config: Config) {
      self.config = config
      configState.registerRequest = .init(config: config)
      squareSetupState.config = config
      paymentState.webViewURL = config.urlOrFallback
    }

    mutating func setAlert(_ content: AlertContent?) {
      alertState = content?.alertState
    }
  }

  struct AlertContent: Equatable {
    var title: String
    var message: String

    var alertState: AlertState<Action> {
      return AlertState {
        TextState(title)
      } actions: {
        ButtonState(action: .alertDismissed) {
          TextState("OK")
        }
      } message: {
        TextState(message)
      }
    }
  }

  enum Mode: Equatable {
    case acceptPayments, close, setup
  }

  enum Action: Equatable {
    case appeared
    case configLoaded(TaskResult<Config>)
    case terminalEvent(TerminalEvent)
    case updateStatus(Bool, Date)
    case setMode(Mode)
    case setConfiguringSquare(Bool)
    case configAction(RegSetupConfigFeature.Action)
    case squareSetupAction(SquareSetupFeature.Action)
    case squareCheckoutAction(SquareCheckoutAction)
    case squareTransactionCompleted(Bool)
    case paymentAction(PaymentFeature.Action)
    case setErrorMessage(AlertContent?)
    case alertDismissed
    case ignore
    case scenePhaseChanged(ScenePhase)
  }

  private enum SubID {}
  private enum SquareID {}

  var body: some ReducerProtocol<State, Action> {
    Scope(state: \.configState, action: /Action.configAction) {
      RegSetupConfigFeature()
    }

    Scope(state: \.squareSetupState, action: /Action.squareSetupAction) {
      SquareSetupFeature()
    }

    Reduce { state, action in
      switch action {
      case .appeared:
        state.squareIsReady = SQRDReaderSDK.shared.isAuthorized
        return .task {
          do {
            let config = try await ConfigLoader.loadConfig()
            return .configLoaded(.success(config ?? Config.empty))
          } catch {
            return .configLoaded(.failure(error))
          }
        }
      case let .configLoaded(.success(config)):
        state.setConfig(config)
        state.isLoadingConfig = false
        if config != Config.empty {
          return connect(&state, config: state.config)
        } else {
          return .none
        }
      case let .configLoaded(.failure(error)):
        state.setAlert(
          AlertContent(
            title: "Config Load Error",
            message: error.localizedDescription
          ))
        return .none
      case .terminalEvent(.open):
        state.paymentState = .init(webViewURL: state.config.urlOrFallback)
        if state.squareIsReady {
          state.setMode(.acceptPayments)
        } else {
          state.setAlert(
            AlertContent(
              title: "Opening Failed",
              message: "Square is not yet configured."
            ))
        }
        return .none
      case .terminalEvent(.close):
        state.paymentState.currentTransactionReference = ""
        state.setMode(.close)
        return .none
      case .terminalEvent(.clearCart):
        state.paymentState.currentTransactionReference = ""
        state.paymentState = .init(webViewURL: state.config.urlOrFallback)
        return .none
      case let .terminalEvent(.updateCart(cart)):
        state.paymentState.currentTransactionReference = ""
        state.paymentState.cart = cart
        state.paymentState.alert = nil
        return .none
      case let .terminalEvent(.processPayment(total, note, reference)):
        state.paymentState.currentTransactionReference = reference

        let amountMoney = SQRDMoney(amount: total)
        let params = SQRDCheckoutParameters(amountMoney: amountMoney)
        params.note = note

        if state.config.allowCash == true {
          params.additionalPaymentTypes = [.cash]
        }

        return Effect<SquareCheckoutAction, Never>.run { sub in
          let delegate = SquareCheckoutDelegate(sub)

          let presentingView = Register.presentingViewController!
          DispatchQueue.main.async {
            let controller = SQRDCheckoutController(parameters: params, delegate: delegate)
            controller.present(from: presentingView)
          }

          return AnyCancellable {
            _ = delegate
          }
        }
        .map(RegSetupFeature.Action.squareCheckoutAction)
        .cancellable(id: SquareID.self, cancelInFlight: true)
      case let .updateStatus(connected, lastUpdate):
        state.isConnected = connected
        state.lastUpdate = lastUpdate
        return .none
      case let .setMode(mode):
        state.setMode(mode)
        return .none
      case let .setConfiguringSquare(configuring):
        state.isConfiguringSquare = configuring
        return .none
      case .configAction(.registerTerminal):
        return disconnect(state: &state)
      case let .configAction(.registered(.success(config))):
        state.setConfig(config)
        state.setAlert(
          AlertContent(
            title: "Registration Complete",
            message: "Successfully registered \(config.terminalName)"
          ))
        return connect(&state, config: state.config)
      case let .configAction(.registered(.failure(error))):
        state.setAlert(
          AlertContent(
            title: "Registration Error",
            message: error.localizedDescription
          ))
        return .none
      case let .configAction(.scannerResult(.success(payload))):
        return decodeQRCode(state: &state, payload: payload)
      case let .configAction(.scannerResult(.failure(error))):
        state.setAlert(
          AlertContent(
            title: "QR Code Error",
            message: error.localizedDescription
          ))
        return .none
      case .configAction(.clear):
        return disconnect(state: &state)
      case .configAction:
        return .none
      case .squareSetupAction(.fetchedAuthToken):
        state.squareIsReady = true
        return .none
      case .squareSetupAction(.didRemoveAuthorization):
        state.squareIsReady = false
        return .none
      case .squareSetupAction:
        return .none
      case .squareCheckoutAction(.cancelled):
        return .none
      case let .squareCheckoutAction(.finished(.failure(error))):
        state.paymentState.alert = AlertState(
          title: TextState("Error"),
          message: TextState(error.localizedDescription)
        )
        return .none
      case let .squareCheckoutAction(.finished(.success(result))):
        let config = state.config
        let transaction = SquareCompletedTransaction(
          reference: state.paymentState.currentTransactionReference,
          transactionID: result.transactionID ?? "",
          clientTransactionID: result.transactionClientID
        )
        return .task {
          let isValidTransaction: Bool
          do {
            isValidTransaction = try await apis.squareTransactionCompleted(config, transaction)
          } catch {
            Register.logger.error("Checkout failed: \(error, privacy: .public)")
            isValidTransaction = false
          }
          return .squareTransactionCompleted(isValidTransaction)
        }.animation(.easeInOut)
      case .squareTransactionCompleted(true):
        state.paymentState.cart = nil
        state.paymentState.alert = AlertState(
          title: TextState("Thanks!"),
          message: TextState("Payment successful.")
        )
        return .none
      case .squareTransactionCompleted(false):
        state.paymentState.alert = AlertState(
          title: TextState("Error"),
          message: TextState("Payment was not successful.")
        )
        return .none
      case .paymentAction:
        return .none
      case let .setErrorMessage(content):
        state.setAlert(content)
        return .none
      case .alertDismissed:
        state.setAlert(nil)
        return .none
      case .ignore:
        return .none
      case let .scenePhaseChanged(phase):
        if state.isConnected && phase == .active {
          return connect(&state, config: state.config)
        } else if state.isConnected && phase == .background {
          return .cancel(id: SubID.self)
        } else {
          return .none
        }
      }
    }
    #if DEBUG
      ._printChanges()
    #endif
  }

  private func connect(_ state: inout State, config: Config) -> EffectTask<Action> {
    state.isConnected = false

    return .run { send in
      do {
        let (client, listener) = try await apis.subscribeToEvents(config)
        await send(.updateStatus(true, Date()))

        let jsonDecoder = JSONDecoder()

        await withTaskCancellationHandler {
          Register.logger.debug("Stream was started")
          for await result in listener {
            switch result {
            case .success(let publish):
              await send(.updateStatus(true, Date()))

              var buffer = publish.payload
              guard let data = buffer.readData(length: buffer.readableBytes) else {
                continue
              }

              do {
                let event = try jsonDecoder.decode(TerminalEvent.self, from: data)
                await send(.terminalEvent(event), animation: .easeInOut)
              } catch {
                Register.logger.warning("Unknown event: \(error, privacy: .public)")
                await send(
                  .setErrorMessage(
                    AlertContent(
                      title: "Unknown Event",
                      message: error.localizedDescription
                    )))
              }
            case .failure(let error):
              await send(
                .setErrorMessage(
                  AlertContent(
                    title: "Error",
                    message: error.localizedDescription
                  )))
            }
          }
        } onCancel: {
          Register.logger.info("Stream was cancelled")
          try! client.syncShutdownGracefully()
        }
      } catch {
        await send(
          .setErrorMessage(
            AlertContent(
              title: "Error",
              message: error.localizedDescription
            )))
      }
    }
    .cancellable(id: SubID.self, cancelInFlight: true)
  }

  private func disconnect(state: inout State) -> EffectTask<Action> {
    state.isConnected = false
    return .cancel(id: SubID.self)
  }

  private func decodeQRCode(state: inout State, payload: String) -> EffectTask<Action> {
    guard let data = payload.data(using: .utf8) else {
      state.setAlert(AlertContent(title: "QR Code Error", message: "Not Valid UTF8"))
      return .none
    }

    do {
      let jsonDecoder = JSONDecoder()
      let registerRequest = try jsonDecoder.decode(RegisterRequest.self, from: data)
      state.configState.registerRequest = registerRequest
      state.setAlert(
        AlertContent(
          title: "Imported QR Code",
          message: "Successfully imported data."
        ))
      return disconnect(state: &state)
    } catch {
      state.setAlert(
        AlertContent(
          title: "QR Code Error",
          message: error.localizedDescription
        ))
      return .none
    }
  }
}

struct RegSetupView: View {
  @Environment(\.scenePhase) var scenePhase

  let store: StoreOf<RegSetupFeature>

  var body: some View {
    NavigationStack {
      WithViewStore(store) { viewStore in
        Form {
          RegSetupStatusView(
            isConnected: viewStore.binding(
              get: \.isConnected,
              send: RegSetupFeature.Action.ignore
            ),
            lastUpdated: viewStore.binding(
              get: \.lastUpdate,
              send: RegSetupFeature.Action.ignore
            )
          )

          RegSetupConfigView(
            store: store.scope(
              state: \.configState,
              action: RegSetupFeature.Action.configAction
            ))

          Section("Square") {
            Button {
              viewStore.send(.setConfiguringSquare(true))
            } label: {
              Label("Square Setup", systemImage: "square")
            }.disabled(!viewStore.isConnected)
          }

          launch(viewStore)
        }
        .navigationTitle("Reg Setup")
        .alert(store.scope(state: \.alertState), dismiss: .alertDismissed)
        .fullScreenCover(
          isPresented: viewStore.binding(
            get: \.isClosed,
            send: .setMode(.setup)
          ),
          content: ClosedView.init
        )
        .fullScreenCover(
          isPresented: viewStore.binding(
            get: \.isAcceptingPayments,
            send: .setMode(.setup)
          ),
          content: {
            PaymentView(
              store: store.scope(
                state: \.paymentState,
                action: RegSetupFeature.Action.paymentAction
              ))
          }
        )
        .sheet(
          isPresented: viewStore.binding(
            get: \.isConfiguringSquare, send: RegSetupFeature.Action.setConfiguringSquare)
        ) {
          SquareSetupView(
            store: store.scope(
              state: \.squareSetupState,
              action: RegSetupFeature.Action.squareSetupAction
            ))
        }
        .onAppear {
          if viewStore.isLoadingConfig {
            viewStore.send(.appeared)
          }
        }
        .onChange(of: scenePhase) { newPhase in
          viewStore.send(.scenePhaseChanged(newPhase))
        }
      }
    }
    .statusBar(hidden: true)
  }

  @ViewBuilder
  func launch(_ viewStore: ViewStoreOf<RegSetupFeature>) -> some View {
    Section("Launch") {
      Button {
        viewStore.send(.setMode(.close))
      } label: {
        Label("Close Terminal", systemImage: "xmark.square")
      }

      Button {
        viewStore.send(.setMode(.acceptPayments))
      } label: {
        Label("Accept Payments", systemImage: "creditcard")
      }.disabled(!viewStore.squareIsReady || !viewStore.isConnected)
    }
  }
}

struct ContentView_Previews: PreviewProvider {
  static var previews: some View {
    RegSetupView(
      store: Store(
        initialState: .init(),
        reducer: RegSetupFeature()
      ))
  }
}
