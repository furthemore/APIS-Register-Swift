//
//  ConfigClient+SwiftUI.swift
//  Register
//

#if canImport(SwiftUI)

  import SwiftUI
  import UIKit

  extension Config {
    var parsedColor: Color {
      Color(hexString: themeColor) ?? Register.fallbackThemeColor
    }
  }

  extension Color {
    public init?(hexString: String) {
      guard let hex = Int(hexString.trimmingPrefix("#"), radix: 16) else { return nil }

      self = Color(
        red: Double((hex >> 16) & 0xff) / 255,
        green: Double((hex >> 8) & 0xff) / 255,
        blue: Double(hex & 0xff) / 255
      )
    }

    var luminance: Double {
      let uiColor = UIColor(self)

      var r: CGFloat = 0
      var g: CGFloat = 0
      var b: CGFloat = 0

      uiColor.getRed(&r, green: &g, blue: &b, alpha: nil)

      return 0.2126 * Double(r) + 0.7152 * Double(g) + 0.0722 * Double(b)
    }

    var isLight: Bool {
      luminance > 0.5
    }

    var adaptedTextColor: Color {
      isLight ? .black : .white
    }
  }

#endif
