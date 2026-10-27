import Dependencies
import Testing
import WalletCore

@Suite("Address Line Display")
struct AddressLineDisplayTests {
    @Test
    func `display items cap chains and keep one icon only item`() {
        let addressLine = makeAddressLine(chains: [.ethereum, .solana, .ton, .tron, .bnb])
        let displayItems = addressLine.displayItems(maxChainCount: 3, multichainAddressCount: 2)

        #expect(displayItems.map { $0.item.chain } == [.ethereum, .solana, .ton])
        #expect(displayItems.map(\.showsAddress) == [true, true, false])
        #expect(displayItems.map { $0.item.isLast } == [false, false, true])
    }

    @Test
    func `display items can show one address and two icon only chains`() {
        let addressLine = makeAddressLine(chains: [.ton, .ethereum, .solana, .bnb])
        let displayItems = addressLine.displayItems(maxChainCount: 3, multichainAddressCount: 1)

        #expect(displayItems.map { $0.item.chain } == [.ton, .ethereum, .solana])
        #expect(displayItems.map(\.showsAddress) == [true, false, false])
        #expect(displayItems.map { $0.item.isLast } == [false, false, true])
    }

    @Test
    func `single visible chain always shows address`() {
        let addressLine = makeAddressLine(chains: [.ton])
        let displayItems = addressLine.displayItems(maxChainCount: 3, multichainAddressCount: 0)

        #expect(displayItems.map { $0.item.chain } == [.ton])
        #expect(displayItems.map(\.showsAddress) == [true])
        #expect(displayItems.map { $0.item.isLast } == [true])
    }

    @Test
    func `gram wallet with no token chains shows only ton address`() {
        let orderedChains = makeOrderedChains([.ethereum, .ton, .solana])
        let account = makeAccount(chains: [.ethereum, .ton, .solana])
        let addressLine = account.addressLine(orderedChains: orderedChains, tokenChains: [], isGramWallet: true)

        #expect(addressLine.items.map(\.chain) == [.ton])
    }

    @Test
    func `gram wallet with only ton token chains shows only ton address`() {
        let orderedChains = makeOrderedChains([.ethereum, .ton, .solana])
        let account = makeAccount(chains: [.ethereum, .ton, .solana])
        let addressLine = account.addressLine(orderedChains: orderedChains, tokenChains: [.ton], isGramWallet: true)

        #expect(addressLine.items.map(\.chain) == [.ton])
    }

    @Test
    func `gram wallet with non ton token chains keeps ordered chains`() {
        let orderedChains = makeOrderedChains([.ethereum, .ton, .solana])
        let account = makeAccount(chains: [.ethereum, .ton, .solana])
        let addressLine = account.addressLine(orderedChains: orderedChains, tokenChains: [.ton, .ethereum], isGramWallet: true)

        #expect(addressLine.items.map(\.chain) == [.ethereum, .ton, .solana])
    }

    @Test
    func `non gram wallet keeps ordered chains when token chains are empty`() {
        let orderedChains = makeOrderedChains([.ethereum, .ton, .solana])
        let account = makeAccount(chains: [.ethereum, .ton, .solana])
        let addressLine = account.addressLine(orderedChains: orderedChains, tokenChains: [], isGramWallet: false)

        #expect(addressLine.items.map(\.chain) == [.ethereum, .ton, .solana])
    }

    @MainActor @Test
    func walletRowShowsOneAddressWithoutReducingTheAddressMenu() {
        withDependencies {
            $0.context = .live
            $0.accountStore = .shared
            $0.balancesStore = .liveValue
            $0.stakingStore = .liveValue
            $0.assetsAndActivityDataStore = .shared
            $0[_TokenStore.self] = TokenStore
        } operation: {
            withDependencies {
                $0.balanceDataStore = .shared
            } operation: {
                let account = MAccount(id: "single-address-mainnet", title: nil, type: .view, byChain: [
                    .ton: AccountChain(address: "ton-address"),
                    .ethereum: AccountChain(address: "0x1234"),
                    .tron: AccountChain(address: "tron-address"),
                ])
                let context = AccountContext(source: .constant(account))
                let menuChains = context.displayedChains.map(\.0)
                let mainAddress = context.topAddressLine

                #expect(mainAddress.items.count == 1)
                #expect(mainAddress.items.first?.chain == menuChains.first)
                #expect(mainAddress.items.first?.isLast == true)
                #expect(mainAddress.leadingIcon == .view)
                #expect(Set(context.displayedChains.map(\.0)) == [.ton, .ethereum, .tron])
                #expect(context.addressLine.items.count == 3)
            }
        }
    }

    @MainActor @Test
    func operationAddressUsesTheRequestedChainAndPreservesDomainAndBadges() {
        withDependencies { $0.context = .live } operation: {
            let account = MAccount(id: "operation-address-testnet", title: nil, type: .hardware, byChain: [
                .ton: AccountChain(address: "ton-address"),
                .ethereum: AccountChain(address: "0x1234", domain: "wallet.eth"),
                .tron: AccountChain(address: "tron-address"),
            ])
            let context = AccountContext(source: .constant(account))
            let ethereumLine = context.addressLine(for: .ethereum)

            #expect(ethereumLine.items.map(\.chain) == [.ethereum])
            #expect(ethereumLine.items.first?.text == "wallet.eth")
            #expect(ethereumLine.items.first?.textToCopy == "wallet.eth")
            #expect(ethereumLine.items.first?.isDomain == true)
            #expect(ethereumLine.leadingIcon == .ledger)
            #expect(ethereumLine.isTestnet)
            #expect(context.addressLine(for: .tron).items.map(\.chain) == [.tron])
            #expect(context.addressLine(for: .solana).items.isEmpty)
        }
    }

    private func makeAddressLine(chains: [ApiChain]) -> MAccount.AddressLine {
        let account = makeAccount(chains: chains)
        return account.addressLine(orderedChains: makeOrderedChains(chains), isGramWallet: false)
    }

    private func makeAccount(chains: [ApiChain]) -> MAccount {
        MAccount(
            id: "address-line-test-mainnet",
            title: nil,
            type: .mnemonic,
            byChain: Dictionary(uniqueKeysWithValues: chains.map { ($0, AccountChain(address: "\($0.rawValue)-address")) })
        )
    }

    private func makeOrderedChains(_ chains: [ApiChain]) -> [(ApiChain, AccountChain)] {
        chains.map { ($0, AccountChain(address: "\($0.rawValue)-address")) }
    }
}
