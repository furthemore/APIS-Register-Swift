//
//  NameValueView.swift
//  Register
//

import SwiftUI

struct NameValueView: View {
  let name: String
  let value: String

  var body: some View {
    HStack {
      Text(name)
      Spacer()
      Text(value).foregroundColor(.secondary)
    }
    .contextMenu {
      Button("Copy Value", systemImage: "clipboard") {
        UIPasteboard.general.string = value
      }
    }
  }
}

#Preview(traits: .sizeThatFitsLayout) {
  NameValueView(name: "Name", value: "Value")
}
