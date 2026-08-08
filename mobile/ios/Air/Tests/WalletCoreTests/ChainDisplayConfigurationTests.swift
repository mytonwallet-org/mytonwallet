import Foundation
import Testing
import WalletCore

@Suite("Chain Display Configuration")
struct ChainDisplayConfigurationTests {
    @Test
    func `missing configuration uses automatic visibility and value order`() {
        let data = MAssetsAndActivityData.empty
        let chains: [ApiChain] = [.ton, .tron, .solana]

        #expect(data.chainDisplayConfiguration == nil)
        #expect(data.chainDisplayMode == .value)
        #expect(data.visibleChains(
            defaultOrder: chains,
            valueOrder: [.solana, .ton, .tron],
            automaticallyVisibleChains: [.ton, .solana]
        ) == [.solana, .ton])
    }

    @Test
    func `automatic order keeps visible zero value chains ahead of hidden chains`() {
        let configuration = MChainDisplayConfiguration()
        let defaultOrder: [ApiChain] = [.ton, .tron, .solana, .base, .bnb]
        let valueOrder: [ApiChain] = [.tron, .ton, .solana, .base, .bnb]

        #expect(configuration.orderedChains(
            defaultOrder: defaultOrder,
            valueOrder: valueOrder,
            automaticallyVisibleChains: [.ton, .tron, .base]
        ) == [.tron, .ton, .base, .solana, .bnb])
        #expect(configuration.visibleChains(
            defaultOrder: defaultOrder,
            valueOrder: valueOrder,
            automaticallyVisibleChains: [.ton, .tron, .base]
        ) == [.tron, .ton, .base])
    }

    @Test
    func `empty wallet automatically shows all chains`() {
        #expect(MChainDisplayConfiguration.automaticallyVisibleChains(
            defaultOrder: [.ton, .tron, .solana],
            chainsWithBalance: [],
            hasTokenBalance: false,
            isGramWallet: false
        ) == [.ton, .tron, .solana])
    }

    @Test
    func `empty gram wallet automatically shows only ton`() {
        #expect(MChainDisplayConfiguration.automaticallyVisibleChains(
            defaultOrder: [.ethereum, .ton, .tron],
            chainsWithBalance: [],
            hasTokenBalance: false,
            isGramWallet: true
        ) == [.ton])
    }

    @Test
    func `nonempty wallet automatically shows only funded chains`() {
        #expect(MChainDisplayConfiguration.automaticallyVisibleChains(
            defaultOrder: [.ton, .tron, .solana],
            chainsWithBalance: [.tron, .ethereum],
            hasTokenBalance: true,
            isGramWallet: false
        ) == [.tron])
    }

    @Test
    func `manual mode stores only visibility differences from automatic mode`() {
        var data = MAssetsAndActivityData.empty
        data.saveChainDisplayMode(.manual, capturing: [.solana, .ton, .tron])
        data.saveChainVisible(.ton, isVisible: false, automaticallyVisible: true)
        data.saveChainVisible(.tron, isVisible: true, automaticallyVisible: false)

        #expect(data.hiddenChains == [.ton])
        #expect(data.shownChains == [.tron])
        #expect(data.chainDisplayConfiguration?.manualOrder == [.solana, .tron])
        #expect(data.visibleChains(
            defaultOrder: [.ton, .tron, .solana],
            valueOrder: [.ton, .solana, .tron],
            automaticallyVisibleChains: [.ton, .solana]
        ) == [.solana, .tron])

        data.saveChainVisible(.ton, isVisible: true, automaticallyVisible: true)
        data.saveChainVisible(.tron, isVisible: false, automaticallyVisible: false)
        #expect(data.hiddenChains.isEmpty)
        #expect(data.shownChains.isEmpty)
    }

    @Test
    func `manual mode automatically enables a newly funded chain`() {
        let configuration = MChainDisplayConfiguration(
            displayMode: .manual,
            hiddenChains: [.tron],
            manualOrder: [.solana, .ton, .tron]
        )

        #expect(
            configuration.visibleChains(
                defaultOrder: [.ton, .tron, .solana, .ethereum],
                valueOrder: [.ethereum, .ton, .tron, .solana],
                automaticallyVisibleChains: [.ton, .ethereum]
            ) == [.ton, .ethereum]
        )
    }

    @Test
    func `future chains missing from partial manual order are appended in default order`() {
        let configuration = MChainDisplayConfiguration(
            displayMode: .manual,
            manualOrder: [.solana, .ton]
        )

        #expect(configuration.orderedChains(
            defaultOrder: [.ton, .tron, .solana, .ethereum],
            valueOrder: [.ethereum, .tron, .ton, .solana],
            automaticallyVisibleChains: [.ton, .tron, .solana, .ethereum]
        ) == [.solana, .ton, .tron, .ethereum])
    }

    @Test
    func `manual order contains visible chains only and disabled chains use value order`() {
        let configuration = MChainDisplayConfiguration(
            displayMode: .manual,
            hiddenChains: [.solana],
            shownChains: [.base],
            manualOrder: [.solana, .tron, .bnb, .ton, .base]
        )

        #expect(configuration.normalizedManualOrder(
            defaultOrder: [.ton, .tron, .solana, .base, .bnb, .ethereum],
            automaticallyVisibleChains: [.ton, .tron]
        ) == [.tron, .ton, .base])
        #expect(configuration.orderedChains(
            defaultOrder: [.ton, .tron, .solana, .base, .bnb, .ethereum],
            valueOrder: [.bnb, .base],
            automaticallyVisibleChains: [.ton, .tron]
        ) == [.tron, .ton, .base, .bnb, .solana, .ethereum])
    }

    @Test
    func `disabling a chain removes it from manual order`() {
        var configuration = MChainDisplayConfiguration(
            displayMode: .manual,
            manualOrder: [.tron, .ton, .solana]
        )

        configuration.setVisible(.ton, isVisible: false, automaticallyVisible: true)

        #expect(configuration.manualOrder == [.tron, .solana])
    }

    @Test
    func `reordering all rows persists only visible relative order`() {
        var configuration = MChainDisplayConfiguration(
            displayMode: .manual,
            hiddenChains: [.ton],
            shownChains: [.base]
        )

        configuration.setManualOrder(
            [.solana, .ton, .base, .tron],
            automaticallyVisibleChains: [.solana, .ton]
        )

        #expect(configuration.manualOrder == [.solana, .base])
        #expect(configuration.orderedChains(
            defaultOrder: [.ton, .tron, .solana, .base],
            valueOrder: [.tron, .ton, .base, .solana],
            automaticallyVisibleChains: [.solana, .ton]
        ) == [.solana, .base, .tron, .ton])
    }

    @Test
    func `automatic mode ignores preserved manual choices`() {
        let configuration = MChainDisplayConfiguration(
            displayMode: .value,
            hiddenChains: [.ton],
            shownChains: [.tron],
            manualOrder: [.tron, .ton, .solana]
        )

        #expect(configuration.visibleChains(
            defaultOrder: [.ton, .tron, .solana],
            valueOrder: [.solana, .ton, .tron],
            automaticallyVisibleChains: [.ton, .solana]
        ) == [.solana, .ton])
    }

    @Test
    func `switching modes can preserve a prior manual order`() {
        var configuration = MChainDisplayConfiguration(
            displayMode: .manual,
            manualOrder: [.solana, .ton, .tron]
        )

        configuration.setDisplayMode(.value)
        configuration.setDisplayMode(.manual)

        #expect(configuration.orderedChains(
            defaultOrder: [.ton, .tron, .solana],
            valueOrder: [.tron, .ton, .solana],
            automaticallyVisibleChains: [.ton, .tron, .solana]
        ) == [.solana, .ton, .tron])
    }

    @Test
    func `duplicate and conflicting overrides are normalized`() {
        let configuration = MChainDisplayConfiguration(
            displayMode: .manual,
            hiddenChains: [.tron, .tron],
            shownChains: [.tron, .solana, .solana],
            manualOrder: [.solana, .ton, .solana]
        )

        #expect(configuration.hiddenChains == [.tron])
        #expect(configuration.shownChains == [.solana])
        #expect(configuration.manualOrder == [.solana, .ton])
    }

    @Test
    func `explicit receive chain remains visible`() {
        let configuration = MChainDisplayConfiguration(
            displayMode: .manual,
            hiddenChains: [.tron]
        )

        #expect(
            configuration.visibleChains(
                defaultOrder: [.ton, .tron, .solana],
                valueOrder: [.solana, .ton, .tron],
                automaticallyVisibleChains: [.ton],
                including: .tron
            ) == [.ton, .tron]
        )
    }

    @Test
    func `invalid all hidden state keeps a fallback chain visible`() {
        let configuration = MChainDisplayConfiguration(
            displayMode: .manual,
            hiddenChains: [.ton, .tron]
        )

        #expect(configuration.visibleChains(
            defaultOrder: [.ton, .tron],
            valueOrder: [.tron, .ton],
            automaticallyVisibleChains: [.ton, .tron]
        ) == [.ton])
    }

    @Test
    func `empty available chain list remains empty`() {
        let configuration = MChainDisplayConfiguration(displayMode: .manual, hiddenChains: [.ton])

        #expect(configuration.visibleChains(
            defaultOrder: [],
            valueOrder: [.ton],
            automaticallyVisibleChains: [.ton]
        ) == [])
    }

    @Test
    func `configuration decoder defaults missing fields`() throws {
        let configuration = try JSONDecoder().decode(
            MChainDisplayConfiguration.self,
            from: Data("{}".utf8)
        )

        #expect(configuration == MChainDisplayConfiguration())
    }

    @Test
    func `configuration decoder ignores unshipped boolean mode`() throws {
        let configuration = try JSONDecoder().decode(
            MChainDisplayConfiguration.self,
            from: Data(#"{"sortByValue":false}"#.utf8)
        )

        #expect(configuration.displayMode == .value)
    }

    @Test
    func `configuration decoder ignores future fields`() throws {
        let configuration = try JSONDecoder().decode(
            MChainDisplayConfiguration.self,
            from: Data(#"{"displayMode":"manual","shownChains":["tron"],"futureField":true}"#.utf8)
        )

        #expect(configuration == MChainDisplayConfiguration(displayMode: .manual, shownChains: [.tron]))
    }

    @Test
    func `legacy hidden chains migrate to manual mode`() throws {
        let configuration = try JSONDecoder().decode(
            MChainDisplayConfiguration.self,
            from: Data(#"{"hiddenChains":["tron"]}"#.utf8)
        )

        #expect(configuration == MChainDisplayConfiguration(displayMode: .manual, hiddenChains: [.tron]))
    }

    @Test
    func `database row preserves chain configuration`() {
        var data = MAssetsAndActivityData.empty
        data.saveChainDisplayMode(.manual, capturing: [.ton, .monad])
        data.saveChainVisible(.monad, isVisible: false, automaticallyVisible: true)

        let row = MAccountAssetsAndActivityData(accountId: "test-mainnet", data: data)

        #expect(row.chainDisplayConfiguration == data.chainDisplayConfiguration)
        #expect(row.data == data)
        #expect(row.hasData)
    }

    @Test
    func `share link omits hidden non evm chains`() {
        let account = makeShareLinkAccount()
        let configuration = MChainDisplayConfiguration(displayMode: .manual, hiddenChains: [.tron])
        let visibleChains = visibleChains(configuration: configuration, account: account)
        let values = queryValues(in: account.shareLink(visibleChains: Set(visibleChains)))

        #expect(values[ApiChain.ton.rawValue] == "ton-address")
        #expect(values[ApiChain.tron.rawValue] == nil)
        #expect(values[ApiChain.solana.rawValue] == "solana-address")
        #expect(values[ApiChain.viewAccountEvmParam] == "0x1234")
    }

    @Test
    func `share link omits evm parameter when every evm chain is hidden`() {
        let account = makeShareLinkAccount()
        let configuration = MChainDisplayConfiguration(displayMode: .manual, hiddenChains: ApiChain.evmChains)
        let visibleChains = visibleChains(configuration: configuration, account: account)
        let values = queryValues(in: account.shareLink(visibleChains: Set(visibleChains)))

        #expect(values[ApiChain.viewAccountEvmParam] == nil)
        for chain in ApiChain.evmChains {
            #expect(values[chain.rawValue] == nil)
        }
    }

    @Test
    func `one visible evm chain keeps one coalesced evm parameter`() {
        let account = makeShareLinkAccount()
        let configuration = MChainDisplayConfiguration(
            displayMode: .manual,
            hiddenChains: ApiChain.evmChains.filter { $0 != .base }
        )
        let visibleChains = visibleChains(configuration: configuration, account: account)
        let queryItems = URLComponents(
            url: account.shareLink(visibleChains: Set(visibleChains)),
            resolvingAgainstBaseURL: false
        )?.queryItems ?? []

        #expect(queryItems.filter { $0.name == ApiChain.viewAccountEvmParam }.count == 1)
        #expect(queryItems.first { $0.name == ApiChain.viewAccountEvmParam }?.value == "0x1234")
        #expect(queryItems.allSatisfy { $0.name != ApiChain.base.rawValue })
    }

    private func visibleChains(configuration: MChainDisplayConfiguration, account: MAccount) -> [ApiChain] {
        let chains = account.orderedChains.map(\.0)
        return configuration.visibleChains(
            defaultOrder: chains,
            valueOrder: chains,
            automaticallyVisibleChains: Set(chains)
        )
    }

    private func makeShareLinkAccount() -> MAccount {
        var byChain: [ApiChain: AccountChain] = [
            .ton: AccountChain(address: "ton-address"),
            .tron: AccountChain(address: "tron-address"),
            .solana: AccountChain(address: "solana-address"),
        ]
        for chain in ApiChain.evmChains {
            byChain[chain] = AccountChain(address: "0x1234")
        }
        return MAccount(
            id: "share-link-test-mainnet",
            title: nil,
            type: .mnemonic,
            byChain: byChain
        )
    }

    private func queryValues(in url: URL) -> [String: String] {
        let queryItems = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        return Dictionary(uniqueKeysWithValues: queryItems.compactMap { item in
            item.value.map { (item.name, $0) }
        })
    }
}
