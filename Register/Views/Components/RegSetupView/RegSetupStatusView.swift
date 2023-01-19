//
//  RegSetupStatusView.swift
//  Register
//

import SwiftUI

struct RegSetupStatusView: View {
  @Binding var isConnected: Bool
  @Binding var lastEvent: Date?

  var body: some View {
    Section("Status") {
      Toggle(isOn: $isConnected) {
        Text("Connected")
      }

      HStack {
        Text("Last Event")

        Spacer()

        if let lastUpdated = lastEvent {
          Text(lastUpdated, format: .dateTime)
        } else {
          Text("never")
        }
      }
    }
    .disabled(true)
  }
}

struct RegSetupStatusView_Previews: PreviewProvider {
  static var previews: some View {
    Form {
      RegSetupStatusView(
        isConnected: .constant(false),
        lastEvent: .constant(nil)
      )
    }
    .previewLayout(.fixed(width: 400, height: 200))
    .previewDisplayName("Disconnected")

    Form {
      RegSetupStatusView(
        isConnected: .constant(true),
        lastEvent: .constant(Date(timeIntervalSince1970: 1_673_932_324))
      )
    }
    .previewLayout(.fixed(width: 400, height: 200))
    .previewDisplayName("Connected")
  }
}
