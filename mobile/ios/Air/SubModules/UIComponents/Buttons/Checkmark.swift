//
//  IntroView.swift
//  MyTonWalletAir
//
//  Created by nikstar on 04.09.2025.
//

import SwiftUI
import WalletContext

public struct Checkmark: View {
    
    public var isOn: Bool
    
    public init(isOn: Bool) {
        self.isOn = isOn
    }
    
    public var body: some View {
        ZStack {
            Circle()
                .stroke(Color.air.checkmarkDisabled, lineWidth: 1.2)
            if isOn {
                Circle()
                    .fill(Color.air.tint)
                    .transition(.opacity
                        .combined(with: .scale(scale: 0.2))
                    )
                Image(systemName: "checkmark")
                    .foregroundStyle(.white)
                    .font(.system(size: 10, weight: .semibold))
                    .transition(.modifier(
                        active: CheckmarkTransition(active: true),
                        identity: CheckmarkTransition(active: false)
                    ))
            }
        }
        .frame(width: 20, height: 20)
        .contentShape(.circle)
    }
}


private struct CheckmarkTransition: ViewModifier {
    var active: Bool
    
    func body(content: Content) -> some View {
        content
            .rotationEffect(Angle.degrees(active ? -15 : 0))
            .scaleEffect(active ? 0 : 1)
            .offset(y: active ? 3 : 0)
    }
}
