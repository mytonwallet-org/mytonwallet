//
//  MtwCardHighlight.swift
//  MyTonWalletAir
//
//  Created by nikstar on 19.11.2025.
//

import SwiftUI
import WalletContext

public struct MtwCardSelection: ViewModifier {
    
    var isSelected: Bool
    var cornerRadius: CGFloat
    var lineWidth: CGFloat
    
    public init(isSelected: Bool, cornerRadius: CGFloat, lineWidth: CGFloat) {
        self.isSelected = isSelected
        self.cornerRadius = cornerRadius
        self.lineWidth = lineWidth
    }
    
    public func body(content: Content) -> some View {
        content
            .clipShape(.rect(cornerRadius: 12).inset(by: isSelected ? lineWidth : 0))
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: cornerRadius + lineWidth)
                        .strokeBorder(lineWidth: lineWidth)
                        .foregroundStyle(Color.air.tint)
                        .padding(-lineWidth)
                }
            }
    }
}

public extension View {
    func mtwCardSelection(isSelected: Bool, cornerRadius: CGFloat, lineWidth: CGFloat) -> some View {
        modifier(MtwCardSelection(isSelected: isSelected, cornerRadius: cornerRadius, lineWidth: lineWidth))
    }
}
