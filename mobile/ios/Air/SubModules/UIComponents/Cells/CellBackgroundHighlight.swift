//
//  CellBaclgroundHighlight.swift
//  MyTonWalletAir
//
//  Created by nikstar on 18.11.2025.
//

import SwiftUI
import WalletContext

private let swipeCornerRadius: CGFloat = IOS_26_MODE_ENABLED ? 26 : 0

public struct CellBackgroundHighlight: View {
    
    var isHighlighted: Bool
    var isSwiped: Bool
    var normalColor: Color
    
    public init(isHighlighted: Bool, isSwiped: Bool = false, normalColor: Color = .air.groupedItem) {
        self.isHighlighted = isHighlighted
        self.isSwiped = isSwiped
        self.normalColor = normalColor
    }
    
    public var body: some View {
        Rectangle()
            .fill(isHighlighted ? Color.air.highlight : normalColor)
            .animation(.linear(duration: isHighlighted ? 0.1 : 0.5), value: isHighlighted)
            .clipShape(.rect(cornerRadius: isSwiped ? swipeCornerRadius : 0))
            .animation(.smooth(duration: 0.15), value: isSwiped)
    }
}
