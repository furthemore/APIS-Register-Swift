//
//  PaymentWebView.swift
//  Register
//

import Combine
import SwiftUI
import WebKit

struct PaymentWebView: UIViewRepresentable {
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
