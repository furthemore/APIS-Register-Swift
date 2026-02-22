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
      $0.square.wasInitialized = { true }
      $0.square.isAuthorized = { true }
      $0.config.load = { .mock }
      $0.apis.setUpEvents = { _ in .none }
      $0.zebra.events = { AsyncStream.finished }
    }

    await store.send(.appeared) {
      $0.regState.squareIsReady = true
      $0.regState.squareWasInitialized = true
    }

    await store.receive(\.configLoaded.success) {
      $0.regState.needsConfigLoad = false
      $0.config = .mock
    }
  }

  func testMissingConfigIsLoaded() async throws {
    let store = TestStore(initialState: State()) {
      Feature()
    } withDependencies: {
      $0.square.wasInitialized = { true }
      $0.square.isAuthorized = { true }
      $0.config.load = { nil }
      $0.apis.setUpEvents = { _ in .none }
      $0.zebra.events = { AsyncStream.finished }
    }

    await store.send(.appeared) {
      $0.regState.squareWasInitialized = true
      $0.regState.squareIsReady = true
    }

    await store.receive(\.configLoaded.failure) {
      $0.regState.needsConfigLoad = false
      $0.config = nil
    }
  }

  func testSetMode() async throws {
    let store = TestStore(
      initialState: State(
        config: .mock,
        regState: .init(connectionState: .connected)
      )
    ) {
      Feature()
    }
    store.exhaustivity = .off(showSkippedAssertions: true)

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
    expectation.expectedFulfillmentCount = 3

    let store = TestStore(
      initialState: State(
        regState: .init(connectionState: .connected),
        configState: .init()
      )
    ) {
      Feature()
    } withDependencies: {
      $0.apis.disconnectEvents = { expectation.fulfill() }
      $0.config.clear = { expectation.fulfill() }
      $0.square.deauthorize = { expectation.fulfill() }
    }

    await store.send(.configAction(.clear)) {
      $0.regState.connectionState = .disconnected
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
    let expectation = XCTestExpectation()
    expectation.expectedFulfillmentCount = 2

    let store = TestStore(
      initialState: State(
        config: .mock,
        paymentState: .init()
      )
    ) {
      Feature()
    } withDependencies: {
      $0.apis.notifyFrontend = { _, _ in }
      $0.apis.squareTransactionCompleted = { _, tx in
        XCTAssertEqual(tx, .mock)
        expectation.fulfill()
        return false
      }
    }

    await store.send(.squareCheckoutAction(.finished(.success(.mock))))

    await store.receive(\.squareTransactionCompleted) {
      $0.paymentState?.alert = AlertState {
        TextState("Error")
      } message: {
        TextState("Payment was not successful.")
      }
    }

    store.dependencies.apis.squareTransactionCompleted = { _, tx in
      XCTAssertEqual(tx, .mock)
      expectation.fulfill()
      return true
    }

    await store.send(.squareCheckoutAction(.finished(.success(.mock))))

    await store.receive(\.squareTransactionCompleted)

    await fulfillment(of: [expectation], timeout: 1)
  }

  func testEventConnections() async throws {
    let expectation = XCTestExpectation()

    let disconnectedStore = TestStore(initialState: State()) {
      Feature()
    }

    await disconnectedStore.send(.scenePhaseChanged(.active))

    let connectedStore = TestStore(
      initialState: State(
        config: .mock,
        regState: .init(connectionState: .connected)
      )
    ) {
      Feature()
    } withDependencies: {
      $0.apis.setUpEvents = { _ in .none }
      $0.apis.connectEvents = {
        expectation.fulfill()
      }
    }

    await connectedStore.send(.scenePhaseChanged(.inactive))

    await connectedStore.send(.scenePhaseChanged(.active)) {
      $0.regState.connectionState = .connecting
    }

    await connectedStore.receive(\.terminalEvent.success) {
      $0.regState.connectionState = .connected
    }

    await fulfillment(of: [expectation], timeout: 1)
  }

  func testTerminalOpen() async throws {
    let date = Date(timeIntervalSince1970: 1000)

    let storeNoSquare = TestStore(
      initialState: State(paymentState: .init())
    ) {
      Feature()
    } withDependencies: {
      $0.date.now = date
    }

    await storeNoSquare.send(.terminalEvent(.success(.state(.open)))) {
      $0.regState.lastEvent = date

      $0.setAlert(title: "Opening Failed", message: "Terminal has not been fully configured.")
    }

    let storeWithSquare = TestStore(
      initialState: State(
        config: .mock,
        regState: .init(squareIsReady: true),
        paymentState: .init()
      )
    ) {
      Feature()
    } withDependencies: {
      $0.square.wasInitialized = { true }
      $0.date.now = date
    }
    storeWithSquare.exhaustivity = .off(showSkippedAssertions: true)

    await storeWithSquare.send(.terminalEvent(.success(.state(.open)))) {
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

    await store.send(.terminalEvent(.success(.state(.close)))) {
      $0.regState.lastEvent = date

      $0.regState.mode = .close
    }
  }

  func testTerminalClearCart() async throws {
    let date = Date(timeIntervalSince1970: 1000)

    let store = TestStore(
      initialState: State(
        paymentState: .init(cart: .mock))
    ) {
      Feature()
    } withDependencies: {
      $0.date.now = date
    }

    await store.send(.terminalEvent(.success(.cartUpdate(.mock)))) {
      $0.regState.lastEvent = date

      $0.paymentState?.cart = .mock
      $0.paymentState?.alert = nil
    }
  }

  func testTerminalProcessPayment() async throws {
    let date = Date(timeIntervalSince1970: 1000)

    let noOrderIdExpectation = XCTestExpectation(description: "Checkout params with no orderID")
    let storeForNilOrderId = TestStore(
      initialState: State(
        paymentState: .init(cart: .mock))
    ) {
      Feature()
    } withDependencies: {
      $0.date.now = date
      $0.uuid = UUIDGenerator.incrementing
      $0.square.checkout = { params, viewController in
        XCTAssertNil(params.orderId)
        XCTAssertEqual(params.paymentAttemptId, "00000000-0000-0000-0000-000000000000")
        XCTAssertEqual(params.amountMoney, Money(amount: 6000, currency: .USD))
        XCTAssertEqual(params.referenceId, "MOCK-REF1")
        XCTAssertEqual(params.note, "MOCK-NOTE")
        noOrderIdExpectation.fulfill()
        return .finished
      }
    }

    await storeForNilOrderId.send(
      .terminalEvent(
        .success(
          .process(
            .init(
              paymentAttemptId: "00000000-0000-0000-0000-000000000000",
              orderId: nil,
              total: 6000,
              note: "MOCK-NOTE",
              reference: "MOCK-REF1"
            )
          )
        )
      )
    ) {
      $0.regState.lastEvent = date
      $0.regState.isPresentingPayment = true
    }

    let someOrderIdExpectation = XCTestExpectation(description: "Checkout params with orderID")
    let storeForOrderId = TestStore(
      initialState: State(
        paymentState: .init(cart: .mock))
    ) {
      Feature()
    } withDependencies: {
      $0.date.now = date
      $0.uuid = UUIDGenerator.incrementing
      $0.square.checkout = { params, viewController in
        XCTAssertEqual(params.orderId, "MOCK-ORDERID")
        XCTAssertEqual(params.paymentAttemptId, "00000000-0000-0000-0000-000000000001")
        XCTAssertEqual(params.amountMoney, Money(amount: 6000, currency: .USD))
        XCTAssertEqual(params.referenceId, "MOCK-REF2")
        XCTAssertNil(params.note)
        someOrderIdExpectation.fulfill()
        return .finished
      }
    }

    await storeForOrderId.send(
      .terminalEvent(
        .success(
          .process(
            .init(
              paymentAttemptId: "00000000-0000-0000-0000-000000000001",
              orderId: "MOCK-ORDERID",
              total: 6000,
              note: "MOCK-NOTE",
              reference: "MOCK-REF2"
            )
          )
        )
      )
    ) {
      $0.regState.lastEvent = date
      $0.regState.isPresentingPayment = true
    }

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
            .init(accessToken: "MOCK-ACCESS-TOKEN", refreshToken: "MOCK-REFRESH-TOKEN")
          )))
    ) {
      $0.regState.lastEvent = date
    }

    await store.receive(\.squareSetupAction) {
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
