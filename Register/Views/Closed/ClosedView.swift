//
//  ClosedView.swift
//  Register
//

import SwiftUI

struct ClosedView: View {
  @Environment(\.dismiss) var dismiss

  let themeColor: Color

  var body: some View {
    VStack {
      Spacer()

      VStack {
        Text("Closed")
          .modifier(FitToWidth())
        Text("Next Register, Please")
          .modifier(FitToWidth())
      }.bold()

      Spacer()

      CurrentTimeView()
        .onTapGesture(count: 5) {
          dismiss()
        }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .padding()
    .foregroundColor(themeColor.adaptedTextColor)
    .background(themeColor)
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
    ClosedView(themeColor: Register.fallbackThemeColor)
  }
}
