//
//  RegisterApp.swift
//  Register
//

import ComposableArchitecture
import SquareReaderSDK
import SwiftUI

@main
struct RegisterApp: App {
  @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

  var body: some Scene {
    WindowGroup {
      RegSetupView(
        store: Store(
          initialState: .init(),
          reducer: RegSetupFeature()
        ))
    }
  }
}

class AppDelegate: NSObject, UIApplicationDelegate {
  func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
  ) -> Bool {
    SQRDReaderSDK.initialize(applicationLaunchOptions: launchOptions)

    return true
  }
}
