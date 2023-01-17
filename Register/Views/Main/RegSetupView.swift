//
//  ContentView.swift
//  Register
//

import ComposableArchitecture
import SwiftUI

struct RegFeature: ReducerProtocol {
  @Dependency(\.apis) var apis

  struct State: Equatable {
    var alertState: AlertState<Action>? = nil

    var isLoadingConfig: Bool = true
    var config: Config = Config.empty

    var isConnected: Bool = false
    var lastUpdate: Date? = nil

    var isAcceptingPayments: Bool = false
    var isClosed: Bool = false

    var cart: TerminalCart = .empty

    var configState: RegConfigFeature.State = .init()

    var paymentState: PayFeature.State = .init(
      webViewURL: URL(string: "https://furthemore.org/code-of-conduct/")!
    )

    static func isValidHost(host: String) -> Bool {
      guard let url = URL(string: host) else {
        return false
      }

      return UIApplication.shared.canOpenURL(url)
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

  enum Action: Equatable {
    case appeared
    case configLoaded(Config)
    case showConfig, acceptPayments, closeTerminal
    case setErrorMessage(AlertContent?)
    case alertDismissed
    case updateStatus(Bool, Date)
    case terminalEvent(TerminalEvent)
    case configAction(RegConfigFeature.Action)
    case paymentAction(PayFeature.Action)
    case connect
  }

  private enum SubID {}

  var body: some ReducerProtocol<State, Action> {
    Scope(state: \.configState, action: /Action.configAction) {
      RegConfigFeature()
    }

    Reduce { state, action in
      switch action {
      case .appeared:
        return .task {
          let config = try? await ConfigLoader.loadConfig()
          return .configLoaded(config ?? Config.empty)
        }
      case let .configLoaded(config):
        state.config = config
        state.configState.registerRequest = .init(config: config)
        state.isLoadingConfig = false
        if config != Config.empty {
          return .task {
            return .connect
          }
        } else {
          return .none
        }
      case .showConfig:
        state.isClosed = false
        state.isAcceptingPayments = false
        return .none
      case .acceptPayments:
        state.isClosed = false
        state.isAcceptingPayments = true
        return .none
      case .closeTerminal:
        state.isClosed = true
        state.isAcceptingPayments = false
        return .none
      case .connect:
        let config = state.config
        return .run { send in
          do {
            let (client, listener) = try await apis.subscribeToEvents(config)
            await send(.updateStatus(true, Date()))

            let jsonDecoder = JSONDecoder()

            await withTaskCancellationHandler {
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
                    dump(error)
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
      case let .setErrorMessage(.some(content)):
        state.alertState = content.alertState
        return .none
      case .setErrorMessage(_):
        state.alertState = nil
        return .none
      case .alertDismissed:
        state.alertState = nil
        return .none
      case let .updateStatus(connected, lastUpdate):
        state.isConnected = connected
        state.lastUpdate = lastUpdate
        return .none
      case let .terminalEvent(event):
        switch event {
        case .open:
          state.isClosed = false
          state.isAcceptingPayments = true
        case .close:
          state.isClosed = true
          state.isAcceptingPayments = false
        case .clearCart:
          state.paymentState.cart = nil
        case .updateCart(let cart):
          state.paymentState.cart = cart
        default:
          fatalError("unimplemented event")
        }
        return .none
      case .paymentAction:
        return .none
      case .configAction(.registerTerminal):
        return .none
      case let .configAction(.registered(.success(config))):
        state.config = config
        state.alertState =
          AlertContent(
            title: "Registration Complete",
            message: "Successfully registered \(config.terminalName)"
          ).alertState
        return .task {
          return .connect
        }
      case let .configAction(.registered(.failure(error))):
        dump(error)
        state.alertState =
          AlertContent(
            title: "Registration Error",
            message: error.localizedDescription
          ).alertState
        return .none
      case .configAction(_):
        return .none
      }
    }
  }
}

struct RegSetupView: View {
  let store: StoreOf<RegFeature>

  var body: some View {
    NavigationStack {
      WithViewStore(store) { viewStore in
        Form {
          RegSetupStatusView(
            isConnected: viewStore.isConnected,
            lastUpdated: viewStore.lastUpdate
          )

          RegSetupConfigView(
            store: store.scope(
              state: \.configState,
              action: RegFeature.Action.configAction
            ))

          launch(viewStore)
        }
        .navigationTitle("Reg Setup")
        .alert(store.scope(state: \.alertState), dismiss: .alertDismissed)
        .fullScreenCover(
          isPresented: viewStore.binding(
            get: \.isClosed,
            send: .showConfig
          ),
          content: ClosedView.init
        )
        .fullScreenCover(
          isPresented: viewStore.binding(
            get: \.isAcceptingPayments,
            send: .showConfig
          ),
          content: {
            PaymentView(
              store: store.scope(
                state: \.paymentState,
                action: RegFeature.Action.paymentAction
              ))
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
  func launch(_ viewStore: ViewStoreOf<RegFeature>) -> some View {
    Section("Launch") {
      Button {
        viewStore.send(.closeTerminal)
      } label: {
        Label("Close Terminal", systemImage: "xmark.square")
      }

      Button {
        viewStore.send(.acceptPayments)
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
        reducer: RegFeature()
      ))
  }
}
