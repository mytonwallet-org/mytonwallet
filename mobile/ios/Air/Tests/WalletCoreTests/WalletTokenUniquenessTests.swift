import Testing
import WalletContext
@testable import WalletCore

@Suite("Wallet Token Uniqueness")
struct WalletTokenUniquenessTests {
    @Test(arguments: [false, true])
    func `multiple staking positions share one row with their combined balance`(isHidden: Bool) {
        let walletTon = MTokenBalance(tokenSlug: TONCOIN_SLUG, balance: 7, isStaking: false)
        let liquidTon = MTokenBalance(tokenSlug: TONCOIN_SLUG, balance: 11, isStaking: true)
        let nominatorTon = MTokenBalance(tokenSlug: TONCOIN_SLUG, balance: 13, isStaking: true)
        let stakedMy = MTokenBalance(tokenSlug: MYCOIN_SLUG, balance: 17, isStaking: true)
        let account = MAccount(
            id: "wallet-token-uniqueness-mainnet",
            title: nil,
            type: .mnemonic,
            byChain: [.ton: AccountChain(address: "ton-address")]
        )
        var preferences = MAssetsAndActivityData.empty
        preferences.saveTokenHidden(slug: TONCOIN_SLUG, isStaking: true, isHidden: isHidden)
        preferences.saveTokenPinning(slug: TONCOIN_SLUG, isStaking: true, isPinned: true)

        let presentation = MTokenBalance.presentationForUI(
            walletTokens: [walletTon],
            walletStaked: [liquidTon, stakedMy, nominatorTon],
            account: account,
            assetsAndActivityData: preferences,
            hidesTokensWithNoCost: false
        )
        let data = MAccountWalletTokensData(
            orderedTokenBalances: presentation.visible,
            hiddenTokenBalances: presentation.hidden
        )
        let stakingRows = data.allTokenBalances.filter { $0.tokenID == liquidTon.tokenID }

        #expect(stakingRows.count == 1)
        #expect(stakingRows.first?.balance == 24)
        #expect(data.orderedTokenBalancesDict[walletTon.tokenID] == walletTon)
        #expect(data.orderedTokenBalancesDict[stakedMy.tokenID] == stakedMy)
        if isHidden {
            #expect(data.hiddenTokenBalancesDict[liquidTon.tokenID]?.balance == 24)
            #expect(data.orderedTokenBalancesDict[liquidTon.tokenID] == nil)
        } else {
            #expect(data.orderedTokenBalances.first?.tokenID == liquidTon.tokenID)
            #expect(data.hiddenTokenBalances.isEmpty)
        }
    }

    @Test(arguments: [false, true])
    func `repeated token IDs keep the latest value and original order`(isHidden: Bool) {
        let original = MTokenBalance(tokenSlug: TONCOIN_SLUG, balance: 7, isStaking: false)
        let other = MTokenBalance(tokenSlug: MYCOIN_SLUG, balance: 11, isStaking: false)
        let latest = MTokenBalance(tokenSlug: TONCOIN_SLUG, balance: 13, isStaking: false)
        let balances = [original, other, latest]

        let data = MAccountWalletTokensData(
            orderedTokenBalances: isHidden ? [] : balances,
            hiddenTokenBalances: isHidden ? balances : []
        )

        #expect(data.orderedTokenBalances == (isHidden ? [] : [latest, other]))
        #expect(data.hiddenTokenBalances == (isHidden ? [latest, other] : []))
    }
}
