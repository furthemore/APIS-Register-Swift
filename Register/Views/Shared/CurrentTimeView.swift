//
//  CurrentTimeView.swift
//  Register
//

import SwiftUI

struct CurrentTimeView: View {
  var font: Font = .title

  var body: some View {
    TimelineView(.everyMinute) { context in
      HStack(spacing: 0) {
        Text(context.date, format: .dateTime.day().month().weekday())
          .animation(.default, value: context.date)
        Text("・")
        Text(context.date, format: .dateTime.hour().minute())
          .animation(.default, value: context.date)

      }
    }
    .font(font)
    .monospacedDigit()
    .textSelection(.disabled)
    .contentTransition(.numericText())
  }
}

#Preview {
  CurrentTimeView()
}
