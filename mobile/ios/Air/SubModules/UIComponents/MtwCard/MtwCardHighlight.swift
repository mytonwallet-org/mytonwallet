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
            EllipticalGradient(colors: [color, .clear])
                .opacity(0.16)
        }
    }
}

