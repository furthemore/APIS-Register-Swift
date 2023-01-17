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

struct PaymentBasicLine_Previews: PreviewProvider {
  static var previews: some View {
    PaymentLineBasicView(lineName: "Line Item", price: 20)
  }
}
