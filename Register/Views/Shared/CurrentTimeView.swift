//
//  CurrentTimeView.swift
//  Register
//

import SwiftUI

struct CurrentTimeView: View {
  var font: Font = .title

  @State private var currentTime = dateFormatter.string(from: Date())
  private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

  private static var dateFormatter: DateFormatter {
    let dateFormatter = DateFormatter()
    dateFormatter.dateFormat = "h:mm a"
    return dateFormatter
  }

  var body: some View {
    Text(currentTime)
      .font(font)
      .monospacedDigit()
      .textSelection(.disabled)
      .contentTransition(.numericText())
      .onReceive(timer) { _ in
        withAnimation {
          self.currentTime = Self.dateFormatter.string(from: Date())
        }
      }
  }
}

struct CurrentTimeView_Previews: PreviewProvider {
  static var previews: some View {
    CurrentTimeView()
  }
}
