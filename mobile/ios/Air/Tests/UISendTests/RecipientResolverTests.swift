import Testing
@testable import UISend
import WalletContext
import WalletCore

@Suite("Send Recipient Resolver")
struct RecipientResolverTests {
    @Test
    func `raw selection trims the draft value`() {
        let selection = RecipientSelection.raw("  recipient  ")

        #expect(selection.address(for: .ton) == "recipient")
    }

    @Test
    func `account selection prefers the active chain`() throws {
        let account = makeAccount(
            tonAddress: "ton-address",
            ethereumAddress: "ethereum-address"
        )
        let selection = RecipientSelection.account(
            account,
            fallbackChain: .ethereum
        )

        #expect(selection.address(for: .ton) == "ton-address")
        #expect(selection.address(for: .solana) == "ethereum-address")
    }

    @Test
    func `saved selection exposes its persistence key`() {
        let selection = RecipientSelection.savedAccount(
            makeAccount(tonAddress: "ton-address"),
            saveKey: "saved-key",
            fallbackChain: .ton
        )

        #expect(selection.savedAddressKey == "saved-key")
    }

    @MainActor
    @Test
    func `selected account replaces the search query until edited`() async {
        let sender = makeAccount(
            id: "sender-mainnet",
            tonAddress: "sender-address"
        )
        let recipient = makeAccount(
            tonAddress: "recipient-address"
        )
        let model = SendRecipientModel(
            account: AccountContext(source: .constant(sender)),
            chain: .ton,
            resolver: RecipientResolverClient { _ in [:] }
        )
        model.textFieldInput = "old search"

        model.selectAccount(recipient, fallbackChain: .ton)
        await Task.yield()

        #expect(model.textFieldInput == "recipient-address")
        #expect(model.draftAddressOrDomain == "recipient-address")

        model.textFieldInput = "manually edited"
        await Task.yield()

        #expect(model.draftAddressOrDomain == "manually edited")
    }

}

private func makeAccount(
    id: String = "recipient-mainnet",
    tonAddress: String? = nil,
    ethereumAddress: String? = nil
) -> MAccount {
    var byChain: [ApiChain: AccountChain] = [:]
    if let tonAddress {
        byChain[.ton] = AccountChain(address: tonAddress)
    }
    if let ethereumAddress {
        byChain[.ethereum] = AccountChain(address: ethereumAddress)
    }
    return MAccount(
        id: id,
        title: "Recipient",
        type: .view,
        byChain: byChain
    )
}
