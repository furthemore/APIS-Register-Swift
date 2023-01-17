//
//  PaymentView.swift
//  Register
//

import SwiftUI
import WebKit
import ComposableArchitecture

struct PayFeature: ReducerProtocol {
  struct State: Equatable {
    var webViewURL: URL = URL(string: "https://www.google.com")!

    var cart: TerminalCart? = nil
  }
  
  enum Action: Equatable {
    case updateCart(TerminalCart)
  }
  
  func reduce(into state: inout State, action: Action) -> EffectTask<Action> {
    switch action {
    case .updateCart(let cart):
      state.cart = cart
      return .none
    }
  }
}

struct PaymentView: View {
  @Environment(\.dismiss) var dismiss
  
  let store: StoreOf<PayFeature>
  
  var body: some View {
    WithViewStore(store) { viewStore in
      TwoColumnLayout(mainColumnSize: 3/5, minimumSecondaryWidth: 300) {
        WebView(url: viewStore.webViewURL)
          .ignoresSafeArea()
          
        VStack(spacing: 0) {
          CurrentTimeView()
            .foregroundColor(.white)
            .onTapGesture(count: 5) {
              dismiss()
            }
            .padding([.top], 16)
            .frame(maxWidth: .infinity)
          
          if let cart = viewStore.cart {
            List {
              paymentLineItems(cart)
            }
              .scrollContentBackground(.hidden)
          }
        }
      }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(red: 0, green: 153 / 255, blue: 204 / 255))
        .statusBarHidden()
    }
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
  func badgeItems(_ cart: TerminalCart) -> some View{
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
    PaymentView(store: Store(
      initialState: PayFeature.State(),
      reducer: PayFeature()
    ))
  }
}
