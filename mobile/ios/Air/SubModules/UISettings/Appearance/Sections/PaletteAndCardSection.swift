//
//  PaletteSection.swift
//  MyTonWalletAir
//
//  Created by nikstar on 17.10.2025.
//

import Foundation
import SwiftUI
import UIKit
import UIComponents
import WalletContext
import WalletCore
import Flow
import Perception
import Dependencies

struct PaletteAndCardSection: View {
    
    @State var accountContext = AccountContext(source: .current)
    
    var body: some View {
        InsetSection {
            cell
        } header: {
            Text(lang("Palette and Card"))
        } footer: {
            Text(lang("Customize the wallet's home screen and color accents the way you like."))
        }
    }
    
    var cell: some View {
        InsetButtonCell(action: onTap) {
            HStack(spacing: 16) {
                PaletteAndCardIcon(accountContext: accountContext)
                Text(lang("Customize Wallet"))
                    .foregroundStyle(Color.air.primaryLabel)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Image.airBundle("RightArrowIcon")
            }
        }
    }
    
    func onTap() {
        AppActions.showCustomizeWallet(accountId: nil)
    }
}

struct PaletteAndCardIcon: View {
    
    let accountContext: AccountContext
    
    var body: some View {
        WithPerceptionTracking {
            Color.clear
                .frame(width: 30, height: 30)
                .overlay(alignment: .leading) {
                    Circle()
                        .foregroundStyle(Color(accountContext.accentColor))
                        .frame(width: 28, height: 28)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 3 + 1.333)
                        .padding(-1.333)
                        .offset(x: 6)
                        .rotationEffect(.degrees(-10))
                        .frame(width: 22, height: 14)
                        .blendMode(.destinationOut)
                }
                .compositingGroup()
                .overlay {
                    _CardMiniature(accountContext: accountContext)
                        .offset(x: 6)
                        .rotationEffect(.degrees(-10))
                }
        }
    }
}

struct _CardMiniature: View {
    
    let accountContext: AccountContext
    
    private let cardPreviewSize = CGSize(width: 22, height: 14)
    
    var body: some View {
        WithPerceptionTracking {
            MtwCardBackground(nft: accountContext.nft, hideBorder: true)
                .clipShape(.rect(cornerRadius: 3))
                .frame(width: 22, height: 14)
                .overlay {
                    MtwCardMiniPlaceholders()
                        .sourceAtop {
                            MtwCardInverseCenteredGradient(nft: accountContext.nft)
                        }
                }
        }
    }
}


#Preview {
    Color.blue.opacity(0.2)
        .overlay {
            PaletteAndCardSection()
                .fixedSize(horizontal: false, vertical: true)
        }
}
