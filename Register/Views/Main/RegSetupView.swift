//
//  ContentView.swift
//  Register
//

import ComposableArchitecture
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

    var configState: RegSetupConfigFeature.State = .init()
    var cart: TerminalCart? = nil

    private(set) var alertState: AlertState<Action>? = nil

    mutating func setMode(_ mode: Mode) {
      isClosed = mode == .close
      isAcceptingPayments = mode == .acceptPayments
    }

    mutating func setConfig(_ config: Config) {
      self.config = config
      configState.registerRequest = .init(config: config)
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
    case configAction(RegSetupConfigFeature.Action)
    case setErrorMessage(AlertContent?)
    case alertDismissed
    case ignore
  }

  private enum SubID {}

  var body: some ReducerProtocol<State, Action> {
    Scope(state: \.configState, action: /Action.configAction) {
      RegSetupConfigFeature()
    }

    Reduce { state, action in
      switch action {
      case .appeared:
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
          return connect(config: state.config)
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
        state.setMode(.acceptPayments)
        return .none
      case .terminalEvent(.close):
        state.setMode(.close)
        return .none
      case .terminalEvent(.clearCart):
        state.cart = nil
        return .none
      case let .terminalEvent(.updateCart(cart)):
        state.cart = cart
        return .none
      case .terminalEvent(.processPayment):
        fatalError("unimplemented process payment")
      case let .updateStatus(connected, lastUpdate):
        state.isConnected = connected
        state.lastUpdate = lastUpdate
        return .none
      case let .setMode(mode):
        state.setMode(mode)
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
        return connect(config: state.config)
      case let .configAction(.registered(.failure(error))):
        state.setAlert(
          AlertContent(
            title: "Registration Error",
            message: error.localizedDescription
          ))
        return .none
      case .configAction(_):
        return .none
      case let .setErrorMessage(content):
        state.setAlert(content)
        return .none
      case .alertDismissed:
        state.setAlert(nil)
        return .none
      case .ignore:
        return .none
      }
    }
    #if DEBUG
      ._printChanges()
    #endif
  }

  private func connect(config: Config) -> EffectTask<Action> {
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
}

struct RegSetupView: View {
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
              webViewURL: viewStore.binding(
                get: \.config.urlOrFallback,
                send: RegSetupFeature.Action.ignore
              ),
              cart: viewStore.binding(
                get: \.cart,
                send: RegSetupFeature.Action.ignore
              )
            )
          }
        )
        .onAppear {
          if viewStore.isLoadingConfig {
            viewStore.send(.appeared)
          }
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
      }
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
