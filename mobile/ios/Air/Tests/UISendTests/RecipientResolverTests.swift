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

    @MainActor
    @Test
    func `pasted EVM address reports every supported compatible chain`() async throws {
        let address = "0x1111111111111111111111111111111111111111"
        let sender = MAccount(
            id: "sender-mainnet", title: "Sender", type: .view,
            byChain: [
                .ton: AccountChain(address: "sender-ton-address"),
                .ethereum: AccountChain(address: address),
                .bnb: AccountChain(address: address),
            ]
        )
        let model = SendRecipientModel(
            account: AccountContext(source: .constant(sender)),
            chain: .ton,
            resolver: RecipientResolverClient { _ in [:] }
        )
        var detected: [ApiChain] = []
        model.onCompatibleChainsDetected = { detected = $0 }
        model.textFieldInput = address
        try await Task.sleep(for: .milliseconds(50))

        #expect(Set(detected) == Set([ApiChain.ethereum, .bnb]))
    }

    @MainActor
    @Test(arguments: [false, true], [ApiChain.ton, .ethereum])
    func `recipient suggestions preserve their chain until the address is edited`(
        isSavedAddress: Bool,
        initialChain: ApiChain
    ) async throws {
        let address = "0x1111111111111111111111111111111111111111"
        let sender = MAccount(
            id: "sender-mainnet", title: "Sender", type: .view,
            byChain: [
                .ton: AccountChain(address: "sender-ton-address"),
                .ethereum: AccountChain(address: address),
                .bnb: AccountChain(address: address),
            ]
        )
        let model = SendRecipientModel(
            account: AccountContext(source: .constant(sender)),
            chain: initialChain,
            resolver: RecipientResolverClient { _ in [:] }
        )
        var detected: [ApiChain] = []
        model.onCompatibleChainsDetected = {
            detected = $0
            // Simulate the send model preferring a larger BNB balance.
            model.updateChain(.bnb)
        }
        model.onSuggestionChainSelected = { model.updateChain($0) }
        defer {
            model.onCompatibleChainsDetected = { _ in }
            model.onSuggestionChainSelected = { _ in }
        }
        let recipient = makeAccount(ethereumAddress: address)
        if isSavedAddress {
            model.selectSavedAccount(recipient, saveKey: address, fallbackChain: .ethereum)
        } else {
            model.selectAccount(recipient, fallbackChain: .ethereum)
        }
        try await Task.sleep(for: .milliseconds(50))

        #expect(model.chain == .ethereum)
        #expect(model.draftAddressOrDomain == address)
        #expect(detected.isEmpty)

        model.textFieldInput = "0x2222222222222222222222222222222222222222"
        try await Task.sleep(for: .milliseconds(50))

        #expect(Set(detected) == Set([ApiChain.ethereum, .bnb]))
        #expect(model.chain == .bnb)
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
