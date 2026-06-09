//
//  OpenButtonStyle.swift
//  MyTonWalletAir
//
//  Created by nikstar on 20.07.2025.
//

import SwiftUI
import WalletContext

public struct OpenButtonStyle: PrimitiveButtonStyle {
    private let foregroundColor: Color
    private let backgroundColor: Color
    private let fontSize: CGFloat
    private let paddings: CGSize
    
    public enum Size {
        case standard, small
    }

    @State private var isHighlighted: Bool = false
    
    public init(
        foregroundColor: Color = Color.air.folderFill,
        backgroundColor: Color = Color.air.buttonBackground,
        size: Size = .standard
    ) {
        self.foregroundColor = foregroundColor
        self.backgroundColor = backgroundColor
        switch size {
        case .standard:
            fontSize = 16
            paddings = .init(width: 16, height: 8)
        case .small:
            fontSize = 14
            paddings = .init(width: 12, height: 4)
        }
    }

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: fontSize, weight: .bold))
            .foregroundStyle(foregroundColor)
            .padding(.horizontal, paddings.width)
            .padding(.vertical, paddings.height)
            .opacity(isHighlighted ? 0.5 : 1)
            .background(backgroundColor, in: .containerRelative)
            .contentShape(.containerRelative.inset(by: -10))
            .onTapGesture {
                configuration.trigger()
            }
            .simultaneousGesture(DragGesture(minimumDistance: 0).onChanged { _ in
                withAnimation(.spring(duration: 0.1)) {
                    isHighlighted = true
                }
            }.onEnded { _ in
                withAnimation(.spring(duration: 0.5)) {
                    isHighlighted = false
                }
            })
            .containerShape(.capsule)
    }
}
