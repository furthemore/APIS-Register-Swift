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
    let store = TestStore(initialState: State(), reducer: Feature()) {
      $0.square.isAuthorized = { true }
      $0.square.authorizedLocation = { .mock }

      $0.avAudioSession.recordPermission = { .granted }

      $0.locationManager.delegate = {
        return .task {
          return LocationAction.didChangeAuthorization(.authorizedAlways)
        }
      }
    }

    await store.send(.appeared) {
      $0.recordPermission = .granted
      $0.authorizedLocation = .mock
      $0.isAuthorized = true
    }

    await store.receive(.locationManager(.didChangeAuthorization(.authorizedAlways))) {
      $0.locationAuthorizationStatus = .authorizedAlways
    }
  }

  func testRequestingLocation() async throws {
    let expectation = XCTestExpectation()

    let store = TestStore(initialState: State(), reducer: Feature()) {
      $0.locationManager.requestWhenInUseAuthorization = {
        expectation.fulfill()
      }
    }

    await store.send(.requestLocation)

    wait(for: [expectation], timeout: 1)
  }

  func testRequestingMicrophone() async throws {
    let store = TestStore(initialState: State(), reducer: Feature()) {
      $0.avAudioSession.requestRecordPermission = { .task { .granted } }
    }

    await store.send(.requestRecordPermission)

    await store.receive(.recordPermission(.granted)) {
      $0.recordPermission = .granted
    }
  }

  func testFetchAuthCode() async throws {
    let squareToken = "TEST-SQUARE-TOKEN"

    let store = TestStore(initialState: State(), reducer: Feature()) {
      $0.apis.getSquareToken = { _ in squareToken }
      $0.square.authorize = { token in
        XCTAssertEqual(squareToken, token)
        return .mock
      }
    }

    await store.send(.getAuthorizationCode) {
      $0.isFetchingAuthCode = true
    }

    await store.receive(.fetchedAuthToken(.mock)) {
      $0.isFetchingAuthCode = false
      $0.isAuthorized = true
      $0.authorizedLocation = .mock
    }
  }

  func testOpeningSettings() async throws {
    let store = TestStore(initialState: State(), reducer: Feature())

    await store.send(.setPairingDevice(false))

    store.dependencies.square.openSettings = {
      .task { .presented(.success(true)) }
    }

    await store.send(.setPairingDevice(true))

    await store.receive(.squareSettingsAction(.presented(.success(true))))
  }

  func testRemoveAuthorization() async throws {
    let expectation = XCTestExpectation()

    let store = TestStore(initialState: State(), reducer: Feature()) {
      $0.square.deauthorize = { expectation.fulfill() }
    }

    await store.send(.removeAuthorization) {
      $0.isFetchingAuthCode = true
    }

    await store.receive(.didRemoveAuthorization) {
      $0.isFetchingAuthCode = false
      $0.isAuthorized = false
      $0.authorizedLocation = nil
    }

    wait(for: [expectation], timeout: 1)
  }
}
