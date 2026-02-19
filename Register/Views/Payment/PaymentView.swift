//
//  PaymentView.swift
//  Register
//

import Combine
import ComposableArchitecture
import SwiftUI

@Reducer
struct PaymentFeature {
  @Dependency(\.square) var square

  @ObservableState
  struct State {
    @Presents var alert: AlertState<Action.Alert>?

    var webViewUrl: URL
    var themeColor: Color

    var cart: TerminalCart?

    var showingMockReaderUI = false
    var showingRegistration = false

    var viewController = UIViewController()

    var paymentWebActionPublisher = PassthroughSubject<PaymentWebView.Action, Never>()
    var regWebActionPublisher = CurrentValueSubject<RegistrationWebView.Action?, Never>(nil)
  }

  enum Action: Equatable {
    case alert(PresentationAction<Alert>)
    case dismissView
    case toggleMockReaderUI

    case registrationAlert(String)
    case registrationCompleted

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
        } else if square.environment() == .sandbox {
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
              }
            )
          }
        }
        return .none
      case .registrationAlert(let message):
        state.alert = AlertState(
          title: {
            TextState("Error")
          },
          message: {
            TextState(message)
          }
        )
        return .none
      case .registrationCompleted:
        state.showingRegistration = false
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
    ZStack {
      ViewHolder(controller: store.viewController)
      content
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(store.themeColor)
    .statusBarHidden()
    .preferredColorScheme(.light)
    .alert(
      store: self.store.scope(state: \.$alert, action: \.alert)
    )
    .fullScreenCover(isPresented: .constant(store.showingRegistration)) {
      RegistrationWebView(actionPublisher: store.regWebActionPublisher) { message in
        store.send(.registrationAlert(message))
      } completionHandler: {
        store.send(.registrationCompleted)
      }
      .ignoresSafeArea()
      .statusBarHidden()
    }
    .onAppear {
      UIApplication.shared.isIdleTimerDisabled = true
    }
    .onDisappear {
      UIApplication.shared.isIdleTimerDisabled = false
    }
  }

  @ViewBuilder
  var content: some View {
    if horizontalSizeClass == .compact {
      payment
    } else {
      TwoColumnLayout(mainColumnSize: 3 / 5, minimumSecondaryWidth: 300) {
        PaymentWebView(
          actionPublisher: store.paymentWebActionPublisher,
          url: store.webViewUrl,
          themeColor: store.themeColor
        )
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
        .onLongPressGesture {
          store.send(.toggleMockReaderUI)
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

extension Color {
  var hexString: String {
    let uitColor = UIColor(self)
    var r: CGFloat = 0
    var g: CGFloat = 0
    var b: CGFloat = 0
    var a: CGFloat = 0

    uitColor.getRed(&r, green: &g, blue: &b, alpha: &a)

    return String(
      format: "#%02lX%02lX%02lX",
      lroundf(Float(r) * 255),
      lroundf(Float(g) * 255),
      lroundf(Float(b) * 255)
    )
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
