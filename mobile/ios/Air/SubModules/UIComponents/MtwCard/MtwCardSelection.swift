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
            .clipShape(.rect(cornerRadius: cornerRadius))
            .padding(2 * lineWidth)
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius + 2 * lineWidth)
                    .strokeBorder(lineWidth: lineWidth)
                    .foregroundStyle(isSelected ?  AnyShapeStyle(.tint) : AnyShapeStyle(.clear))
            }
    }
}

public extension View {
    func mtwCardSelection(isSelected: Bool, cornerRadius: CGFloat, lineWidth: CGFloat) -> some View {
        modifier(MtwCardSelection(isSelected: isSelected, cornerRadius: cornerRadius, lineWidth: lineWidth))
    }
}
