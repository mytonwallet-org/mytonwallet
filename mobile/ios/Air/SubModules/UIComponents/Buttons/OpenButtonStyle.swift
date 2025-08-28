//
//  OpenButtonStyle.swift
//  MyTonWalletAir
//
//  Created by nikstar on 20.07.2025.
//

import SwiftUI
import WalletContext

public struct OpenButtonStyle: ButtonStyle {
    @State private var isHighlighted: Bool = false
    
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .opacity(isHighlighted ? 0.5 : 1)
            .foregroundStyle(Color(WTheme.tint))
            .background(Color(WTheme.tint), in: .containerRelative)
            .contentShape(.containerRelative.inset(by: -10))
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
