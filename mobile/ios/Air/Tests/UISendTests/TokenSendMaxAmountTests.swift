import Dependencies
import Foundation
import Testing
@testable import UISend
import WalletContext
@testable import WalletCore
import WalletResources

@Suite("Send maximum amount")
@MainActor
struct TokenSendMaxAmountTests {
    init() { _ = WalletResourcesBundle.bundle.load() }

    @Test
    func `a request for everything fills the maximum once the balance loads`() async throws {
        let accountId = "sendmax\(UUID().uuidString.replacingOccurrences(of: "-", with: ""))-mainnet"
        let store = _BalancesStore.liveValue
        let balances = store.for(accountId: accountId)
        let model = withDependencies {
            $0[_TokenStore.self] = TokenStore
            $0[_BalancesStore.self] = store
        } operation: {
            TokenSendModel(
                accountContext: AccountContext(source: .constant(MAccount(
                    id: accountId, title: nil, type: .mnemonic,
                    byChain: [.ton: AccountChain(address: String(repeating: "B", count: 48))]
                ))),
                configuration: .init(
                    mode: .send, initialAddress: nil, initialAmount: nil, isMaxAmount: true,
                    initialTokenSlug: TONCOIN_SLUG, jettonAddress: nil, initialComment: "",
                    binaryPayload: nil, stateInit: nil
                ),
                flow: TokenSendFlow(api: .init(
                    checkDraft: { _, _ in throw CancellationError() },
                    submit: { _, _ in throw CancellationError() }
                )),
                recipientResolver: .init { _ in [:] }
            )
        }
        defer { model.draft.pause() }
        #expect(model.amount == nil)

        balances.replaceAll(byChain: [.ton: [TONCOIN_SLUG: 5_000_000_000]])

        let deadline = ContinuousClock.now + .seconds(3)
        while model.amount != 5_000_000_000 {
            try #require(ContinuousClock.now < deadline, "Timed out waiting for the maximum amount")
            try await Task.sleep(for: .milliseconds(5))
        }
    }
}
