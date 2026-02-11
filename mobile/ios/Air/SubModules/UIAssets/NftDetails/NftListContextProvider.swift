//
//  NftListContextProvider.swift
//  UIAssets
//
//  Created by nikstar on 18.08.2025.
//

import WalletCore
import WalletContext
import Perception

@Perceptible
final class NftListContextProvider {
    
    @PerceptionIgnored
    var accountId: String
    let filter: NftCollectionFilter
    var nfts: [ApiNft]

    init(accountId: String, filter: NftCollectionFilter, fixedNfts: [ApiNft]? = nil) {
        self.accountId = accountId
        self.filter = filter
        if let fixedNfts {
            self.nfts = fixedNfts
        } else {
            self.nfts = Array(filter.apply(to: NftStore.getAccountShownNfts(accountId: accountId) ?? [:]).values.map(\.nft))
        }
    }
}
