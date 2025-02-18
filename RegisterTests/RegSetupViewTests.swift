//
//  RegSetupViewTests.swift
//  RegisterTests
//

import ComposableArchitecture
import SquareMobilePaymentsSDK
import XCTest

@testable import Register

@MainActor
final class RegSetupViewTests: XCTestCase {
  private typealias Feature = RegSetupFeature
  private typealias State = Feature.State

  func testAppearLoadsConfig() async throws {
    let store = TestStore(initialState: State()) {
      Feature()
    } withDependencies: {
      $0.square.isAuthorized = { true }
      $0.config.load = { .mock }
      $0.apis.subscribeToEvents = { _ in .none }
    }

    await store.send(.appeared) {
      $0.regState.squareIsReady = true
    }

    await store.receive(.configLoaded(.success(.mock))) {
      $0.regState.needsConfigLoad = false
      $0.setConfig(.mock)
    }
  }

  func testMissingConfigIsLoaded() async throws {
    let store = TestStore(initialState: State()) {
      Feature()
    } withDependencies: {
      $0.square.isAuthorized = { true }
      $0.config.load = { nil }
      $0.apis.subscribeToEvents = { _ in .none }
    }

    await store.send(.appeared) {
      $0.regState.squareIsReady = true
    }

    await store.receive(.configLoaded(.success(.empty))) {
      $0.regState.needsConfigLoad = false
      $0.setConfig(.empty)
    }
  }

  func testSetMode() async throws {
    let store = TestStore(initialState: State()) {
      Feature()
    }

    await store.send(.setMode(.acceptPayments)) {
      $0.regState.mode = .acceptPayments
    }

    await store.send(.setMode(.close)) {
      $0.regState.mode = .close
    }

    await store.send(.setMode(.setup)) {
      $0.regState.mode = .setup
    }
  }

  func testSetConfig() async throws {
    var state = State()
    XCTAssertEqual(state.config, .empty)
    XCTAssertEqual(state.configState.registerRequest, .init(config: .empty))
    XCTAssertEqual(state.squareSetupState.config, .empty)
    XCTAssertEqual(state.paymentState.webViewURL, Register.fallbackURL)

    state.setConfig(.mock)
    XCTAssertEqual(state.config, .mock)
    XCTAssertEqual(state.configState.registerRequest, .init(config: .mock))
    XCTAssertEqual(state.squareSetupState.config, .mock)
    XCTAssertEqual(state.paymentState.webViewURL, try XCTUnwrap(URL(string: "http://example.com")))
  }

  func testSetAlert() async throws {
    var state = State()
    XCTAssertNil(state.alertState)

    state.setAlert(title: "title", message: "message")
    XCTAssertEqual(state.alertState, standardAlertState(title: "title", message: "message"))
  }

  func testRegisteringTerminal() async throws {
    let expectation = XCTestExpectation()
    let lastEvent = Date(timeIntervalSince1970: 1000)

    let store = TestStore(initialState: State()) {
      Feature()
    } withDependencies: {
      $0.apis.registerTerminal = { _ in .mock }
      $0.config.save = { _ in expectation.fulfill() }
      $0.apis.subscribeToEvents = { _ in .run { send in await send(.success(.connected)) } }
      $0.date.now = lastEvent
    }

    await store.send(.configAction(.registerTerminal)) {
      $0.regState.isConnected = false
      $0.configState.canUpdateConfig = true
      $0.configState.isLoading = true
    }

    await store.receive(.configAction(.registered(.success(.mock)))) {
      $0.setConfig(.mock)
      $0.setAlert(
        title: "Registration Complete",
        message: "Successfully registered \(Config.mock.terminalName)"
      )
      $0.regState.isConnected = false
      $0.configState.isLoading = false
      $0.configState.canUpdateConfig = true
    }

    await fulfillment(of: [expectation], timeout: 1)

    await store.receive(.terminalEvent(.success(.connected))) {
      $0.regState.isConnected = true
      $0.regState.lastEvent = lastEvent
      $0.configState.canUpdateConfig = false
    }
  }

