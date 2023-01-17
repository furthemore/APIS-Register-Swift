//
//  ContentView.swift
//  Register
//

import ComposableArchitecture
import SwiftUI

struct RegFeature: ReducerProtocol {
  @Dependency(\.apis) var apis

  struct State: Equatable {
    var isLoadingConfig: Bool = true
    var isRegistering: Bool = false
    var alertState: AlertState<Action>? = nil

    var isConnected: Bool = false
    var lastUpdate: Date? = nil

    var hasChangedConfig: Bool = false
    var config: Config = Config.empty

    var isAcceptingPayments: Bool = false
    var isClosed: Bool = false

    var cart: TerminalCart = .empty

    var paymentState: PayFeature.State = .init(
      webViewURL: URL(string: "https://furthemore.org/code-of-conduct/")!
    )

    var registrationDisabled: Bool {
      return isLoadingConfig || config.terminalName.isEmpty || config.host.isEmpty
        || config.token.isEmpty || !hasChangedConfig || isRegistering
        || !Self.isValidHost(host: config.host)
    }

    var isLoading: Bool {
      return isLoadingConfig || isRegistering
    }

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
  }

  enum Action: Equatable {
    case appeared
    case configLoaded(Config)
    case showConfig, acceptPayments, closeTerminal
    case disabled
    case updateName(String)
    case updateHost(String)
    case updateToken(String)
    case registerTerminal
    case setErrorMessage(AlertContent?)
    case alertDismissed
    case registrationComplete
    case updateStatus(Bool, Date)
    case terminalEvent(TerminalEvent)
    case paymentAction(PayFeature.Action)
  }

  private enum SubID {}

  func reduce(into state: inout State, action: Action) -> EffectTask<Action> {
    dump(action)
    switch action {
    case .appeared:
      return .task {
        let config = try? await ConfigLoader.loadConfig()
        return .configLoaded(config ?? Config.empty)
      }
    case let .configLoaded(config):
      state.config = config
      state.isLoadingConfig = false
      return .none
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
    case .updateName(let name):
      state.config.terminalName = name
      state.hasChangedConfig = true
      return .none
    case .updateHost(let host):
      state.config.host = host
      state.hasChangedConfig = true
      return .none
    case .updateToken(let token):
      state.config.token = token
      state.hasChangedConfig = true
      return .none
    case .registerTerminal:
      state.isRegistering = true
      let config = state.config
      return .task {
        var config = config
        do {
          let key = try await apis.registerTerminal(config)
          config.key = key
          try await ConfigLoader.saveConfig(config)
          return .registrationComplete
        } catch {
          return .setErrorMessage(
            AlertContent(
              title: "Error",
              message: error.localizedDescription
            ))
        }
      }
    case .registrationComplete:
      state.isRegistering = false
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
                  print("got payload with no data")
                  continue
                }

                #if DEBUG
                  if let str = String(data: data, encoding: .utf8) {
                    print("got data: \(str)")
                  }
                #endif

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
            print("Subscription cancel")
            try! client.syncShutdownGracefully()
          }
        } catch {
          dump(error)
          await send(
            .setErrorMessage(
              AlertContent(
                title: "Error",
                message: error.localizedDescription
              )))
        }
      }.cancellable(id: SubID.self, cancelInFlight: true)
    case let .setErrorMessage(.some(content)):
      state.isRegistering = false
      state.alertState = AlertState {
        TextState(content.title)
      } actions: {
        ButtonState(action: .alertDismissed) {
          TextState("OK")
        }
      } message: {
        TextState(content.message)
      }
      return .none
    case .setErrorMessage(_):
      state.isRegistering = false
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
        print("got other event: \(event)")
      }
      return .none
    case .paymentAction(let payAction):
      dump(payAction)
      return .none
    case .disabled:
      return .none
    }
  }
}

struct ContentView: View {
  let store: StoreOf<RegFeature>

  var body: some View {
    NavigationStack {
      WithViewStore(store) { viewStore in
        Form {
          status(viewStore)
          config(viewStore)
          launch(viewStore)
        }
        .navigationTitle("Registration App Setup")
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
  func status(_ viewStore: ViewStoreOf<RegFeature>) -> some View {
    Section("Status") {
      Toggle(
        isOn: viewStore.binding(
          get: \.isConnected,
          send: .disabled
        )
      ) {
        Text("Connected")
      }

      HStack {
        Text("Last Update")
        Spacer()
        if let lastUpdate = viewStore.lastUpdate {
          Text(lastUpdate, format: .dateTime)
        } else {
          Text("never").bold()
        }
      }
    }
    .disabled(true)
    .foregroundColor(.secondary)
  }

  @ViewBuilder
  func config(_ viewStore: ViewStoreOf<RegFeature>) -> some View {
    Section("Config") {
      TextField(
        text: viewStore.binding(
          get: \.config.terminalName,
          send: RegFeature.Action.updateName
        ),
        prompt: Text("Terminal Name")
      ) {
        Text("Terminal Name")
      }

      TextField(
        text: viewStore.binding(
          get: \.config.host,
          send: RegFeature.Action.updateHost
        ),
        prompt: Text("Host")
      ) {
        Text("Host")
      }
      .keyboardType(.URL)

      SecureField(
        text: viewStore.binding(
          get: \.config.token,
          send: RegFeature.Action.updateToken
        ),
        prompt: Text("Token")
      ) {
        Text("Token")
      }

      SecureField(
        text: viewStore.binding(
          get: \.config.key,
          send: RegFeature.Action.disabled
        ),
        prompt: Text("API Key")
      ) {
        Text("API Key")
      }
      .disabled(true)
      .foregroundColor(.secondary)

      Button {
        viewStore.send(.registerTerminal)
      } label: {
        HStack(spacing: 8) {
          Label("Register Terminal", systemImage: "cloud.bolt")

          if viewStore.isLoading {
            ProgressView()
          }
        }
      }
      .disabled(viewStore.registrationDisabled)
    }
    .disabled(viewStore.isLoadingConfig)
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
    ContentView(
      store: Store(
        initialState: .init(),
        reducer: RegFeature()
      ))
  }
}
