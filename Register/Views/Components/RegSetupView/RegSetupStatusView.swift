//
//  RegSetupStatusView.swift
//  Register
//

import SwiftUI

struct RegSetupStatusView: View {
  @Binding var isConnected: Bool
  @Binding var lastUpdated: Date?

  var body: some View {
    Section("Status") {
      Toggle(isOn: $isConnected) {
        Text("Connected")
      }

      HStack {
        Text("Last Event")

        Spacer()

        if let lastUpdated = lastUpdated {
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
        lastUpdated: .constant(nil)
      )
    }
    .previewLayout(.fixed(width: 400, height: 200))
    .previewDisplayName("Disconnected")

    Form {
      RegSetupStatusView(
        isConnected: .constant(true),
        lastUpdated: .constant(Date(timeIntervalSince1970: 1_673_932_324))
      )
    }
    .previewLayout(.fixed(width: 400, height: 200))
    .previewDisplayName("Connected")
  }
}
