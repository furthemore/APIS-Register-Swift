//
//  PaymentView.swift
//  Register
//

import ComposableArchitecture
import SwiftUI
import WebKit

struct PaymentView: View {
  @Environment(\.dismiss) var dismiss

  @Binding var webViewURL: URL
  @Binding var cart: TerminalCart?

  var body: some View {
    TwoColumnLayout(mainColumnSize: 3 / 5, minimumSecondaryWidth: 300) {
      WebView(url: webViewURL)
        .ignoresSafeArea()

      VStack(spacing: 0) {
        CurrentTimeView()
          .foregroundColor(.white)
          .onTapGesture(count: 5) {
            dismiss()
          }
          .padding([.top], 16)
          .frame(maxWidth: .infinity)

        if let cart = cart {
          List {
            paymentLineItems(cart)
          }
          .scrollContentBackground(.hidden)
        }
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Register.themeColor)
    .statusBarHidden()
  }

  @ViewBuilder
  func paymentLineItems(_ cart: TerminalCart) -> some View {
    Section(header: Text("Badges").foregroundColor(.white)) {
      badgeItems(cart)
    }

    Section(header: Text("Donations").foregroundColor(.white)) {
      PaymentLineBasicView(lineName: "Charity Donation", price: cart.charityDonation)
      PaymentLineBasicView(lineName: "Organization Donation", price: cart.organizationDonation)
    }

    Section {
      PaymentLineBasicView(lineName: "Total", price: cart.total)
    }
    .bold()
  }

  @ViewBuilder
  func badgeItems(_ cart: TerminalCart) -> some View {
    if cart.badges.isEmpty {
      Text("No badges in cart").foregroundColor(.secondary)
    } else {
      ForEach(cart.badges) { badge in
        PaymentLineBadgeView(
          name: "\(badge.firstName) \(badge.lastName)",
          badgeName: badge.badgeName,
          levelName: badge.effectiveLevelName,
          price: badge.effectiveLevelPrice
        )
      }
    }
  }
}

struct WebView: UIViewRepresentable {
  var url: URL

  func makeUIView(context: Context) -> WKWebView {
    return WKWebView()
  }

  func updateUIView(_ webView: WKWebView, context: Context) {
    let request = URLRequest(url: url)
    webView.load(request)
  }
}

struct PaymentView_Previews: PreviewProvider {
  static var previews: some View {
    PaymentView(
      webViewURL: .constant(Register.fallbackURL),
      cart: .constant(
        .init(
          badges: .init(),
          charityDonation: 0,
          organizationDonation: 0,
          total: 0
        )
      ))
  }
}
