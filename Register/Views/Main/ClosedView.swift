//
//  ClosedView.swift
//  Register
//

import SwiftUI

struct ClosedView: View {
  @Environment(\.dismiss) var dismiss

  var dateFormatter: DateFormatter {
    let dateFormatter = DateFormatter()
    dateFormatter.dateFormat = "hh:mm a"
    return dateFormatter
  }

  var body: some View {
    VStack {
      Text("Closed")
        .modifier(FitToWidth())
      Text("Next Register, Please")
        .modifier(FitToWidth())
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .overlay(alignment: .bottom) {
      CurrentTimeView()
        .onTapGesture(count: 5) {
          dismiss()
        }
    }
    .padding()
    .foregroundColor(.white)
    .bold()
    .background(Register.themeColor)
    .statusBar(hidden: true)
  }
}

struct FitToWidth: ViewModifier {
  func body(content: Content) -> some View {
    content
      .font(.system(size: 1000))
      .lineLimit(1)
      .minimumScaleFactor(0.005)
  }
}

struct ClosedView_Previews: PreviewProvider {
  static var previews: some View {
    ClosedView()
  }
}
