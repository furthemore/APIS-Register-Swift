//
//  ContentView.swift
//  Register
//

import AVFoundation
import CodeScanner
import Combine
import ComposableArchitecture
import ExternalAccessory
import Foundation
import PDFKit
import SquareMobilePaymentsSDK
import SwiftUI

@Reducer
struct RegSetupFeature {
  @Dependency(\.config) var config
  @Dependency(\.apis) var apis
  @Dependency(\.square) var square
  @Dependency(\.date) var date
  @Dependency(\.uuid) var uuid
  @Dependency(\.zebra) var zebra

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
    enum ConnectionState: Equatable {
      case disconnected
      case connecting
      case connected

      var isConnecting: Bool {
        self == .connecting
      }

      var isConnected: Bool {
        self == .connected
      }

      var wantsConnection: Bool {
        isConnected || isConnecting
      }
    }

    var needsConfigLoad = true

    var connectionState: ConnectionState = .disconnected
    var lastEvent: Date? = nil

    var mode = Mode.setup

    var isConfiguringSquare = false
    var squareIsReady = false
    var squareWasInitialized = false

    var isPresentingPayment = false
    var isPresentingPrint = false
  }

  @ObservableState
  struct State: Equatable {
    @Presents var alert: AlertState<Action.Alert>? = nil

    var config: Config? = nil

    var regState: RegState = .init()
    var configState: RegSetupConfigFeature.State = .init()

    var squareSetupState: SquareSetupFeature.State? = nil
    var paymentState: PaymentFeature.State? = nil
    var printState: PrintFeature.State? = nil

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

    func notify(_ notification: FrontendNotification, _ apis: ApisClient) -> Effect<Action> {
      guard let config = config else {
        return .none
      }

      return .run { send in
        do {
          try await apis.notifyFrontend(config, notification)
        } catch {
          await send(.setErrorMessage(title: "Notify Error", message: error.localizedDescription))
        }
      }
    }
  }

  enum Action {
    case appeared
    case scenePhaseChanged(ScenePhase)

    case setMode(Mode)
    case setConfiguringSquare(Bool)
    case setErrorMessage(title: String, message: String)
    case windowEvent(WindowEvent)

    case configLoaded(TaskResult<Config>)
    case connectToggle

    case terminalEvent(Result<TerminalEvent, Error>)
    case squareTransactionCompleted(Bool)

    case showPrint(Bool)
    case zebraEvent(ZebraEvent)

    case alert(PresentationAction<Alert>)
    case configAction(RegSetupConfigFeature.Action)
    case squareSetupAction(SquareSetupFeature.Action)
    case squareCheckoutAction(SquareCheckoutAction)
    case paymentAction(PaymentFeature.Action)
    case printAction(PrintFeature.Action)

    enum Alert: Equatable {
      case dismiss
    }
  }

  enum CancelID: Hashable {
    case events
  }

  var body: some Reducer<State, Action> {
    Scope(state: \.configState, action: \.configAction) {
      RegSetupConfigFeature()
    }

    Reduce { state, action in
      switch action {
      case .appeared:
        state.regState.squareIsReady = square.isAuthorized()
        state.regState.squareWasInitialized = square.wasInitialized()
        return .merge(
          .run { send in
            do {
              if let config = try await config.load() {
                await send(.configLoaded(.success(config)))
              } else {
                await send(.configLoaded(.failure(ConfigError.missingConfig)))
              }
            } catch {
              await send(.configLoaded(.failure(error)))
            }
          },
          .run { send in
            for await event in zebra.events() {
              await send(.zebraEvent(event))
            }
          }
        ).animation(.easeInOut)

      case .scenePhaseChanged(let phase):
        // Ensure MQTT is connected when becoming active.
        if phase == .active && state.regState.connectionState.wantsConnection {
          return connect(&state).animation(.easeInOut)
        } else {
          return .none
        }

      case .setMode(.acceptPayments), .windowEvent(.open):
        if let config = state.config, state.regState.connectionState.isConnected {
          state.regState.mode = .acceptPayments
          state.paymentState = .init(
            webViewUrl: config.webViewUrl,
            themeColor: config.parsedColor
          )
        }
        return .none
      case .setMode(let mode):
        state.regState.mode = mode
        return .none
      case .windowEvent(.close):
        state.regState.mode = .close
        return .none
      case .windowEvent(.setup):
        state.regState.mode = .setup
        return .none

      case .setConfiguringSquare(let configuring):
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

      case .setErrorMessage(let title, let message):
        state.setAlert(title: title, message: message)
        return .none

      case .configLoaded(.success(let config)):
        state.config = config
        state.regState.needsConfigLoad = false
        return setUpEvents(&state)
      case .configLoaded(.failure(ConfigError.missingConfig)):
        state.regState.needsConfigLoad = false
        return .none
      case .configLoaded(.failure(let error)):
        state.regState.needsConfigLoad = false
        state.setAlert(
          title: "Config Load Error",
          message: error.localizedDescription
        )
        return .run { _ in
          try! await config.clear()
        }

      case .connectToggle:
        if state.regState.connectionState.wantsConnection {
          return disconnect(state: &state)
        } else {
          return setUpEvents(&state)
        }

      case .terminalEvent(let event):
        return handleTerminalEvent(&state, event: event).animation(.easeInOut)

      case .squareTransactionCompleted(false):
        state.paymentState?.alert = AlertState {
          TextState("Error")
        } message: {
          TextState("Payment was not successful.")
        }
        return .none
      case .squareTransactionCompleted:
        return .none

      case .alert(.dismiss):
        state.alert = nil
        return .none
      case .alert:
        return .none

      case .configAction(.scannerResult(.success(let payload))):
        return decodeQRCode(state: &state, payload: payload)
      case .configAction(.scannerResult(.failure(let error))):
        state.setAlert(
          title: "QR Code Error",
          message: error.localizedDescription
        )
        return .none
      case .configAction(.clear):
        return .concatenate(
          .run { _ in
            try! await square.deauthorize()
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
        state.regState.isPresentingPayment = false
        return state.notify(.paymentCancelled, apis)
      case .squareCheckoutAction(.finished(.failure(let error))):
        state.regState.isPresentingPayment = false
        state.paymentState?.alert = AlertState {
          TextState("Error")
        } message: {
          TextState(error.localizedDescription)
        }
        return state.notify(.paymentFailed, apis)
      case .squareCheckoutAction(.finished(.success(let result))):
        state.regState.isPresentingPayment = false
        var effects = [state.notify(.paymentCompleted, apis)]

        guard let config = state.config, var paymentState = state.paymentState else {
          return .concatenate(effects)
        }

        guard let paymentId = result.paymentId, let referenceId = result.referenceId else {
          paymentState.alert = AlertState {
            TextState("Error")
          } message: {
            TextState("Finished payment was missing ID or reference.")
          }
          return .concatenate(effects)
        }

        let transaction = SquareCompletedTransaction(
          reference: referenceId,
          paymentId: paymentId
        )

        effects.append(
          .run { send in
            let isValidTransaction: Bool
            do {
              isValidTransaction = try await apis.squareTransactionCompleted(config, transaction)
            } catch {
              Register.logger.error("Checkout failed: \(error, privacy: .public)")
              isValidTransaction = false
            }
            await send(.squareTransactionCompleted(isValidTransaction))
          }.animation(.easeInOut)
        )

        return .concatenate(effects)

      case .paymentAction(.dismissView):
        state.regState.mode = .setup
        return .none
      case .paymentAction(.registrationCompleted):
        return state.notify(.registrationCompleted, apis)
      case .paymentAction:
        return .none

      case .showPrint(let show):
        state.regState.isPresentingPrint = show
        state.printState = show ? state.printState ?? .init() : nil
        return .none

      case .zebraEvent, .printAction:
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
    .ifLet(\.printState, action: \.printAction) {
      PrintFeature()
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

  private func setUpEvents(_ state: inout State) -> Effect<Action> {
    guard let config = state.config else {
      return .none
    }

    return .concatenate(
      disconnect(state: &state),
      apis
        .setUpEvents(config)
        .map(Action.terminalEvent)
        .cancellable(id: CancelID.events, cancelInFlight: true)
    )
    .animation(.easeInOut)
  }

  private func connect(_ state: inout State) -> Effect<Action> {
    state.regState.connectionState = .connecting

    return .run { send in
      do {
        try await apis.connectEvents()
        await send(.terminalEvent(.success(.connected)))
      } catch {
        await send(.terminalEvent(.failure(error)))
      }
    }
    .animation(.easeInOut)
  }

  private func disconnect(state: inout State) -> Effect<Action> {
    let wantedConnection = state.regState.connectionState.wantsConnection
    state.regState.connectionState = .disconnected

    if wantedConnection {
      return .run { send in
        try? await apis.disconnectEvents()
      }
      .animation(.easeInOut)
    } else {
      return .none
    }
  }

  private func handleTerminalEvent(
    _ state: inout State,
    event: Result<TerminalEvent, Error>
  ) -> Effect<Action> {
    if case .success(let event) = event, !event.isFakeEvent {
      state.regState.lastEvent = date.now
    }

    switch event {
    case .success(.setUp):
      return connect(&state)
    case .success(.connected):
      state.regState.connectionState = .connected
      return .none
    case .success(.disconnected):
      let wasConnected = state.regState.connectionState.isConnected
      state.regState.connectionState = .disconnected

      if wasConnected {
        return setUpEvents(&state)
      } else {
        return .none
      }
    case .success(.state(.open)), .success(.state(.ready)):
      if state.regState.mode != .acceptPayments {
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
      }
      return .none
    case .success(.state(.close)):
      state.paymentState = nil
      state.regState.mode = .close
      return .none
    case .success(.state):
      return .none
    case .success(.cartClear):
      state.paymentState?.alert = nil
      state.paymentState?.cart = nil
      state.paymentState?.webViewActionPublisher.send(.resetScroll)
      state.paymentState?.showingRegistration = false
      return .none
    case .success(.cartUpdate(let cart)):
      state.paymentState?.alert = nil
      state.paymentState?.cart = cart
      return .none
    case .success(.process(let payment)):
      guard let paymentState = state.paymentState else {
        state.setAlert(
          title: "No Payment State",
          message: "Payments have not yet been enabled."
        )
        return .none
      }

      if state.regState.isPresentingPayment {
        return .none
      }

      state.regState.isPresentingPayment = true

      let params = SquarePaymentParams(
        paymentAttemptId: payment.paymentAttemptId,
        amountMoney: Money(amount: payment.total, currency: .USD),
        referenceId: payment.reference,
        orderId: payment.orderId,
        note: payment.orderId == nil ? payment.note : nil
      )

      return .concatenate(
        state.notify(.paymentOpened, apis),
        .run { [viewController = paymentState.viewController] send in
          do {
            for await action in try await square.checkout(params, viewController) {
              await send(.squareCheckoutAction(action))
            }
          } catch {
            await send(
              .setErrorMessage(
                title: "Error",
                message: "Could not create checkout: \(error.localizedDescription)"
              )
            )
          }
        }
      )
    case .success(.updateToken(let tokens)):
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
          try await square.authorize(tokens.accessToken, currentConfig.squareLocationId)
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
    case .success(.updateConfig(let updatedConfig)):
      let existingConfig = state.config

      state.config = updatedConfig

      state.paymentState?.themeColor = updatedConfig.parsedColor
      state.paymentState?.webViewUrl = updatedConfig.webViewUrl

      if state.regState.isConfiguringSquare {
        state.regState.isConfiguringSquare = false
        state.squareSetupState = nil
      }

      let updatedAppId = existingConfig?.squareApplicationId != updatedConfig.squareApplicationId

      if updatedAppId {
        state.setAlert(
          title: "Updated Config",
          message: "Square Application ID changed, you must relaunch the app."
        )
      }

      return .concatenate(
        .run { _ in
          try! await config.save(updatedConfig)
        },
        setUpEvents(&state)
      )

    case .success(.print(let print)):
      return .run { send in
        do {
          let (data, _) = try await URLSession.shared.data(from: print.url)

          guard let pdf = PDFDocument(data: data) else {
            await send(
              .setErrorMessage(
                title: "Print Error",
                message: "Could not open data as PDF"
              )
            )
            return
          }

          for pageIndex in 0..<pdf.pageCount {
            let page = pdf.page(at: pageIndex)!
            page.rotation = 270
          }

          let pdfData = pdf.dataRepresentation()!

          try await zebra.print(pdfData, print.serialNumber)
        } catch {
          await send(
            .setErrorMessage(
              title: "Print Error",
              message: error.localizedDescription
            )
          )
        }
      }

    case .success(.registrationDisplay(let display)):
      state.paymentState?.showingRegistration = true
      state.paymentState?.regWebActionPublisher.send(
        .navigate(to: display.url, token: display.token)
      )
      return state.notify(.registrationOpened, apis)

    case .success(.registrationCancel):
      state.paymentState?.showingRegistration = false
      return .none

    case .failure(let error):
      state.setAlert(
        title: "Event Error",
        message: error.localizedDescription
      )
      return disconnect(state: &state)
    }
  }
}

enum WindowEvent {
  case setup, open, close
}

struct RegSetupView: View {
  @SwiftUICore.Environment(\.scenePhase) var scenePhase

  @Bindable var store: StoreOf<RegSetupFeature>

  let windowEvents: PassthroughSubject<WindowEvent, Never>

  var body: some View {
    NavigationStack {
      Form {
        status
        launch

        Section("Printer") {
          Button("Printers", systemImage: "printer") {
            store.send(.showPrint(true))
          }
        }

        Section("Square") {
          Button("Square Setup", systemImage: "square") {
            store.send(.setConfiguringSquare(true))
          }
          .disabled(store.config == nil || !store.regState.squareWasInitialized)
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
      .sheet(
        isPresented: Binding(
          get: {
            store.configState.isPresentingScanner
          },
          set: { newValue in
            store.send(.configAction(.showScanner(newValue)))
          })
      ) {
        codeScanner
      }
      .sheet(
        isPresented: Binding(
          get: {
            store.regState.isPresentingPrint
          },
          set: { newValue in
            store.send(.showPrint(newValue))
          }
        )
      ) {
        if let store = store.scope(state: \.printState, action: \.printAction) {
          PrintView(store: store)
        }
      }
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
      .onReceive(windowEvents) { event in
        store.send(.windowEvent(event))
      }
    }
  }

  @ViewBuilder
  var status: some View {
    RegSetupStatusView(
      terminalName: Binding(
        get: { store.config?.terminalName },
        set: { _ in }
      ),
      isConnecting: Binding(
        get: { store.regState.connectionState.isConnecting },
        set: { _ in }
      ),
      isConnected: Binding(
        get: { store.regState.connectionState.isConnected },
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
  }

  @ViewBuilder
  var launch: some View {
    Section("Launch") {
      Button("Accept Payments", systemImage: "creditcard") {
        store.send(.setMode(.acceptPayments))
      }
      .disabled(!store.regState.squareIsReady || !store.regState.connectionState.isConnected)

      Button("Close Terminal", systemImage: "xmark.square") {
        store.send(.setMode(.close))
      }
    }
  }

  @ViewBuilder
  var codeScanner: some View {
    CodeScannerView(
      codeTypes: [.qr],
      simulatedData: Register.simulatedQRCode,
      videoCaptureDevice: AVCaptureDevice.default(
        .builtInWideAngleCamera,
        for: .video,
        position: store.configState.preferFrontCamera ? .front : .unspecified
      )
    ) {
      store.send(
        .configAction(
          .scannerResult(
            TaskResult($0.map { $0.string })
          )))
    }
  }
}

#Preview {
  RegSetupView(
    store: Store(initialState: .init()) {
      RegSetupFeature()
    },
    windowEvents: .init()
  )
}
