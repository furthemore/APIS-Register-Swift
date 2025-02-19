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

  func testClearConfig() async throws {
    let expectation = XCTestExpectation()

    let store = TestStore(initialState: State(isPresentingScanner: true)) {
      Feature()
    } withDependencies: {
      $0.config.clear = { expectation.fulfill() }
    }

    await store.send(.clear)

    await fulfillment(of: [expectation], timeout: 1)
  }
}
