//
//  MtwCard.swift
//  UIComponents
//
//  Created by nikstar on 19.11.2025.
//

import SwiftUI
import WalletCore
import WalletContext

public struct MtwCard: View {
    
    var aspectRatio: CGFloat?
    
    public init(aspectRatio: CGFloat?) {
        self.aspectRatio = aspectRatio
    }
    
    public var body: some View {
        Color.clear
            .aspectRatio(aspectRatio, contentMode: .fit)
            .contentShape(.containerRelative)
    }
}


#if DEBUG
private let card = ApiNft.sampleMtwCard
private let black: ApiNft = {
    var card = card
    card.metadata?.mtwCardId = 1
    card.metadata?.mtwCardType = .black
    return card
}()
private let platinum: ApiNft = {
    var card = card
    card.metadata?.mtwCardId = 37
    card.metadata?.mtwCardType = .platinum
    return card
}()
private let gold: ApiNft = {
    var card = card
    card.metadata?.mtwCardId = 170
    card.metadata?.mtwCardType = .gold
    return card
}()
private let silver: ApiNft = {
    var card = card
    card.metadata?.mtwCardId = 629
    card.metadata?.mtwCardType = .silver
    return card
}()
private let standard: ApiNft = {
    var card = card
    card.metadata?.mtwCardId = 1634
    card.metadata?.mtwCardType = .standard
    return card
}()
private let standardDark: ApiNft = {
    var card = card
    card.metadata?.mtwCardId = 1667
    card.metadata?.mtwCardType = .standard
    card.metadata?.mtwCardTextType = .dark
    return card
}()

private struct _Card: View {
    var nft: ApiNft?
    
    var body: some View {
//        ZStack {
//            Color.clear
//            MtwCardBorder(nft: nft)
//        }
        MtwCardBackground(nft: nft, hideBorder: false)
            .overlay {
                MtwCardBalanceView(balance: BaseCurrencyAmount.fromDouble(18225.26, .USD), style: .homeCard, secondaryOpacity: nft?.metadata?.mtwCardType?.isPremium == true ? 1 : 0.75)
//                    .background(.white)
                    .padding(40)
                    .sourceAtop {
                        MtwCardBalanceGradient(nft: nft)
                    }
                    .padding(-40)
                    .offset(y: -8)
            }
            .clipShape(.containerRelative)
            .containerShape(.rect(cornerRadius: 26))
            .aspectRatio(1/CARD_RATIO, contentMode: .fit)
            .overlay(alignment: .topTrailing) {
                Text((nft?.metadata?.mtwCardType?.rawValue ?? "none") + (nft?.metadata?.mtwCardTextType == .dark ? " dark" : ""))
                    .foregroundStyle(.secondary)
                    .font13()
                    .padding(.horizontal, 24)
                    .padding(.vertical, 8)
            }
            .padding(.horizontal, 16)
    }
}

#Preview {
    ScrollView {
        VStack(spacing: 24) {
            _Card(nft: black)
            _Card(nft: platinum)
            _Card(nft: gold)
            _Card(nft: silver)
            _Card(nft: standard)
            _Card(nft: standardDark)
            _Card(nft: nil)
        }
        .padding(.bottom, 300)
    }
    .background {
        Color.airBundle("HeaderBackgroundColor")
            .ignoresSafeArea()
    }
}
#endif
