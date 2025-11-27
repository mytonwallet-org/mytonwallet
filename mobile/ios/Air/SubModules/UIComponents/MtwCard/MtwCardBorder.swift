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
    
    public init(nft: ApiNft?) {
        self.nft = nft
    }
    
    public var body: some View {
        ContainerRelativeShape()
            .strokeBorder(lineWidth: 2)
            .foregroundStyle(.white.opacity(nft != nil ? 0.3 : 0))
    }
}
