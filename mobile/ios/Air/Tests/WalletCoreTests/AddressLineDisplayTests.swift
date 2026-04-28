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
