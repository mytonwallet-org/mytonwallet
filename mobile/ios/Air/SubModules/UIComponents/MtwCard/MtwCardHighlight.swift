//
//  MtwCardHighlight.swift
//  MyTonWalletAir
//
//  Created by nikstar on 19.11.2025.
//

import SwiftUI
import WalletCore
import WalletContext

public struct MtwCardHighlight: View {
    
    var nft: ApiNft?
    
    public init(nft: ApiNft?) {
        self.nft = nft
    }
    
    public var body: some View {
        if nft?.metadata?.mtwCardType == .standard {
            let color: Color = nft?.metadata?.mtwCardTextType == .dark ? .white : .black
            let colors: [Color] = [color.opacity(1), color.opacity(0.8), color.opacity(0.5), color.opacity(0.2), color.opacity(0)]
            GeometryReader { geom in
                ZStack {
                    EllipticalGradient(colors: colors)
                        .opacity(0.2)
                        .blendMode(.overlay)
                    EllipticalGradient(colors: colors)
                        .opacity(0.16)
                }
                .padding(.vertical, -geom.size.height/5)
                .padding(.horizontal, -geom.size.width/5)
            }
        }
    }
}

