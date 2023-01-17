//
//  RegisterApp.swift
//  Register
//

import SwiftUI
import ComposableArchitecture

@main
struct RegisterApp: App {
  var body: some Scene {
    WindowGroup {
      ContentView(store: Store(
        initialState: .init(),
        reducer: RegFeature()
      ))
    }
  }
}
