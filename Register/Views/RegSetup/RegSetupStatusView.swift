//
//  RegSetupStatusView.swift
//  Register
//

import SwiftUI

struct RegSetupStatusView: View {
  @Binding var terminalName: String?
  @Binding var isConnecting: Bool
  @Binding var isConnected: Bool
  @Binding var lastEvent: Date?
  @Binding var canConnect: Bool

  var connectToggle: (() -> Void)? = nil

  var body: some View {
    Section("Status") {
      HStack {
        Text("Terminal Name")

        Spacer()

        if let terminalName = terminalName {
          Text(terminalName)
        } else {
          Text("unregistered").foregroundStyle(.secondary)
        }
      }

      Toggle(
        isOn: Binding(
          get: { isConnected },
          set: { _ in connectToggle?() })
      ) {
        HStack {
          Text("MQTT Connected")

          if isConnecting {
            ProgressView()
          }
        }
      }.disabled(isConnecting || !canConnect)

      HStack {
        Text("Last MQTT Event")

        Spacer()

        if let lastUpdated = lastEvent {
          Text(lastUpdated, format: .dateTime)
        } else {
          Text("never").foregroundStyle(.secondary)
        }
      }
    }
  }
}

#Preview("Disconnected") {
  Form {
    RegSetupStatusView(
      terminalName: .constant(nil),
      isConnecting: .constant(false),
      isConnected: .constant(false),
      lastEvent: .constant(nil),
      canConnect: .constant(false)
    )
  }
}

#Preview("Connected") {
  Form {
    RegSetupStatusView(
      terminalName: .constant("Test Terminal"),
      isConnecting: .constant(false),
      isConnected: .constant(true),
      lastEvent: .constant(Date(timeIntervalSince1970: 1_673_932_324)),
      canConnect: .constant(true)
    )
  }
}
