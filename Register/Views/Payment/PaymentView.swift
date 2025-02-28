//
//  PaymentView.swift
//  Register
//

import ComposableArchitecture
import SwiftUI
import WebKit

@Reducer
struct PaymentFeature {
  @Dependency(\.square) var square

  @ObservableState
  struct State: Equatable {
    @Presents var alert: AlertState<Action.Alert>?

    var webViewUrl: URL
    var themeColor: Color

    var cart: TerminalCart?

    var showingMockReaderUI = false
  }

  enum Action: Equatable {
    case alert(PresentationAction<Alert>)
    case dismissView
    case toggleMockReaderUI

    enum Alert: Equatable {}
  }

  var body: some Reducer<State, Action> {
    Reduce { state, action in
      switch action {
      case .alert:
        return .none
      case .dismissView:
        square.hideMockReader()
        state.showingMockReaderUI = false
        return .none
      case .toggleMockReaderUI:
        guard square.environment() == .sandbox else {
          return .none
        }

        if state.showingMockReaderUI {
          square.hideMockReader()
          state.showingMockReaderUI = false
        } else {
          do {
            try square.showMockReader()
            state.showingMockReaderUI = true
          } catch {
            state.alert = AlertState(
              title: {
                TextState("Error")
              },
              message: {
                TextState("\(error.localizedDescription)")
              })
          }
        }
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
        WebView(url: store.webViewUrl)
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
        .onLongPressGesture(perform: {
          store.send(.toggleMockReaderUI)
        })
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
    Section(
      header: Text("Badges").foregroundColor(store.themeColor.adaptedTextColor)
    ) {
      badgeItems(cart)
    }

    Section(
      header: Text("Donations").foregroundColor(store.themeColor.adaptedTextColor)
    ) {
      PaymentLineBasicView(lineName: "Charity Donation", price: cart.charityDonation)
      PaymentLineBasicView(lineName: "Organization Donation", price: cart.organizationDonation)
    }

    Section {
      if let totalDiscount = cart.totalDiscount, totalDiscount > 0 {
        PaymentLineBasicView(
          lineName: "Subtotal",
          price: cart.total + (cart.totalDiscount ?? 0)
        )
        PaymentLineBasicView(
          lineName: "Discounts",
          price: -totalDiscount
        )
      }

      if cart.paid > 0 {
        PaymentLineBasicView(
          lineName: "Paid",
          price: cart.paid
        )
      }

      PaymentLineBasicView(
        lineName: "Total",
        price: cart.total - cart.paid
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
          webViewUrl: Register.fallbackURL,
          themeColor: Register.fallbackThemeColor
        )
      ) {
        PaymentFeature()
      }
    )
  }
}
