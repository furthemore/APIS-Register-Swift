//
//  PaymentLineItem.swift
//  Register
//

import SwiftUI

struct PaymentLineBadge: View {
  var name: String
  var badgeName: String
  var levelName: String
  var price: Decimal
  
  var body: some View {
    HStack {
      VStack(alignment: .leading) {
        Text(name)
        Text(levelName + " Registration")
        
        Text("\"\(badgeName)\"")
          .bold()
      }
      
      Spacer()
      
      Text(price, format: .currency(code: "USD"))
    }
  }
}

struct PaymentBadgeLine_Previews: PreviewProvider {
  static var previews: some View {
    PaymentLineBadge(
      name: "First Last",
      badgeName: "Fancy Name",
      levelName: "Sponsor",
      price: 175
    )
  }
}
