//
//  WordDisplayView.swift
//  MyTonWalletAir
//
//  Created by nikstar on 04.09.2025.
//

import SwiftUI
import WalletContext
import UIComponents
import Flow

struct ImportSuccessView: View {
    
    var introModel: IntroModel
    var successKind: SuccessKind
    
    @State private var showConfetti: Bool = false

    var body: some View {
        VStack(spacing: 20) {
            WUIAnimatedSticker("animation_happy", size: 160, loop: true)
                .frame(width: 160, height: 160)
                .layoutPriority(1)
                
            VStack(spacing: 20) {
                title
                description
            }
            .layoutPriority(2)
            
            Color.clear.frame(minHeight: 0, maxHeight: 160)
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
            .style(.header28)
            .multilineTextAlignment(.center)
    }
    
    @ViewBuilder
    var description: some View {
        let line1 = successKind == .created ? lang("$wallet_create_done") : lang("$wallet_import_done", arg1: 1)
        let line2 = successKind != .importedView ? lang("$wallet_done_description") : ""
        Text(LocalizedStringKey(line1 + "\n\n" + line2))
            .style(.body17)
            .multilineTextAlignment(.center)
    }
    
    // MARK: Actions
    
    func onOpenWallet() {
        introModel.onOpenWallet()
    }
}
