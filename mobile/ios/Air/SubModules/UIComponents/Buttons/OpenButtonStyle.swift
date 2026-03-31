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

    @State private var isHighlighted: Bool = false
    
    public init(
        foregroundColor: Color = Color.air.folderFill,
        backgroundColor: Color = Color.air.buttonBackground
    ) {
        self.foregroundColor = foregroundColor
        self.backgroundColor = backgroundColor
    }

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .bold))
            .foregroundStyle(foregroundColor)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
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
