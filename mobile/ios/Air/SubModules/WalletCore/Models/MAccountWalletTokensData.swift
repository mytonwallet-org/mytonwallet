import Foundation
import OrderedCollections

public struct MAccountWalletTokensData: Equatable, Hashable, Sendable {
    public let orderedTokenBalancesDict: OrderedDictionary<TokenID, MTokenBalance>

    public var orderedTokenBalances: [MTokenBalance] { Array(orderedTokenBalancesDict.values) }
    public var walletTokens: [MTokenBalance] { orderedTokenBalances.filter { !$0.isStaking } }
    public var walletStaked: [MTokenBalance] { orderedTokenBalances.filter(\.isStaking) }

    init(orderedTokenBalances: [MTokenBalance]) {
        self.orderedTokenBalancesDict = OrderedDictionary(
            uniqueKeysWithValues: orderedTokenBalances.map { ($0.tokenID, $0) }
        )
    }
}
