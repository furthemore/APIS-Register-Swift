//
//  CurrentTimeView.swift
//  Register
//

import SwiftUI

struct CurrentTimeView: View {
  var font: Font = .monospaced(.title)()
  
  @State private var currentTime = dateFormatter.string(from: Date())
  private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
  
  private static var dateFormatter: DateFormatter {
    let dateFormatter = DateFormatter()
    dateFormatter.dateFormat = "hh:mm a"
    return dateFormatter
  }
  
  var body: some View {
    Text(currentTime)
      .font(font)
      .onReceive(timer) { _ in
        self.currentTime = Self.dateFormatter.string(from: Date())
      }
  }
}

struct CurrentTimeView_Previews: PreviewProvider {
  static var previews: some View {
    CurrentTimeView()
  }
}
