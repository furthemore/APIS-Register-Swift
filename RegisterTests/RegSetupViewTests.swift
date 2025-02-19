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
    let store = TestStore(initialState: State(config: .mock)) {
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
      $0.regState.isConnecting = true
      $0.config = .mock
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

    await store.receive(.configLoaded(.failure(ConfigError.missingConfig))) {
      $0.regState.needsConfigLoad = false
      $0.config = nil
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

  func testSetAlert() async throws {
    var state = State()
    XCTAssertNil(state.alert)

    state.setAlert(title: "title", message: "message")
    XCTAssertEqual(state.alert, standardAlertState(title: "title", message: "message"))
  }

  func testDecodeQrCode() async throws {
    let expectation = XCTestExpectation()

    let store = TestStore(initialState: State()) {
      Feature()
    } withDependencies: {
      $0.config.save = { _ in expectation.fulfill() }
    }

    await store.send(.configAction(.scannerResult(.success(Register.simulatedQRCode)))) {
      $0.config = .mock
      $0.alert = self.standardAlertState(
        title: "Imported QR Code",
        message: "Successfully imported data."
      )
    }

    await fulfillment(of: [expectation], timeout: 1)
  }

  func testClearingDisconnects() async throws {
    let expectation = XCTestExpectation()
    expectation.expectedFulfillmentCount = 2

    let store = TestStore(
      initialState: State(
        regState: .init(isConnected: true),
        configState: .init()
      )
    ) {
      Feature()
    } withDependencies: {
      $0.config.clear = { expectation.fulfill() }
      $0.square.deauthorize = { expectation.fulfill() }
    }

    await store.send(.configAction(.clear)) {
      $0.regState.isConnected = false
    }

    await fulfillment(of: [expectation], timeout: 1)
  }

  func testChangingSquareAuthorization() async throws {
    let store = TestStore(initialState: State(squareSetupState: .init(config: .mock))) {
      Feature()
    } withDependencies: {
      $0.square.wasInitialized = { true }
      $0.square.authorizedLocation = { .mock }
    }

    await store.send(.squareSetupAction(.authorized)) {
      $0.regState.squareIsReady = true
      $0.squareSetupState?.hasAuthorizedSquare = true
      $0.squareSetupState?.squareAuthorizedLocation = .mock
    }

    await store.send(.squareSetupAction(.didRemoveAuthorization)) {
      $0.regState.squareIsReady = false
      $0.squareSetupState?.hasAuthorizedSquare = false
      $0.squareSetupState?.squareAuthorizedLocation = nil
    }
  }

  func testSquarePayments() async throws {
    let store = TestStore(
      initialState: State(
        config: .mock,
        paymentState: .init(
          webViewUrl: Register.fallbackURL,
          themeColor: Register.fallbackThemeColor)
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
      $0.paymentState?.alert = AlertState {
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

    await store.receive(.squareTransactionCompleted(true))
  }

  func testEventConnections() async throws {
    let disconnectedStore = TestStore(initialState: State()) {
      Feature()
    }

    await disconnectedStore.send(.scenePhaseChanged(.active))

    let connectedStore = TestStore(
      initialState: State(
        config: .mock,
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
      $0.regState.isConnecting = true
    }
  }

  func testTerminalOpen() async throws {
    let date = Date(timeIntervalSince1970: 1000)

    let storeNoSquare = TestStore(
      initialState: State(
        paymentState: .init(
          webViewUrl: Register.fallbackURL,
          themeColor: Register.fallbackThemeColor
        ))
    ) {
      Feature()
    } withDependencies: {
      $0.date.now = date
    }

    await storeNoSquare.send(.terminalEvent(.success(.open))) {
      $0.regState.isConnected = true
      $0.regState.lastEvent = date

      $0.setAlert(title: "Opening Failed", message: "Terminal has not been fully configured.")
    }

    let storeWithSquare = TestStore(
      initialState: State(
        config: .mock,
        regState: .init(squareIsReady: true),
        paymentState: .init(
          webViewUrl: Config.mock.webViewUrl,
          themeColor: Config.mock.parsedColor
        ))
    ) {
      Feature()
    } withDependencies: {
      $0.square.wasInitialized = { true }
      $0.date.now = date
    }

    await storeWithSquare.send(.terminalEvent(.success(.open))) {
      $0.regState.isConnected = true
      $0.regState.lastEvent = date

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

      $0.regState.mode = .close
    }
  }

  func testTerminalClearCart() async throws {
    let date = Date(timeIntervalSince1970: 1000)

    let store = TestStore(
      initialState: State(
        paymentState: .init(
          webViewUrl: Register.fallbackURL,
          themeColor: Register.fallbackThemeColor,
          cart: .mock
        ))
    ) {
      Feature()
    } withDependencies: {
      $0.date.now = date
    }

    await store.send(.terminalEvent(.success(.updateCart(cart: .mock)))) {
      $0.regState.isConnected = true
      $0.regState.lastEvent = date

      $0.paymentState?.cart = .mock
      $0.paymentState?.alert = nil
    }
  }

  func testTerminalProcessPayment() async throws {
    let noOrderIdExpectation = XCTestExpectation(description: "Checkout params with no orderID")
    let date = Date(timeIntervalSince1970: 1000)

    let store = TestStore(
      initialState: State(
        paymentState: .init(
          webViewUrl: Register.fallbackURL,
          themeColor: Register.fallbackThemeColor,
          cart: .mock
        ))
    ) {
      Feature()
    } withDependencies: {
      $0.date.now = date
      $0.uuid = UUIDGenerator.incrementing
      $0.square.checkout = { params in
        XCTAssertNil(params.orderID)
        XCTAssertEqual(params.idempotencyKey, "00000000-0000-0000-0000-000000000000")
        XCTAssertEqual(params.totalMoney as! Money, Money(amount: 6000, currency: .USD))
        XCTAssertEqual(params.referenceID, "MOCK-REF1")
        XCTAssertEqual(params.note, "MOCK-NOTE")
        noOrderIdExpectation.fulfill()
        return .finished
      }
    }

    await store.send(
      .terminalEvent(
        .success(
          .processPayment(
            orderId: nil,
            total: 6000,
            note: "MOCK-NOTE",
            reference: "MOCK-REF1")
        ))
    ) {
      $0.regState.isConnected = true
      $0.regState.lastEvent = date
    }

    let someOrderIdExpectation = XCTestExpectation(description: "Checkout params with orderID")
    store.dependencies.square.checkout = { params in
      XCTAssertEqual(params.orderID, "MOCK-ORDERID")
      XCTAssertEqual(params.idempotencyKey, "00000000-0000-0000-0000-000000000001")
      XCTAssertEqual(params.totalMoney as! Money, Money(amount: 6000, currency: .USD))
      XCTAssertEqual(params.referenceID, "MOCK-REF2")
      XCTAssertNil(params.note)
      someOrderIdExpectation.fulfill()
      return .finished
    }

    await store.send(
      .terminalEvent(
        .success(
          .processPayment(
            orderId: "MOCK-ORDERID",
            total: 6000,
            note: "MOCK-NOTE",
            reference: "MOCK-REF2")
        ))
    )

    await fulfillment(of: [noOrderIdExpectation, someOrderIdExpectation], timeout: 1)
  }

  func testUpdateSquareToken() async throws {
    let expectation = XCTestExpectation()
    expectation.expectedFulfillmentCount = 2

    let date = Date(timeIntervalSince1970: 1000)

    let store = TestStore(
      initialState: .init(config: .mock, squareSetupState: .init(config: .mock))
    ) {
      Feature()
    } withDependencies: {
      $0.date.now = date
      $0.config.save = { updatedConfig in
        XCTAssertEqual(updatedConfig, .mock)
        expectation.fulfill()
      }
      $0.square.wasInitialized = { true }
      $0.square.authorize = { _, _ in
        expectation.fulfill()
      }
      $0.square.authorizedLocation = { .mock }
    }

    await store.send(
      .terminalEvent(
        .success(
          .updateToken(
            accessToken: "MOCK-ACCESS-TOKEN"
          )))
    ) {
      $0.regState.isConnected = true
      $0.regState.lastEvent = date
    }

    await store.receive(.squareSetupAction(.authorized)) {
      $0.squareSetupState?.hasAuthorizedSquare = true
      $0.regState.squareIsReady = true
      $0.squareSetupState?.squareAuthorizedLocation = .mock
    }

    await fulfillment(of: [expectation], timeout: 1)
  }

  private func standardAlertState(title: String, message: String) -> AlertState<
    Feature.Action.Alert
  > {
    return AlertState {
      TextState(title)
    } actions: {
      ButtonState(action: .dismiss) {
        TextState("OK")
      }
    } message: {
      TextState(message)
    }
  }
}
