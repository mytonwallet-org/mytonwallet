import Foundation
import OrderedCollections

public struct MAccountWalletTokensData: Equatable, Hashable, Sendable {
    public let orderedTokenBalancesDict: OrderedDictionary<TokenID, MTokenBalance>
    public let hiddenTokenBalancesDict: OrderedDictionary<TokenID, MTokenBalance>

    public var orderedTokenBalances: [MTokenBalance] { Array(orderedTokenBalancesDict.values) }
    public var walletTokens: [MTokenBalance] { orderedTokenBalances.filter { !$0.isStaking } }
    public var walletStaked: [MTokenBalance] { orderedTokenBalances.filter(\.isStaking) }
    public var hiddenTokenBalances: [MTokenBalance] { Array(hiddenTokenBalancesDict.values) }
    public var hiddenWalletTokens: [MTokenBalance] { hiddenTokenBalances.filter { !$0.isStaking } }
    public var allTokenBalances: [MTokenBalance] { orderedTokenBalances + hiddenTokenBalances }
    public var presentation: MTokenBalance.Presentation {
        MTokenBalance.Presentation(
            visible: orderedTokenBalances,
            hidden: hiddenTokenBalances
        )
    }

    init(orderedTokenBalances: [MTokenBalance], hiddenTokenBalances: [MTokenBalance]) {
        self.orderedTokenBalancesDict = OrderedDictionary(
            uniqueKeysWithValues: orderedTokenBalances.map { ($0.tokenID, $0) }
        )
        self.hiddenTokenBalancesDict = OrderedDictionary(
            uniqueKeysWithValues: hiddenTokenBalances.map { ($0.tokenID, $0) }
        )
    }
}
