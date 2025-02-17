//
//  PaymentView.swift
//  Register
//

import ComposableArchitecture
import SwiftUI
import WebKit

@Reducer
struct PaymentFeature {
  @ObservableState
  struct State: Equatable {
    @Presents var alert: AlertState<Action.Alert>?

    var webViewURL: URL
    var themeColor: Color

    var cart: TerminalCart?
    var currentTransactionReference = ""
  }

  enum Action: Equatable {
    case alert(PresentationAction<Alert>)
    case dismissView

    enum Alert: Equatable {}
  }

  var body: some Reducer<State, Action> {
    Reduce { state, action in
      switch action {
      case .alert:
        return .none
      case .dismissView:
        return .none
      }
    }
    .ifLet(\.$alert, action: \.alert)
  }
}

struct PaymentView: View {
  @Environment(\.horizontalSizeClass) var horizontalSizeClass

  @Bindable var store: StoreOf<PaymentFeature>

  var body: some View {
    content
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .background(store.themeColor)
      .statusBarHidden()
      .preferredColorScheme(.light)
      .alert(
        store: self.store.scope(state: \.$alert, action: \.alert)
      )
  }

  @ViewBuilder
  var content: some View {
    if horizontalSizeClass == .compact {
      payment
    } else {
      TwoColumnLayout(mainColumnSize: 3 / 5, minimumSecondaryWidth: 300) {
        WebView(url: store.webViewURL)
          .ignoresSafeArea()

        payment
      }
    }
  }

  @ViewBuilder
  var payment: some View {
    VStack(spacing: 0) {
      CurrentTimeView()
        .onTapGesture(count: 5) {
          store.send(.dismissView)
        }
        .foregroundColor(store.themeColor.adaptedTextColor)
        .padding()
        .frame(maxWidth: .infinity)

      if let cart = store.cart {
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
      if let totalDiscount = cart.totalDiscount, totalDiscount > 0 {
        PaymentLineBasicView(lineName: "Subtotal", price: cart.total)
        PaymentLineBasicView(lineName: "Discounts", price: -totalDiscount)
      }
      
      if cart.paid > 0 {
        PaymentLineBasicView(lineName: "Paid", price: cart.paid)
      }

      PaymentLineBasicView(
        lineName: "Total",
        price: cart.total - (cart.totalDiscount ?? 0) - cart.paid
      )
      .bold()
    }
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
          levelName: badge.effectiveLevel.name,
          price: badge.effectiveLevel.price,
          discountedPrice: badge.discountedPrice
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
        initialState: .init(
          webViewURL: Register.fallbackURL,
          themeColor: Register.fallbackThemeColor
        )
      ) {
        PaymentFeature()
      }
    )
  }
}
