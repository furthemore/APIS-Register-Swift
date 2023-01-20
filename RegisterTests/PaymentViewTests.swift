//
//  PaymentViewTests.swift
//  RegisterTests
//

import ComposableArchitecture
import XCTest

@testable import Register

@MainActor
final class PaymentViewTests: XCTestCase {

  func testDismissAlert() async throws {
    let store = TestStore(
      initialState: PaymentFeature.State(
        webViewURL: Register.fallbackURL,
        alert: .init(title: TextState("test"))
      ),
      reducer: PaymentFeature()
    )

    XCTAssertNotNil(store.state.alert)

    await store.send(.dismissAlert) {
      $0.alert = nil
    }
  }

}
