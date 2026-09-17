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
            nfts: [.init(nft: nft, isHiddenByUser: false)], stakingData: nil, savedAddresses: [contact]
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
        XCTAssertEqual(captured.domainStates?["positions"]?.state, "fresh")

        let visible = await AgentV2HostContextProvider.makeSnapshot(input: makeInput(accounts: [snapshot], tokens: input.tokens, hideUnverified: false))
        XCTAssertEqual(visible.accounts.first?.positions?.first?.visibility, "visible")
    }

    func testSnapshotKeepsUnloadedAndLoadedEmptyDomainsDistinct() async throws {
        for isLoaded in [false, true] {
            let account = AgentV2HostContextProvider.AccountSnapshot(
                account: makeAccount(), balances: isLoaded ? [] : nil, assetPreferences: .empty,
                nfts: isLoaded ? [] : nil,
                stakingData: isLoaded ? .init(accountId: makeAccount().id, stateById: [:], totalProfit: 0, shouldUseNominators: nil) : nil,
                savedAddresses: []
            )
            let result = await AgentV2HostContextProvider.makeSnapshot(input: makeInput(accounts: [account]))
            let captured = try XCTUnwrap(result.accounts.first)
            XCTAssertEqual(captured.domainStates?["positions"]?.state, isLoaded ? "fresh" : "notLoaded")
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
            account: makeAccount(), balances: [], assetPreferences: .empty, nfts: [],
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
