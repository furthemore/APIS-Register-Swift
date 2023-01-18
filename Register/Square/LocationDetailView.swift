//
//  LocationDetailView.swift
//  Register
//

import SwiftUI

struct LocationDetailView: View {
  let name: String
  let value: String

  var body: some View {
    HStack {
      Text(name)
      Spacer()
      Text(value).foregroundColor(.secondary)
    }
    .contextMenu {
      Button {
        UIPasteboard.general.string = value
      } label: {
        Label("Copy Value", systemImage: "clipboard")
      }
    }
  }
}

struct LocationDetailView_Previews: PreviewProvider {
  static var previews: some View {
    LocationDetailView(name: "Name", value: "Value")
  }
}
