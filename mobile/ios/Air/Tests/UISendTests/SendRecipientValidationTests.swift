import Testing
import WalletCore
@testable import UISend

@Suite("Send recipient validation")
struct SendRecipientValidationTests {
    private let ethereumAddress =
        "0x1111111111111111111111111111111111111111"

    @Test("empty and focused inputs do not show errors")
    func editingExemptions() {
        #expect(evaluate(input: "") == nil)
        #expect(evaluate(input: "not-an-address", isFocused: true) == nil)
    }

    @Test("invalid and incompatible addresses are distinguished")
    func validationKinds() {
        #expect(evaluate(input: "not-an-address") == .invalid)
        #expect(
            evaluate(
                input: ethereumAddress,
                showsIncompatibleError: true
            ) == .incompatible
        )
    }

    @Test("automatic token selection suppresses compatibility errors")
    func automaticSelectionExemption() {
        #expect(
            evaluate(
                input: ethereumAddress,
                showsIncompatibleError: false
            ) == nil
        )
    }

    @Test("a current draft ends the automatic selection grace period")
    func completedDraftEndsAutomaticSelectionGracePeriod() {
        #expect(
            !TokenSelectionSource.automatic
                .shouldShowIncompatibleRecipientError(
                    hasCurrentDraft: false
                )
        )
        #expect(
            TokenSelectionSource.automatic
                .shouldShowIncompatibleRecipientError(
                    hasCurrentDraft: true
                )
        )
        #expect(
            TokenSelectionSource.user
                .shouldShowIncompatibleRecipientError(
                    hasCurrentDraft: false
                )
        )
    }

    @Test("current-chain draft address errors remain invalid")
    func draftError() {
        let tonAddress = String(repeating: "A", count: 48)
        let validatedRecipient = SendValidatedRecipient(
            resolvedAddress: nil,
            addressName: nil,
            isScam: false,
            error: .domainNotResolved
        )

        #expect(
            evaluate(
                input: tonAddress,
                validatedRecipient: validatedRecipient
            ) == .invalid
        )
    }

    @Test("self-transfers have a separate error on every chain except TON", arguments: ApiChain.allCases)
    func selfTransfer(chain: ApiChain) {
        let address = chain.feeCheckAddress
        let expected: SendRecipientValidationState? = chain == .ton ? nil : .sendToSelf

        #expect(
            evaluate(
                input: address,
                activeChain: chain,
                senderAddress: address
            ) == expected
        )
        #expect(
            SendRecipientPolicy.flexibleChain(suggestions: .all)
                .isRecipientCompatible(
                    input: address,
                    resolvedAddress: nil,
                    senderAddress: address,
                    activeChain: chain
                ) == (chain == .ton)
        )
        #expect(
            evaluate(
                input: address,
                isFocused: true,
                activeChain: chain,
                senderAddress: address
            ) == nil
        )
    }

    @Test("resolved self-transfers stay distinct from invalid addresses")
    func resolvedSelfTransfer() {
        let address = ApiChain.bitcoin.feeCheckAddress
        let validatedRecipient = SendValidatedRecipient(
            resolvedAddress: address,
            addressName: nil,
            isScam: false,
            error: .insufficientBalance
        )

        #expect(
            evaluate(
                input: "  \(address)  ",
                activeChain: .bitcoin,
                senderAddress: address,
                validatedRecipient: validatedRecipient
            ) == .sendToSelf
        )
        #expect(
            evaluate(
                input: ethereumAddress,
                activeChain: .ethereum,
                senderAddress: "0x2222222222222222222222222222222222222222"
            ) == nil
        )
    }

    private func evaluate(
        input: String,
        isFocused: Bool = false,
        activeChain: ApiChain = .ton,
        senderAddress: String? = nil,
        validatedRecipient: SendValidatedRecipient? = nil,
        showsIncompatibleError: Bool = true
    ) -> SendRecipientValidationState? {
        SendRecipientValidationState.evaluate(
            input: input,
            isFocused: isFocused,
            activeChain: activeChain,
            senderAddress: senderAddress,
            validatedRecipient: validatedRecipient,
            showsIncompatibleError: showsIncompatibleError
        )
    }
}
