//
//  PaymentLineItem.swift
//  Register
//

import SwiftUI

struct PaymentLineBadgeView: View {
  let name: String
  let badgeName: String
  let levelName: String
  let price: Decimal
  let discountedPrice: Decimal?

  var isDiscounted: Bool {
    guard let discountedPrice = discountedPrice else {
      return false
    }

    return discountedPrice != price
  }

  var body: some View {
    HStack {
      VStack(alignment: .leading) {
        Text(levelName + " Registration").bold()
        Text(name)
        Text(badgeName)
      }

      Spacer()

      VStack(alignment: .trailing) {
        Text(price, format: .currency(code: "USD"))
          .strikethrough(isDiscounted)
          .foregroundColor(isDiscounted ? .secondary : .primary)

        if let discountedPrice = discountedPrice, isDiscounted {
          Text(discountedPrice, format: .currency(code: "USD"))
        }
      }
    }
  }
}

#Preview("Standard Badge", traits: .sizeThatFitsLayout) {
  PaymentLineBadgeView(
    name: "First Last",
    badgeName: "Badge Name",
    levelName: "Sponsor",
    price: 175,
    discountedPrice: nil
  )
}

#Preview("Discounted Badge", traits: .sizeThatFitsLayout) {
  PaymentLineBadgeView(
    name: "First Last",
    badgeName: "Badge Name",
    levelName: "Sponsor",
    price: 175,
    discountedPrice: 150
  )
}
