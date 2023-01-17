//
//  RegSetupConfigView.swift
//  Register
//

import CodeScanner
import ComposableArchitecture
import SwiftUI

struct RegSetupConfigFeature: ReducerProtocol {
  @Dependency(\.apis) var apis

  struct State: Equatable {
    var registerRequest = RegisterRequest()
    var isLoading = false

    var isPresentingScanner = false

    var isRegistrationDisabled: Bool {
      isLoading || !registerRequest.isReady
    }
  }

  enum Action: BindableAction, Equatable {
    case binding(BindingAction<State>)
    case showScanner(Bool)
    case scannerResult(TaskResult<String>)
    case registerTerminal
    case registered(TaskResult<Config>)
  }

  var body: some ReducerProtocol<State, Action> {
    BindingReducer()

    Reduce { state, action in
      switch action {
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
        return .task {
          let req = req
          do {
            let config = try await apis.registerTerminal(req)
            try await ConfigLoader.saveConfig(config)
            return .registered(.success(config))
          } catch {
            return .registered(.failure(error))
          }
        }
      case .registered:
        state.isLoading = false
        return .none
      }
    }
  }
}

struct RegSetupConfigView: View {
  let store: StoreOf<RegSetupConfigFeature>

  var body: some View {
    WithViewStore(store) { viewStore in
      Section("Terminal Registration") {
        TextField(
          text: viewStore.binding(\.registerRequest.$terminalName),
          prompt: Text("Terminal Name")
        ) {
          Text("Terminal Name")
        }
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()

        TextField(
          text: viewStore.binding(\.registerRequest.$host),
          prompt: Text("APIS Host")
        ) {
          Text("APIS Host")
        }
        .keyboardType(.URL)
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()

        SecureField(
          text: viewStore.binding(\.registerRequest.$token),
          prompt: Text("APIS Token")
        ) {
          Text("APIS Token")
        }

        Button {
          viewStore.send(.showScanner(true))
        } label: {
          Text("Import QR Code")
        }

        Button {
          viewStore.send(.registerTerminal)
        } label: {
          HStack(spacing: 8) {
            Text("Register Terminal")

            if viewStore.isLoading {
              ProgressView()
            }
          }
        }.disabled(viewStore.isRegistrationDisabled)
      }
      .disabled(viewStore.isLoading)
      .sheet(
        isPresented: viewStore.binding(
          get: \.isPresentingScanner,
          send: RegSetupConfigFeature.Action.showScanner
        )
      ) {
        CodeScannerView(
          codeTypes: [.qr],
          simulatedData: Register.simulatedQRCode
        ) {
          viewStore.send(
            .scannerResult(
              TaskResult($0.map { $0.string })
            ))
        }
      }
    }
  }
}

struct RegSetupConfigView_Previews: PreviewProvider {
  static var previews: some View {
    Form {
      RegSetupConfigView(
        store: Store(
          initialState: .init(),
          reducer: RegSetupConfigFeature()
        ))
    }
    .previewLayout(.fixed(width: 400, height: 400))
    .previewDisplayName("Invalid Config")

    Form {
      RegSetupConfigView(
        store: Store(
          initialState: .init(isLoading: true),
          reducer: RegSetupConfigFeature()
        ))
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
          ),
          reducer: RegSetupConfigFeature()
        ))
    }
    .previewLayout(.fixed(width: 400, height: 400))
    .previewDisplayName("Good Config")
  }
}
