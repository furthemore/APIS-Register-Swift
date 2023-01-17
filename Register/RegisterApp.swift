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
      ContentView(
        store: Store(
          initialState: .init(),
          reducer: RegFeature()
        ))
    }
  }
}
