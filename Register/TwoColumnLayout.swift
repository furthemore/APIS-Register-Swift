//
//  TwoColumnLayout.swift
//  Register
//

import SwiftUI

struct TwoColumnLayout: Layout {
  var mainColumnSize: Double
  var minimumSecondaryWidth: Double? = nil
  
  func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
    return proposal.replacingUnspecifiedDimensions()
  }
  
  func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
    precondition(
      subviews.count == 2,
      "Two column layout must have exactly two subviews"
    )
    
    var p = bounds.origin
    
    var w0 = bounds.size.width * mainColumnSize
    if let minimumSecondaryWidth = minimumSecondaryWidth,
       bounds.size.width - w0 < minimumSecondaryWidth {
      let fittingMinimum = min(minimumSecondaryWidth, bounds.width)
      w0 = bounds.size.width - fittingMinimum
    }

    subviews[0].place(at: p, proposal: .init(
      width: w0,
      height: bounds.size.height
    ))
    p.x += w0
    
    subviews[1].place(at: p, proposal: .init(
      width: bounds.size.width - w0,
      height: bounds.size.height
    ))
  }
}
