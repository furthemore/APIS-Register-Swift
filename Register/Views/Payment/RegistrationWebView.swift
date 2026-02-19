//
//  RegistrationWebView.swift
//  Register
//

import Combine
import SwiftUI
import WebKit

struct RegistrationWebView: UIViewRepresentable {
  enum Action {
    case navigate(to: URL, token: String)
  }

  let actionPublisher: any Publisher<Action?, Never>
  let alertHandler: ((String) -> Void)?
  let completionHandler: (() -> Void)?

  final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
    var alertHandler: ((String) -> Void)?
    var completionHandler: (() -> Void)?

    var actionSubscriber: (any Cancellable)?

    init(alertHandler: ((String) -> Void)? = nil, completionHandler: (() -> Void)? = nil) {
      self.alertHandler = alertHandler
      self.completionHandler = completionHandler
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
      if let url = webView.url, url.absoluteString.hasSuffix("/done") {
        completionHandler?()
      }
    }

    func webView(
      _ webView: WKWebView,
      runJavaScriptAlertPanelWithMessage message: String,
      initiatedByFrame frame: WKFrameInfo
    ) async {
      alertHandler?(message)
    }
  }

  func makeCoordinator() -> Coordinator {
    Coordinator(alertHandler: alertHandler, completionHandler: completionHandler)
  }

  func makeUIView(context: Context) -> WKWebView {
    let webView = WKWebView()

    webView.navigationDelegate = context.coordinator
    webView.isInspectable = true

    context.coordinator.actionSubscriber = actionPublisher.sink { action in
      switch action {
      case .navigate(to: let url, let token):
        webView.configuration.websiteDataStore.httpCookieStore.setCookie(
          HTTPCookie(properties: [
            .domain: url.host()!,
            .path: "/",
            .name: "terminal-token",
            .value: token,
          ])!
        ) {
          webView.load(URLRequest(url: url))
        }
      default:
        break
      }
    }

    return webView
  }

  func updateUIView(_ webView: WKWebView, context: Context) {
    context.coordinator.alertHandler = alertHandler
    context.coordinator.completionHandler = completionHandler
  }
}
