//
//  ViewHolder.swift
//  Register
//

import SwiftUI

struct ViewHolder: UIViewControllerRepresentable {
  typealias UIViewControllerType = UIViewController

  let controller: UIViewController

  func makeUIViewController(context: Context) -> UIViewController {
    return controller
  }

  func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}
}
