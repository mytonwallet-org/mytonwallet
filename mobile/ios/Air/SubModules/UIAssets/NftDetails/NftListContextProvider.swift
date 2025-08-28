//
//  NftListContextProvider.swift
//  UIAssets
//
//  Created by nikstar on 18.08.2025.
//

import SwiftUI
import WalletCore
import WalletContext

final class NftListContextProvider: ObservableObject {
    
    let filter: NftCollectionFilter
    @Published var nfts: [ApiNft]

    init(filter: NftCollectionFilter) {
        self.filter = filter
        self.nfts = Array(filter.apply(to: NftStore.currentAccountShownNfts ?? [:]).values.map(\.nft))
    }
}

