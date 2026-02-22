//
//  PaymentWebView.swift
//  Register
//

import Combine
import SwiftUI
import WebKit

struct ThemedWebView: UIViewRepresentable {
  let actionPublisher: any Publisher<Action, Never>

  let url: URL
  let themeColor: Color

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

extension ThemedWebView {
  enum Action {
    case resetScroll
  }
}

extension ThemedWebView {
  final class Coordinator: NSObject, WKNavigationDelegate {
    var currentUrl: URL?
    var currentThemeColor: Color

    var actionSubscriber: (any Cancellable)?

    init(themeColor: Color) {
      self.currentThemeColor = themeColor
    }

    func updateIfNeeded(_ webView: WKWebView, url: URL, themeColor: Color) {
      if url != currentUrl {
        currentUrl = url
        currentThemeColor = themeColor

        let request = URLRequest(url: url)
        webView.load(request)
      }

      if themeColor != currentThemeColor {
        currentThemeColor = themeColor
        updateThemeColor(webView)
      }
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async
      -> WKNavigationActionPolicy
    {
      return navigationAction.request.url == currentUrl ? .allow : .cancel
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
      updateThemeColor(webView)
    }

    func updateThemeColor(_ webView: WKWebView) {
      webView.evaluateJavaScript(
        "document.documentElement.style.setProperty('--terminal-color', '\(currentThemeColor.hexString)');"
      )
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
