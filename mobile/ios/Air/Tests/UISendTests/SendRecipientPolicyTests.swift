import Testing
import WalletCore
@testable import UISend

@Suite("Send recipient policy")
struct SendRecipientPolicyTests {
    @Test("token flow can resolve and select another compatible chain")
    func tokenFlowCanChangeChain() {
        let policy = SendRecipientPolicy.flexibleChain(
            suggestions: .preferActiveChain
        )

        #expect(
            policy.resolutionChains(
                from: [.ton, .tron, .solana]
            ) == [.ton, .tron, .solana]
        )
        #expect(policy.shouldSelectChain(.solana, activeChain: .ton))
        #expect(!policy.shouldSelectChain(.ton, activeChain: .ton))
    }

    @Test("NFT flow fixes resolution and selection to its NFT chain")
    func nftFlowFixesChain() {
        let policy = SendRecipientPolicy.fixedChain(.solana)

        #expect(
            policy.resolutionChains(
                from: [.ton, .solana]
            ) == [.solana]
        )
        #expect(
            policy.resolutionChains(
                from: [.ton]
            ).isEmpty
        )
        #expect(!policy.shouldSelectChain(.ton, activeChain: .solana))
        #expect(policy.suggestionStrategy == .requireActiveChain)
    }

    @Test("user token selection changes flexible suggestions to prefer active chain")
    func userTokenSelectionPrefersActiveChain() {
        let policy = SendRecipientPolicy.flexibleChain(
            suggestions: .all
        )

        #expect(
            policy.preferringActiveChain()
                == .flexibleChain(suggestions: .preferActiveChain)
        )
    }
}
