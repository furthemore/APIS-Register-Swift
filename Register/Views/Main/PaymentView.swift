//
//  PaymentView.swift
//  Register
//

import ComposableArchitecture
import SwiftUI
import WebKit

struct PaymentFeature: ReducerProtocol {
  struct State: Equatable {
    var webViewURL: URL
    var cart: TerminalCart?
    var currentTransactionReference = ""

    var alert: AlertState<Action>? = nil
  }

  enum Action: Equatable {
    case dismissAlert
  }

  func reduce(into state: inout State, action: Action) -> EffectTask<Action> {
    switch action {
    case .dismissAlert:
      state.alert = nil
      return .none
    }
  }
}

struct PaymentView: View {
  @Environment(\.dismiss) var dismiss
  @Environment(\.horizontalSizeClass) var horizontalSizeClass

  let store: StoreOf<PaymentFeature>

  var body: some View {
    WithViewStore(store) { viewStore in
      content(viewStore)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Register.themeColor)
        .statusBarHidden()
        .alert(
          store.scope(state: \.alert),
          dismiss: PaymentFeature.Action.dismissAlert
        )
    }
  }

  @ViewBuilder
  func content(_ viewStore: ViewStoreOf<PaymentFeature>) -> some View {
    if horizontalSizeClass == .compact {
      payment(viewStore)
    } else {
      TwoColumnLayout(mainColumnSize: 3 / 5, minimumSecondaryWidth: 300) {
        WebView(url: viewStore.webViewURL)
          .ignoresSafeArea()

        payment(viewStore)
      }
    }
  }

  @ViewBuilder
  func payment(_ viewStore: ViewStoreOf<PaymentFeature>) -> some View {
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
      } else {
        Spacer()
      }
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
      store: Store(
        initialState: .init(webViewURL: Register.fallbackURL),
        reducer: PaymentFeature()
      ))
  }
}
