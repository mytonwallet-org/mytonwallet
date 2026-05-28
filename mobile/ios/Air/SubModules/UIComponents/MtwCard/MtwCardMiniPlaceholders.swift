//
//  MtwCardMiniPlaceholders.swift
//  MyTonWalletAir
//
//  Created by nikstar on 19.11.2025.
//

import SwiftUI
import WalletContext

public struct MtwCardMiniPlaceholders: View {
    
    public init() {
    }
    
    public var body: some View {
        VStack(spacing: 5.5) {
            VStack(spacing: 1.5) {
                Capsule()
                    .frame(width: 16, height: 2)
                Capsule()
                    .opacity(0.6)
                    .frame(width: 6, height: 1.5)
            }
            Capsule()
                .opacity(0.6)
                .frame(width: 8, height: 1.5)
        }
        .padding(.top, 3)
//        .drawingGroup()
    }
}


#Preview {
    Color.blue.overlay {
        MtwCardMiniPlaceholders()
            .foregroundStyle(.white)
    }
}
