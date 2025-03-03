//
//  PaymentView.swift
//  Register
//

import Combine
import ComposableArchitecture
import SwiftUI
import WebKit

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

    var webViewActionPublisher = PassthroughSubject<WebView.Action, Never>()
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
        WebView(
          actionPublisher: store.webViewActionPublisher,
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
  enum Action {
    case resetScroll
  }

  final class Coordinator: NSObject, WKNavigationDelegate {
    var previousUrl: URL?
    var previousThemeColor: Color

    var actionSubscriber: (any Cancellable)?

    init(themeColor: Color) {
      self.previousThemeColor = themeColor
    }
    
    func updateIfNeeded(_ webView: WKWebView, url: URL, themeColor: Color) {
      if url != previousUrl {
        let request = URLRequest(url: url)
        webView.load(request)
        
        previousUrl = url
        previousThemeColor = themeColor
      }
      
      if themeColor != previousThemeColor {
        previousThemeColor = themeColor

        updateThemeColor(webView)
      }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
      updateThemeColor(webView)
    }
    
    func updateThemeColor(_ webView: WKWebView) {
      webView.evaluateJavaScript(
        "document.documentElement.style.setProperty('--terminal-color', '\(previousThemeColor.hexString)');"
      )
    }
  }

  var actionPublisher: any Publisher<Action, Never>

  var url: URL
  var themeColor: Color

  func makeCoordinator() -> Coordinator {
    Coordinator(themeColor: themeColor)
  }

  func makeUIView(context: Context) -> WKWebView {
    let userScript = WKUserScript(
      source:
        "document.documentElement.style.setProperty('--terminal-color', '\(themeColor.hexString)');",
      injectionTime: .atDocumentEnd,
      forMainFrameOnly: true
    )

    let webView = WKWebView()

    webView.navigationDelegate = context.coordinator

    webView.isInspectable = true
    webView.configuration.preferences.isTextInteractionEnabled = false
    webView.scrollView.isScrollEnabled = false
    
    webView.configuration.userContentController.addUserScript(userScript)

    context.coordinator.actionSubscriber = actionPublisher.sink { action in
      switch action {
      case .resetScroll:
        webView.evaluateJavaScript(
          "document.querySelector('main').scroll({top: 0, behavior: 'smooth'});"
        )
      }
    }

    return webView
  }

  func updateUIView(_ webView: WKWebView, context: Context) {
    context.coordinator.updateIfNeeded(webView, url: url, themeColor: themeColor)
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
