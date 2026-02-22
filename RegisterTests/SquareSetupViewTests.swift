//
//  SquareSetupViewTests.swift
//  RegisterTests
//

import ComposableArchitecture
import XCTest

@testable import Register

@MainActor
final class SquareSetupViewTests: XCTestCase {
  private typealias Feature = SquareSetupFeature
  private typealias State = Feature.State

  func testAppearingChecksPermissions() async throws {
    let store = TestStore(initialState: State(config: .mock)) {
      Feature()
    } withDependencies: {
      $0.square.isAuthorized = { true }
      $0.square.authorizedLocation = { .mock }

      $0.avAudioSession.recordPermission = { .granted }

      $0.bluetoothManager.authorization = { .denied }
      $0.bluetoothManager.delegate = {
        AsyncStream { continuation in
          continuation.yield(.didChangeAuthorization(.allowedAlways))
          continuation.finish()
        }
      }

      $0.locationManager.delegate = {
        AsyncStream { continuation in
          continuation.yield(.didChangeAuthorization(.authorizedAlways))
          continuation.finish()
        }
      }
    }

    await store.send(.appeared) {
      $0.hasAuthorizedSquare = true
      $0.recordPermission = .granted
      $0.bluetoothAuthorizationStatus = .denied
      $0.squareAuthorizedLocation = .mock
    }

    await store.receive(.locationManager(.didChangeAuthorization(.authorizedAlways))) {
      $0.locationAuthorizationStatus = .authorizedAlways
    }

    await store.receive(.bluetoothManager(.didChangeAuthorization(.allowedAlways))) {
      $0.bluetoothAuthorizationStatus = .allowedAlways
    }
  }

  func testRequestingLocation() async throws {
    let expectation = XCTestExpectation()

    let store = TestStore(initialState: State(config: .mock)) {
      Feature()
    } withDependencies: {
      $0.locationManager.requestWhenInUseAuthorization = {
        expectation.fulfill()
      }
    }

    await store.send(.requestLocation)

    await fulfillment(of: [expectation], timeout: 1)
  }

  func testRequestingMicrophone() async throws {
    let store = TestStore(initialState: State(config: .mock)) {
      Feature()
    } withDependencies: {
      $0.avAudioSession.requestRecordPermission = {
        .run { send in
          await send(.granted)
        }
      }
    }

    await store.send(.requestRecordPermission)

    await store.receive(.gotRecordPermission(.granted)) {
      $0.recordPermission = .granted
    }
  }

  func testRequestSquareToken() async throws {
    let expectation = XCTestExpectation()

    let store = TestStore(initialState: State(config: .mock)) {
      Feature()
    } withDependencies: {
      $0.apis.requestSquareToken = { _ in expectation.fulfill() }
    }

    await store.send(.getAuthorizationCode) {
      $0.isAuthorizingSquare = true
    }

    await fulfillment(of: [expectation], timeout: 1)
  }

  func testRemoveAuthorization() async throws {
    let expectation = XCTestExpectation()

    let store = TestStore(initialState: State(config: .mock)) {
      Feature()
    } withDependencies: {
      $0.square.deauthorize = { expectation.fulfill() }
    }

    await store.send(.removeAuthorization) {
      $0.isAuthorizingSquare = true
    }

    await store.receive(.didRemoveAuthorization) {
      $0.isAuthorizingSquare = false
      $0.squareAuthorizedLocation = nil
    }

    await fulfillment(of: [expectation], timeout: 1)
  }
}
