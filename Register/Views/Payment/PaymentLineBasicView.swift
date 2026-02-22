//
//  PaymentLineBasic.swift
//  Register
//

import SwiftUI

struct PaymentLineBasicView: View {
  var lineName: String
  var price: Decimal

  var body: some View {
    HStack {
      Text(lineName)
      Spacer()
      Text(price, format: .currency(code: "USD"))
    }
  }
}

#Preview("Line Items", traits: .sizeThatFitsLayout) {
  List {
    PaymentLineBasicView(lineName: "Line Item", price: 20)
    PaymentLineBasicView(lineName: "Another Item", price: 12.50)
  }
}
