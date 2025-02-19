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
        alert: AlertState { TextState("test") },
        webViewUrl: Register.fallbackURL,
        themeColor: Register.fallbackThemeColor
      )
    ) {
      PaymentFeature()
    }

    XCTAssertNotNil(store.state.alert)

    await store.send(.alert(.dismiss)) {
      $0.alert = nil
    }
  }

}
