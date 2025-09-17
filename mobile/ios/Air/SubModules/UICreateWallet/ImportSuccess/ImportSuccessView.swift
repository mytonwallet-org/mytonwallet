//
//  WordDisplayView.swift
//  MyTonWalletAir
//
//  Created by nikstar on 04.09.2025.
//

import SwiftUI
import WalletContext
import WalletCore
import UIComponents
import Flow
import UIHome

struct ImportSuccessView: View {
    
    var introModel: IntroModel
    var successKind: SuccessKind
    
    @State private var showConfetti: Bool = false

    var body: some View {
        VStack(spacing: 20) {
            WUIAnimatedSticker("animation_happy", size: 160, loop: true)
                .frame(width: 160, height: 160)
                
            VStack(spacing: 20) {
                title
                description
            }
            .padding(.bottom, 180)
        }
        .frame(maxHeight: .infinity)
        .safeAreaInset(edge: .bottom) {
            Button(action: onOpenWallet) {
                Text(lang("Open Wallet"))
            }
            .buttonStyle(.airPrimary)
            .padding(.bottom, 32)
        }
        .padding(.horizontal, 32)
        .overlay {
            if showConfetti {
                Confetti()
//                    .background(Color.red)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
                    .frame(maxHeight: .infinity, alignment: .top)
            }
        }
        .task {
            try? await Task.sleep(for: .seconds(0.5))
            showConfetti = true
        }
    }
    
    var title: some View {
        Text(langMd("All Set!"))
            .multilineTextAlignment(.center)
            .font(.system(size: 28, weight: .semibold))
    }
    
    @ViewBuilder
    var description: some View {
        let line1 = lang(successKind == .created ? "$finalized_wallet_creation" : "$finalized_wallet_import")
        let line2 = lang("$store_securely")
        Text(LocalizedStringKey(line1 + "\n\n" + line2))
            .multilineTextAlignment(.center)
    }
    
    // MARK: Actions
    
    func onOpenWallet() {
        introModel.onOpenWallet()
    }
}
