//
//  RegisterApp.swift
//  Register
//

import Combine
import ComposableArchitecture
import SwiftUI

@main
struct RegisterApp: App {
  @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

  let windowEvents = PassthroughSubject<WindowEvent, Never>()

  var body: some Scene {
    WindowGroup {
      if !_XCTIsTesting {
        RegSetupView(
          store: Store(initialState: .init()) {
            RegSetupFeature()
          },
          windowEvents: windowEvents
        )
      }
    }
    .commands {
      CommandMenu("Actions") {
        Button("Setup", systemImage: "gear") {
          windowEvents.send(.setup)
        }
        .keyboardShortcut("T")

        Button("Close", systemImage: "xmark") {
          windowEvents.send(.close)
        }
        .keyboardShortcut("E")

        Button("Ready", systemImage: "cart") {
          windowEvents.send(.open)
        }
        .keyboardShortcut("D")
      }
    }
  }
}

class AppDelegate: NSObject, UIApplicationDelegate {
  @Dependency(\.square) var square

  func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
  ) -> Bool {
    square.initialize(launchOptions)

    EAAccessoryManager.shared().registerForLocalNotifications()

    return true
  }
}
