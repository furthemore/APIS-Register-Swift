//
//  RegSetupStatusView.swift
//  Register
//

import SwiftUI

struct RegSetupStatusView: View {
  var isConnected = false
  var lastUpdated: Date? = nil

  var body: some View {
    Section("Status") {
      Toggle(isOn: .constant(isConnected)) {
        Text("Connected")
      }

      HStack {
        Text("Last Update")

        Spacer()

        if let lastUpdated = lastUpdated {
          Text(lastUpdated, format: .dateTime)
        } else {
          Text("never").bold()
        }
      }
    }
    .disabled(true)
  }
}

struct RegSetupStatusView_Previews: PreviewProvider {
  static var previews: some View {
    Form {
      RegSetupStatusView()
    }
    .previewLayout(.fixed(width: 400, height: 200))
    .previewDisplayName("Disconnected")

    Form {
      RegSetupStatusView(
        isConnected: true,
        lastUpdated: Date(timeIntervalSince1970: 1_673_932_324)
      )
    }
    .previewLayout(.fixed(width: 400, height: 200))
    .previewDisplayName("Connected")
  }
}
