//
//  RegisterApp.swift
//  Register
//

import ComposableArchitecture
import SwiftUI

@main
struct RegisterApp: App {
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
