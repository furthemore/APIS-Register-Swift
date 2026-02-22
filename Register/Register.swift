//
//  Register.swift
//  Register
//

import SwiftUI
import os

struct Register {
  static let bundle = "net.syfaro.Register"
  static let logger = Logger(subsystem: bundle, category: "Main")

  static let fallbackThemeColor = Color(red: 255, green: 0, blue: 255)
  static let fallbackURL = URL(string: "https://www.google.com")!

  static let simulatedQRCode = """
    {
      "terminalName": "mockterminal",
      "endpoint": "http://example.com",
      "token": "MOCK-TOKEN",
      "webViewUrl": "http://example.com",
      "themeColor": "#000000",
      "mqttHost": "http://example.com",
      "mqttPort": 443,
      "mqttUsername": "MOCK-USERNAME",
      "mqttPassword": "MOCK-PASSWORD",
      "mqttPrefix": "MOCK-TOPIC",
      "squareApplicationId": "MOCK-SQUARE-APPLICATION-ID",
      "squareLocationId": "MOCK-SQUARE-LOCATION-ID"
    }
    """
}
