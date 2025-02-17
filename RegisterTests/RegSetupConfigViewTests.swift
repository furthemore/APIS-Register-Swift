//
//  RegSetupConfigViewTests.swift
//  RegisterTests
//

import ComposableArchitecture
import XCTest

@testable import Register

@MainActor
final class RegSetupConfigViewTests: XCTestCase {
  private typealias Feature = RegSetupConfigFeature
  private typealias State = Feature.State

  func testShowScanner() async throws {
    let store = TestStore(initialState: State()) {
      Feature()
    }

    await store.send(.showScanner(true)) {
      $0.isPresentingScanner = true
    }

    await store.send(.scannerResult(.success(""))) {
      $0.isPresentingScanner = false
    }
  }

  func testRegisterTerminal() async throws {
    let expectation = XCTestExpectation()

    let store = TestStore(initialState: State()) {
      Feature()
    } withDependencies: {
      $0.apis.registerTerminal = { _ in .mock }
      $0.config.save = { config in
        expectation.fulfill()
        XCTAssertEqual(config, .mock)
      }
    }

    await store.send(.registerTerminal) {
      $0.isLoading = true
    }

    await store.receive(.registered(.success(.mock))) {
      $0.isLoading = false
    }

    await fulfillment(of: [expectation], timeout: 1)
  }

  func testClearConfig() async throws {
    let expectation = XCTestExpectation()

    let store = TestStore(initialState: State(canUpdateConfig: false, isPresentingScanner: true)) {
      Feature()
    } withDependencies: {
      $0.config.clear = { expectation.fulfill() }
    }

    await store.send(.clear) {
      $0 = .init()
    }

    await fulfillment(of: [expectation], timeout: 1)
  }

  func testIsRegistrationDisabled() {
    var state = State()
    XCTAssertTrue(state.isRegistrationDisabled)

    state.registerRequest = .mock
    XCTAssertFalse(state.isRegistrationDisabled)

    state.isLoading = true
    XCTAssertTrue(state.isRegistrationDisabled)
  }
}