  func testDecodeQrCode() async throws {
    let store = TestStore(initialState: State()) {
      Feature()
    }

    await store.send(.configAction(.scannerResult(.success(Register.simulatedQRCode)))) {
      $0.regState.isConnected = false
      $0.configState.canUpdateConfig = true
      $0.alertState = self.standardAlertState(
        title: "Imported QR Code",
        message: "Successfully imported data."
      )
      $0.configState.registerRequest = .init(
        terminalName: "name",
        host: "http://localhost:8080",
        token: "helloworld"
      )
    }
  }

  func testClearingDisconnects() async throws {
    let expectation = XCTestExpectation()

    let store = TestStore(
      initialState: State(
        regState: .init(isConnected: true),
        configState: .init(canUpdateConfig: false)
      )
    ) {
      Feature()
    } withDependencies: {
      $0.config.clear = { expectation.fulfill() }
    }

    await store.send(.configAction(.clear)) {
      $0.regState.isConnected = false
      $0.configState.canUpdateConfig = true
    }

    await fulfillment(of: [expectation], timeout: 1)
  }

  func testChangingSquareAuthorization() async throws {
    let store = TestStore(initialState: State()) {
      Feature()
    } withDependencies: {
      $0.square.authorizedLocation = { .mock }
    }

    await store.send(.squareSetupAction(.authorized)) {
      $0.regState.squareIsReady = true
      $0.squareSetupState.isAuthorized = true
      $0.squareSetupState.authorizedLocation = .mock
    }

    await store.send(.squareSetupAction(.didRemoveAuthorization)) {
      $0.regState.squareIsReady = false
      $0.squareSetupState.isAuthorized = false
      $0.squareSetupState.authorizedLocation = nil
    }
  }

  func testSquarePayments() async throws {
    let store = TestStore(
      initialState: State(
        paymentState: .init(
          webViewURL: Register.fallbackURL,
          themeColor: Register.fallbackThemeColor,
          currentTransactionReference: SquareCompletedTransaction.mock.reference)
      )
    ) {
      Feature()
    } withDependencies: {
      $0.apis.squareTransactionCompleted = { _, tx in
        XCTAssertEqual(tx, .mock)
        return false
      }
    }

    await store.send(.squareCheckoutAction(.finished(.success(.mock))))

    await store.receive(.squareTransactionCompleted(false)) {
      $0.paymentState.alert = AlertState {
        TextState("Error")
      } message: {
        TextState("Payment was not successful.")
      }
    }

    store.dependencies.apis.squareTransactionCompleted = { _, tx in
      XCTAssertEqual(tx, .mock)
      return true
    }

    await store.send(.squareCheckoutAction(.finished(.success(.mock))))

    await store.receive(.squareTransactionCompleted(true)) {
      $0.paymentState.cart = nil
      $0.paymentState.currentTransactionReference = ""
    }
  }

  func testEventConnections() async throws {
    let disconnectedStore = TestStore(initialState: State()) {
      Feature()
    }

    await disconnectedStore.send(.scenePhaseChanged(.active))

    let connectedStore = TestStore(
      initialState: State(
        regState: .init(isConnected: true)
      )
    ) {
      Feature()
    } withDependencies: {
      $0.apis.subscribeToEvents = { _ in .none }
    }

    await connectedStore.send(.scenePhaseChanged(.inactive))

    await connectedStore.send(.scenePhaseChanged(.active)) {
      $0.regState.isConnected = false
      $0.configState.canUpdateConfig = true
    }
  }

