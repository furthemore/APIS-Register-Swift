//
//  RegSetupConfigView.swift
//  Register
//

import CodeScanner
import ComposableArchitecture
import SwiftUI

@Reducer
struct RegSetupConfigFeature {
  @Dependency(\.config) var config
  @Dependency(\.apis) var apis

  @ObservableState
  struct State: Equatable {
    var terminalName = ""
    var host = ""
    var token = ""

    var canUpdateConfig = true

    var registerRequest = RegisterRequest()
    var isLoading = false

    var isPresentingScanner = false

    var isRegistrationDisabled: Bool {
      isLoading || !registerRequest.isReady
    }

    var fieldColor: Color {
      canUpdateConfig ? .primary : .secondary
    }
  }

  enum Action: BindableAction, Equatable {
    case binding(BindingAction<State>)
    case showScanner(Bool)
    case scannerResult(TaskResult<String>)
    case registerTerminal
    case registered(TaskResult<Config>)
    case clear
  }

  var body: some Reducer<State, Action> {
    BindingReducer()

    Reduce { state, action in
      switch action {
      case .binding(\.terminalName):
        state.registerRequest.terminalName = state.terminalName
        return .none
      case .binding(\.host):
        state.registerRequest.host = state.host
        return .none
      case .binding(\.token):
        state.registerRequest.token = state.token
        return .none
      case .binding:
        return .none
      case let .showScanner(shouldShow):
        state.isPresentingScanner = shouldShow
        return .none
      case .scannerResult:
        state.isPresentingScanner = false
        return .none
      case .registerTerminal:
        state.isLoading = true
        let req = state.registerRequest
        return .run { send in
          do {
            let fetchedConfig = try await apis.registerTerminal(req)
            try await config.save(fetchedConfig)
            await send(.registered(.success(fetchedConfig)))
          } catch {
            await send(.registered(.failure(error)))
          }
        }
      case .registered:
        state.isLoading = false
        return .none
      case .clear:
        state = .init()
        return .run { _ in
          try? await config.clear()
        }
      }
    }
  }
}

struct RegSetupConfigView: View {
  @Bindable var store: StoreOf<RegSetupConfigFeature>

  var body: some View {
    Section("Terminal Registration") {
      TextField(
        text: $store.registerRequest.terminalName,
        prompt: Text("Terminal Name")
      ) {
        Text("Terminal Name")
      }
      .textInputAutocapitalization(.never)
      .autocorrectionDisabled()
      .textContentType(.name)
      .disabled(!store.canUpdateConfig)
      .foregroundColor(store.fieldColor)

      TextField(
        text: $store.registerRequest.host,
        prompt: Text("APIS Host")
      ) {
        Text("APIS Host")
      }
      .keyboardType(.URL)
      .textInputAutocapitalization(.never)
      .autocorrectionDisabled()
      .textContentType(.URL)
      .disabled(!store.canUpdateConfig)
      .foregroundColor(store.fieldColor)

      SecureField(
        text: $store.registerRequest.token,
        prompt: Text("APIS Token")
      ) {
        Text("APIS Token")
      }
      .textContentType(.password)
      .disabled(!store.canUpdateConfig)
      .foregroundColor(store.fieldColor)

      Button {
        store.send(.showScanner(true))
      } label: {
        Label("Import QR Code", systemImage: "qrcode.viewfinder")
      }

      Button {
        store.send(.registerTerminal)
      } label: {
        HStack(spacing: 8) {
          Label("Register Terminal", systemImage: "terminal")
            .foregroundColor(store.isLoading ? .secondary : .accentColor)

          if store.isLoading {
            ProgressView()
          }
        }
      }.disabled(store.isRegistrationDisabled)

      Button(role: .destructive) {
        store.send(.clear)
      } label: {
        Label("Clear Terminal Registration", systemImage: "trash")
          .foregroundColor(.red)
      }
    }
    .disabled(store.isLoading)
    .sheet(
      isPresented: $store.isPresentingScanner.sending(\.showScanner)
    ) {
      CodeScannerView(
        codeTypes: [.qr],
        simulatedData: Register.simulatedQRCode
      ) {
        store.send(
          .scannerResult(
            TaskResult($0.map { $0.string })
          ))
      }
    }
  }
}

struct RegSetupConfigView_Previews: PreviewProvider {
  static var previews: some View {
    Form {
      RegSetupConfigView(
        store: Store(initialState: .init()) {
          RegSetupConfigFeature()
        }
      )
    }
    .previewLayout(.fixed(width: 400, height: 400))
    .previewDisplayName("Invalid Config")

    Form {
      RegSetupConfigView(
        store: Store(initialState: .init(isLoading: true)) {
          RegSetupConfigFeature()
        }
      )
    }
    .previewLayout(.fixed(width: 400, height: 400))
    .previewDisplayName("Loading Config")

    Form {
      RegSetupConfigView(
        store: Store(
          initialState: .init(
            registerRequest: RegisterRequest(
              terminalName: "Terminal Name",
              host: "http://www.google.com",
              token: "Token"
            )
          )
        ) {
          RegSetupConfigFeature()
        }
      )
    }
    .previewLayout(.fixed(width: 400, height: 400))
    .previewDisplayName("Good Config")
  }
}
