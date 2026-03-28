import Foundation
import OrderedCollections

public struct MAccountWalletTokensData: Equatable, Hashable, Sendable {
    public let walletTokensDict: OrderedDictionary<String, MTokenBalance>
    public let walletStakedDict: OrderedDictionary<String, MTokenBalance>

    public var walletTokens: [MTokenBalance] { Array(walletTokensDict.values) }
    public var walletStaked: [MTokenBalance] { Array(walletStakedDict.values) }

    init(walletTokens: [MTokenBalance], walletStaked: [MTokenBalance]) {
        self.walletTokensDict = walletTokens.orderedDictionaryByKey(\.tokenSlug)
        self.walletStakedDict = walletStaked.orderedDictionaryByKey(\.tokenSlug)
    }
}
