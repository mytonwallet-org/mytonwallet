import XCTest
import WalletContext
@testable import UIAgent
@testable import WalletCore

@MainActor
final class AgentV2HostSnapshotTests: XCTestCase {
    func testBackgroundSnapshotUsesCapturedTokensAndNftVisibility() async throws {
        let account = makeAccount()
        let token = ApiToken(slug: "snapshot-only-token", name: " Captured\nToken ", symbol: "SNAP", decimals: 3, chain: .ton)
        XCTAssertNil(TokenStore.tokens[token.slug])
        let balance = MTokenBalance(tokenSlug: token.slug, balance: 1234, isStaking: false)
        var nft = ApiNft.sample
        nft.name = " Captured\nNFT "
        nft.isUnverified = true
        nft.isHidden = false
        let contact = SavedAddress(name: " Test\nContact ", address: "captured-address", chain: .ton)
        let snapshot = AgentV2HostContextProvider.AccountSnapshot(
            account: account, balances: [balance], assetPreferences: .empty,
            nfts: [.init(nft: nft, isHiddenByUser: false)], nftLoadedChains: [.ton, .solana], stakingData: nil,
            savedAddresses: [contact]
        )
        var tokens = [token.slug: token]
        let input = makeInput(accounts: [snapshot], tokens: tokens, hideUnverified: true)
        tokens.removeAll()

        // The real worker asserts that it is off main, even when invoked from this main-actor test.
        let result = await AgentV2HostContextProvider.makeSnapshot(input: input)
        let captured = try XCTUnwrap(result.accounts.first)
        XCTAssertEqual(result.activeAccountId, account.id)
        XCTAssertEqual(captured.holdings.first?.balance, "1.234")
        XCTAssertEqual(captured.holdings.first?.asset.name, "CapturedToken")
        XCTAssertEqual(captured.holdings.first?.visibility, "visible")
        XCTAssertEqual(captured.positions?.first?.visibility, "hidden")
        XCTAssertEqual(captured.positions?.first?.label, "CapturedNFT")
        XCTAssertEqual(result.savedAddresses.first?.name, "TestContact")
        XCTAssertEqual(captured.savedAddresses, result.savedAddresses)
        XCTAssertEqual(result.assetCatalog?.first?.slug, token.slug)
        XCTAssertEqual(result.currencyRate, "1.25")
        XCTAssertEqual(result.theme, "dark")
        XCTAssertEqual(captured.domainStates?["fungible"]?.state, "fresh")
        // A network the account does not have is left out
        XCTAssertEqual(captured.nftLoadedChains, ["ton"])
        XCTAssertNil(captured.domainStates?["nft"])

        let visible = await AgentV2HostContextProvider.makeSnapshot(input: makeInput(accounts: [snapshot], tokens: input.tokens, hideUnverified: false))
        XCTAssertEqual(visible.accounts.first?.positions?.first?.visibility, "visible")
    }

    func testSnapshotKeepsUnloadedAndLoadedEmptyDomainsDistinct() async throws {
        for isLoaded in [false, true] {
            let account = AgentV2HostContextProvider.AccountSnapshot(
                account: makeAccount(), balances: isLoaded ? [] : nil, assetPreferences: .empty,
                nfts: isLoaded ? [] : nil, nftLoadedChains: isLoaded ? [.ton] : [],
                stakingData: isLoaded ? .init(accountId: makeAccount().id, stateById: [:], totalProfit: 0, shouldUseNominators: nil) : nil,
                savedAddresses: []
            )
            let result = await AgentV2HostContextProvider.makeSnapshot(input: makeInput(accounts: [account]))
            let captured = try XCTUnwrap(result.accounts.first)
            XCTAssertEqual(captured.domainStates?["fungible"]?.state, isLoaded ? "fresh" : "notLoaded")
            XCTAssertEqual(captured.nftLoadedChains, isLoaded ? ["ton"] : [])
            XCTAssertEqual(captured.domainStates?["staking"]?.state, isLoaded ? "fresh" : "notLoaded")
            XCTAssertEqual(captured.portfolioWalletKeys, ["ton:snapshot-address"])
        }
    }

    func testStakingUsesCapturedSwapFallbackAndPrimaryTokenPrecedence() async throws {
        let token = ApiToken(slug: "snapshot-staking-token", name: "Staking", symbol: "SWAP", decimals: 3, chain: .ton)
        let state = ApiStakingState.nominators(.init(
            id: "pool", tokenSlug: token.slug, annualYield: MDouble(4.5), yieldType: .apy,
            balance: 2500, pool: "pool", unstakeRequestAmount: 500, start: 0, end: 0
        ))
        let account = AgentV2HostContextProvider.AccountSnapshot(
            account: makeAccount(), balances: [], assetPreferences: .empty, nfts: [], nftLoadedChains: [],
            stakingData: .init(accountId: makeAccount().id, stateById: ["pool": state], totalProfit: 0, shouldUseNominators: nil),
            savedAddresses: []
        )
        for hasPrimaryToken in [false, true] {
            var primary = token
            primary.symbol = "PRIMARY"
            let input = makeInput(accounts: [account], tokens: hasPrimaryToken ? [token.slug: primary] : [:], swapAssets: [token])
            let result = await AgentV2HostContextProvider.makeSnapshot(input: input)
            let position = try XCTUnwrap(result.accounts.first?.positions?.first)
            XCTAssertEqual(position.quantity, "2.5")
            XCTAssertEqual(position.status, "unstaking")
            XCTAssertEqual(position.apy, "4.5")
            XCTAssertEqual(position.asset?.symbol, hasPrimaryToken ? "PRIMARY" : "SWAP")
        }
    }

