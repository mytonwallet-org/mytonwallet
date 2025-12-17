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
    
    var accountId: String
    let filter: NftCollectionFilter
    @Published var nfts: [ApiNft]

    init(accountId: String, filter: NftCollectionFilter) {
        self.accountId = accountId
        self.filter = filter
        self.nfts = Array(filter.apply(to: NftStore.getAccountShownNfts(accountId: accountId) ?? [:]).values.map(\.nft))
    }
}

