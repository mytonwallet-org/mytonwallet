//
//  MtwCardBorder.swift
//  MyTonWalletAir
//
//  Created by nikstar on 19.11.2025.
//

import SwiftUI
import WalletCore
import WalletContext

public struct MtwCardBorder: View {
    
    var nft: ApiNft?
    var borderWidthMultiplier: CGFloat
    
    public init(nft: ApiNft?, borderWidthMultiplier: CGFloat) {
        self.nft = nft
        self.borderWidthMultiplier = borderWidthMultiplier
    }
    
    public var body: some View {
        ZStack {
            Color.clear
            if let linearGradientColors {
                LinearGradient(
                    colors: linearGradientColors,
                    startPoint: UnitPoint(x: 0.65, y: 0.1),
                    endPoint: UnitPoint(x: 0.45, y: 0.25),
                )
            }
            if let highlightRotation {
                GeometryReader { geom in
                    EllipticalGradient(
                        stops: [
                            .init(color: .white.opacity(1), location: circleHighlight ? 0.1 : 0.05),
                            .init(color: .white.opacity(0), location: 1),
                        ],
                    )
                    .scaleEffect(circleHighlight ? CGSize(width: 0.6, height: 1.3) : CGSize(width: 1, height: 0.5))
                    .offset(x: geom.size.width * 0.5)
                    .rotationEffect(.degrees(highlightRotation))
                }
            }
        }
        .mask {
            ContainerRelativeShape()
                .strokeBorder(lineWidth: borderWidth * borderWidthMultiplier)
                .foregroundStyle(.black)
        }
    }
    
    var borderWidth: CGFloat {
        nft?.metadata?.mtwCardType == .black ? 2 : 1.333
    }
    
    var linearGradientColors: [Color]? {
        return getCardBorderColors(nft: nft)
    }
    
    var circleHighlight: Bool {
        nft?.metadata?.mtwCardType == .black
    }
    
    var highlightRotation: CGFloat? {
        if nft?.metadata?.mtwCardType?.isPremium == true {
            -45
        } else {
            switch nft?.metadata?.mtwCardBorderShineType {
            case .up:
                -80
            case .down:
                70
            case .left:
                -190
            case .right:
                10
            case .radioactive:
                nil
            case nil:
                nil
            }
        }
    }
}
