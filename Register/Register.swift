//
//  Register.swift
//  Register
//

import SwiftUI
import os

struct Register {
  static let bundle = "net.syfaro.Register"
  static let logger = Logger(subsystem: bundle, category: "Main")

  static let themeColor = Color(red: 0, green: 153 / 255, blue: 204 / 255)
  static let fallbackURL = URL(string: "https://www.google.com")!

  static let simulatedQRCode =
    #"{"terminalName": "name", "host": "http://localhost:8080", "token": "helloworld"}"#

  static var presentingViewController: UIViewController? {
    return UIApplication.shared.connectedScenes.filter {
      $0.activationState == .foregroundActive
    }
    .compactMap { $0 as? UIWindowScene }
    .first?
    .windows
    .filter { $0.isKeyWindow }
    .first?
    .rootViewController?
    .presentedViewController
  }
}