  func testTerminalOpen() async throws {
    let date = Date(timeIntervalSince1970: 1000)

    let storeNoSquare = TestStore(
      initialState: State(
        paymentState: .init(
          webViewURL: Register.fallbackURL,
          themeColor: Register.fallbackThemeColor,
          currentTransactionReference: "MOCK-REF"
        ))
    ) {
      Feature()
    } withDependencies: {
      $0.date.now = date
    }

    await storeNoSquare.send(.terminalEvent(.success(.open))) {
      $0.regState.isConnected = true
      $0.regState.lastEvent = date
      $0.configState.canUpdateConfig = false

      $0.paymentState.currentTransactionReference = ""

      $0.setAlert(title: "Opening Failed", message: "Square is not yet configured.")
    }

    let storeWithSquare = TestStore(
      initialState: State(
        regState: .init(squareIsReady: true),
        paymentState: .init(
          webViewURL: Register.fallbackURL,
          themeColor: Register.fallbackThemeColor,
          currentTransactionReference: "MOCK-REF"
        ))
    ) {
      Feature()
    } withDependencies: {
      $0.date.now = date
    }

    await storeWithSquare.send(.terminalEvent(.success(.open))) {
      $0.regState.isConnected = true
      $0.regState.lastEvent = date
      $0.configState.canUpdateConfig = false

      $0.paymentState.currentTransactionReference = ""
      $0.regState.mode = .acceptPayments
    }
  }

  func testTerminalClose() async throws {
    let date = Date(timeIntervalSince1970: 1000)

    let store = TestStore(initialState: State()) {
      Feature()
    } withDependencies: {
      $0.date.now = date
    }

    await store.send(.terminalEvent(.success(.close))) {
      $0.regState.isConnected = true
      $0.regState.lastEvent = date
      $0.configState.canUpdateConfig = false

      $0.paymentState.currentTransactionReference = ""
      $0.regState.mode = .close
    }
  }

  func testTerminalClearCart() async throws {
    let date = Date(timeIntervalSince1970: 1000)

    let store = TestStore(
      initialState: State(
        paymentState: .init(
          webViewURL: Register.fallbackURL,
          themeColor: Register.fallbackThemeColor,
          cart: .mock,
          currentTransactionReference: "MOCK-REF"
        ))
    ) {
      Feature()
    } withDependencies: {
      $0.date.now = date
    }

    await store.send(.terminalEvent(.success(.updateCart(cart: .mock)))) {
      $0.regState.isConnected = true
      $0.regState.lastEvent = date
      $0.configState.canUpdateConfig = false

      $0.paymentState.currentTransactionReference = ""
      $0.paymentState.cart = .mock
      $0.paymentState.alert = nil
    }
  }

  func testTerminalProcessPayment() async throws {
    let expectation = XCTestExpectation()
    let date = Date(timeIntervalSince1970: 1000)

    let store = TestStore(
      initialState: State(
        paymentState: .init(
          webViewURL: Register.fallbackURL,
          themeColor: Register.fallbackThemeColor,
          cart: .mock,
          currentTransactionReference: "MOCK-REF"
        ))
    ) {
      Feature()
    } withDependencies: {
      $0.date.now = date
      $0.uuid = UUIDGenerator.incrementing
      $0.square.checkout = { params in
        XCTAssertEqual(params.idempotencyKey, "00000000-0000-0000-0000-000000000000")
        XCTAssertEqual(params.totalMoney as! Money, Money(amount: 6000, currency: .USD))
        XCTAssertEqual(params.referenceID, "MOCK-REF")
        expectation.fulfill()
        return .finished
      }
    }

    await store.send(
      .terminalEvent(
        .success(
          .processPayment(
            total: 6000,
            note: "note",
            reference: "MOCK-REF")
        ))
    ) {
      $0.regState.isConnected = true
      $0.regState.lastEvent = date
      $0.configState.canUpdateConfig = false

      $0.paymentState.currentTransactionReference = "MOCK-REF"
    }

    await fulfillment(of: [expectation], timeout: 1)
  }

  private func standardAlertState(title: String, message: String) -> AlertState<Feature.Action> {
    return AlertState {
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
