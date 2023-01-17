//
//  PaymentLineBasic.swift
//  Register
//

import SwiftUI

struct PaymentLineBasic: View {
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

struct PaymentBasicLine_Previews: PreviewProvider {
  static var previews: some View {
    PaymentLineBasic(lineName: "Line Item", price: 20)
  }
}