    func testSnapshotKeepsStakedBalancesOutOfFungibleHoldings() async throws {
        let token = ApiToken(slug: "snapshot-staking-token", name: "Staking", symbol: "STAKE", decimals: 3, chain: .ton)
        let state = ApiStakingState.nominators(.init(
            id: "pool", tokenSlug: token.slug, annualYield: MDouble(4.5), yieldType: .apy,
            balance: 2500, pool: "pool", unstakeRequestAmount: 0, start: 0, end: 0
        ))
        let stakedBalance = MTokenBalance(tokenSlug: token.slug, balance: 2500, isStaking: true)
        let liquidBalance = MTokenBalance(tokenSlug: token.slug, balance: 1234, isStaking: false)

        for hasLiquidBalance in [false, true] {
            let account = AgentV2HostContextProvider.AccountSnapshot(
                account: makeAccount(),
                balances: hasLiquidBalance ? [stakedBalance, liquidBalance] : [stakedBalance],
                assetPreferences: .empty, nfts: [], nftLoadedChains: [],
                stakingData: .init(accountId: makeAccount().id, stateById: ["pool": state], totalProfit: 0, shouldUseNominators: nil),
                savedAddresses: []
            )
            let result = await AgentV2HostContextProvider.makeSnapshot(input: makeInput(accounts: [account], tokens: [token.slug: token]))
            let captured = try XCTUnwrap(result.accounts.first)

            XCTAssertEqual(captured.holdings.count, hasLiquidBalance ? 1 : 0)
            if hasLiquidBalance {
                let holding = try XCTUnwrap(captured.holdings.first)
                XCTAssertEqual(holding.asset.slug, token.slug)
                XCTAssertEqual(holding.balance, "1.234")
                XCTAssertEqual(holding.availableBalance, "1.234")
            }
            XCTAssertEqual(captured.positions?.count, 1)
            let position = try XCTUnwrap(captured.positions?.first)
            XCTAssertEqual(position.kind, "staking")
            XCTAssertEqual(position.asset?.slug, token.slug)
            XCTAssertEqual(position.quantity, "2.5")
            XCTAssertEqual(captured.domainStates?["fungible"]?.state, "fresh")
            XCTAssertEqual(captured.domainStates?["staking"]?.state, "fresh")
        }
    }

    func testActiveNetworkIsTonWhenPresentElseFirstNetworkInAppOrder() async throws {
        let cases: [([ApiChain], String, [String])] = [
            ([.bitcoin, .ethereum, .ton], "ton", ["bitcoin", "ethereum", "ton"]),
            ([.tron, .solana, .ethereum], "ethereum", ["ethereum", "solana", "tron"]),
        ]
        for (accountChains, activeNetwork, chains) in cases {
            let byChain = Dictionary(uniqueKeysWithValues: accountChains.map { ($0, AccountChain(address: "\($0.rawValue)-address")) })
            let account = AgentV2HostContextProvider.AccountSnapshot(
                account: .init(id: "snapshot-mainnet", title: "Snapshot", type: .view, byChain: byChain),
                balances: [], assetPreferences: .empty, nfts: [], nftLoadedChains: [], stakingData: nil, savedAddresses: []
            )
            let result = await AgentV2HostContextProvider.makeSnapshot(input: makeInput(accounts: [account]))
            XCTAssertEqual(result.activeNetwork, activeNetwork)
            XCTAssertEqual(try XCTUnwrap(result.accounts.first).chains, chains)
        }
    }

    func testCatalogOverItsLimitKeepsItsFirstAssetsBySlug() async throws {
        let slugs = (0...10_000).map { String(format: "token-%05d", $0) }
        let tokens = Dictionary(uniqueKeysWithValues: slugs.map {
            ($0, ApiToken(slug: $0, name: "Token", symbol: "TKN", decimals: 9, chain: .ton))
        })
        let result = await AgentV2HostContextProvider.makeSnapshot(input: makeInput(accounts: [], tokens: tokens, swapAssets: slugs.reversed().map { tokens[$0]! }))
        let catalog = try XCTUnwrap(result.assetCatalog)
        XCTAssertEqual(catalog.count, 10_000)
        XCTAssertEqual(catalog.first?.slug, "token-00000")
        XCTAssertEqual(catalog.last?.slug, "token-09999")
        XCTAssertEqual(result.swapAssetCatalog?.first?.slug, "token-00000")
    }

    private func makeAccount() -> MAccount {
        .init(id: "snapshot-mainnet", title: "Snapshot", type: .view, byChain: [.ton: .init(address: "snapshot-address")])
    }

    private func makeInput(
        accounts: [AgentV2HostContextProvider.AccountSnapshot],
        tokens: [String: ApiToken] = [:],
        swapAssets: [ApiToken]? = nil,
        hideUnverified: Bool = false
    ) -> AgentV2HostContextProvider.SnapshotInput {
        .init(
            activeAccount: accounts.first?.account, accounts: accounts,
            savedAddresses: accounts.first?.savedAddresses ?? [], tokens: tokens, swapAssets: swapAssets,
            areUnverifiedNftsHidden: hideUnverified, lang: "en", baseCurrency: "EUR", currencyRate: 1.25,
            timeZone: "Europe/Belgrade", appVersion: "test", theme: "dark"
        )
    }
}
