import Testing
import WalletCore

@Suite("Subwallet Support")
struct SubwalletSupportTests {
    @Test
    func `single-chain wallets do not support subwallet settings`() {
        let account = makeAccount(chains: [.tron])

        #expect(account.supportsSubwallets(on: .tron) == false)
    }

    @Test
    func `multichain wallets support path-based subwallet settings`() {
        let account = makeAccount(chains: [.ton, .tron])

        #expect(account.supportsSubwallets(on: .tron) == true)
    }

    private func makeAccount(chains: [ApiChain]) -> MAccount {
        MAccount(
            id: "subwallet-support-test-mainnet",
            title: nil,
            type: .mnemonic,
            byChain: Dictionary(uniqueKeysWithValues: chains.map { ($0, AccountChain(address: "\($0.rawValue)-address")) })
        )
    }
}
