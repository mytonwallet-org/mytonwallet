import Foundation
import Perception
import SwiftNavigation
import UIComponents
import WalletContext
import WalletCore

typealias NftSendDraftSnapshot = OperationDraftSnapshot<
    NftSendDraftRequest,
    NftSendValidatedDraft
>

extension OperationDraftSnapshot
where Request == NftSendDraftRequest, Draft == NftSendValidatedDraft {
    var isAccepted: Bool {
        draft.recipient.error == nil
    }
}

@Perceptible @MainActor
final class NftSendModel: Sendable {
    @PerceptionIgnored
    @AccountContext var account: MAccount

    let configuration: NftSendConfiguration
    let recipient: SendRecipientModel
    private var sanitizedComment: String

    @PerceptionIgnored
    let flow: NftSendFlow
    @PerceptionIgnored
    @TokenProvider var feeToken: ApiToken
    @PerceptionIgnored
    private var observers: [ObserveToken] = []
    @PerceptionIgnored
    var onDraftFailure: ((any Error) -> Void)?
    @PerceptionIgnored
    let draft: DraftEngine<NftSendDraftRequest, NftSendValidatedDraft>

    var didConfirmDomainScamWarning = false

    init(
        accountContext: AccountContext,
        configuration: NftSendConfiguration,
        flow: NftSendFlow = NftSendFlow(),
        recipientResolver: RecipientResolverClient = .live
    ) {
        self._account = accountContext
        self.configuration = configuration
        self.flow = flow
        self.draft = DraftEngine(
            debounce: { from, to in
                // Typed address and comment transitions debounce; the
                // first request and account switches load immediately.
                guard let from,
                      from.accountId == to.accountId else {
                    return .zero
                }
                return .milliseconds(250)
            },
            sameScope: { lhs, rhs in
                lhs.accountId == rhs.accountId
                    && lhs.chain == rhs.chain
                    && lhs.nfts == rhs.nfts
                    && lhs.mode == rhs.mode
            },
            load: { [flow] request, _ in
                try await flow.validateDraft(request)
            }
        )

        self.sanitizedComment = TransferPayloadPolicy.sanitizeComment(
            configuration.initialComment
        )
        self._feeToken = TokenProvider(
            tokenSlug: configuration.chain.nativeToken.slug
        )
        self.recipient = SendRecipientModel(
            account: accountContext,
            chain: configuration.chain,
            recipientPolicy: .fixedChain(configuration.chain),
            resolver: recipientResolver
        )

        if configuration.mode == .send,
           let address = configuration.initialAddress {
            recipient.textFieldInput = address
        }
        recipient.onScanResult = { [weak self] result in
            self?.applyScanResult(result)
        }
        draft.onFailure = { [weak self] _, error in
            self?.onDraftFailure?(error)
        }

        setupObservers()
        draft.start { [weak self] in
            self?.currentDraftRequest
        }
    }

    var comment: String {
        get { sanitizedComment }
        set {
            let value = TransferPayloadPolicy.sanitizeComment(newValue)
            guard value != sanitizedComment else { return }
            sanitizedComment = value
            didConfirmDomainScamWarning = false
        }
    }

    var addressOrDomain: String {
        recipient.draftAddressOrDomain
    }

    var activeChain: ApiChain {
        configuration.chain
    }

    var currentDraftRequest: NftSendDraftRequest? {
        guard !configuration.nfts.isEmpty,
              configuration.mode == .burn
                || !addressOrDomain.isEmpty else {
            return nil
        }
        return NftSendDraftRequest(
            accountId: account.id,
            address: addressOrDomain,
            chain: configuration.chain,
            nfts: configuration.nfts,
            comment: draftComment,
            mode: configuration.mode
        )
    }

    var currentDraftSnapshot: NftSendDraftSnapshot? {
        draft.current
    }

    var currentValidatedDraft: NftSendValidatedDraft? {
        draft.current?.draft
    }

    var isDraftLoading: Bool {
        draft.isLoading
    }

    var addressViewModel: AddressViewModel {
        recipient.makeAddressViewModel(
            validatedRecipient: currentValidatedDraft?.recipient
        )
    }

    var isCommentRequired: Bool {
        currentValidatedDraft?.requiresMemo ?? false
    }

    var resolvedAddress: String? {
        currentValidatedDraft?.recipient.resolvedAddress
    }

    var isRecipientCompatible: Bool {
        configuration.mode == .burn
            || recipient.isCompatible(resolvedAddress: resolvedAddress)
    }

    var isRecipientInvalid: Bool {
        isSendAddressDraftError(
            currentValidatedDraft?.recipient.error
        )
    }

    var recipientValidationState: SendRecipientValidationState? {
        recipient.validationState(
            validatedRecipient: currentValidatedDraft?.recipient,
            showsIncompatibleError: true
        )
    }

    var balanceStatus: SendBalanceStatus {
        let nativeBalance = $account.balances[feeToken.slug]
        return SendBalancePolicy.evaluate(
            tokenBalance: nativeBalance,
            tokenSlug: feeToken.slug,
            nativeTokenBalance: nativeBalance,
            transferAmount: 0,
            fullFee:
                currentValidatedDraft?.explainedFee?.fullFee?.terms,
            canTransferFullBalance: false,
            draftError: currentValidatedDraft?.recipient.error
        )
    }

    var hasInsufficientBalanceError: Bool {
        balanceStatus.isInsufficient
    }

    var canContinue: Bool {
        guard currentDraftSnapshot?.isAccepted == true else {
            return false
        }
        return canAttemptContinue && resolvedAddress != nil
    }

    var canAttemptContinue: Bool {
        (configuration.mode == .burn || !addressOrDomain.isEmpty)
            && isRecipientCompatible
            && !hasInsufficientBalanceError
            && !isRequiredCommentMissing
            && !configuration.nfts.isEmpty
            && !shouldShowMultisigWarning
    }

    var primaryAction: NftSendPrimaryAction {
        if draft.canRetry {
            return .retryDraft
        }
        if recipientValidationState == .sendToSelf {
            return .invalidAddress
        }
        if (isRecipientInvalid || !isRecipientCompatible), !addressOrDomain.isEmpty {
            return .invalidAddress
        }
        if hasInsufficientBalanceError {
            return .insufficientBalance
        }
        if isDraftLoading {
            return .validating
        }
        if canContinue {
            return .continueToReview
        }
        return .incomplete
    }

    var isAllowSuspiciousActions: Bool {
        $account.settings.isAllowSuspiciousActions
    }

    var shouldConfirmDomainScamWarning: Bool {
        shouldShowDomainScamWarning && !didConfirmDomainScamWarning
    }

    var isScamRecipient: Bool {
        currentValidatedDraft?.recipient.isScam == true
    }

    var shouldShowMultisigWarning: Bool {
        account.getChainInfo(chain: activeChain)?.isMultisig == true
    }

    var shouldShowDomainScamWarning: Bool {
        recipient.shouldShowDomainScamWarning(
            draftError: currentValidatedDraft?.recipient.error
        )
    }

    var showingFee: MFee? {
        let explainedFee = draft.displayed?.explainedFee
        let fullFee = explainedFee?.fullFee
        let fullNativeFee = fullFee?.nativeSum
        let nativeBalance = $account.balances[feeToken.slug] ?? 0
        if let fullNativeFee, fullNativeFee > nativeBalance {
            return fullFee
        }
        return explainedFee?.realFee
    }

    var isTransferPayloadAvailable: Bool {
        payloadPolicy.availability.isVisible
    }

    func confirmDomainScamWarning() {
        didConfirmDomainScamWarning = true
    }

    func retryDraft() {
        draft.retry()
    }

    func makeConfirmedSend() throws -> ConfirmedNftSend {
        guard let snapshot = currentDraftSnapshot,
              snapshot.isAccepted else {
            throw DisplayError(text: lang("Transaction is not ready"))
        }
        return ConfirmedNftSend(
            account: account,
            addressViewModel: recipient.makeAddressViewModel(
                validatedRecipient: snapshot.draft.recipient
            ),
            submission: try snapshot.draft.makeSubmission(
                for: snapshot.request
            ),
            explainedFee: snapshot.draft.explainedFee,
            isScamRecipient: snapshot.draft.recipient.isScam,
            isTransferPayloadAvailable:
                isTransferPayloadAvailable,
            flow: flow
        )
    }

    private var isRequiredCommentMissing: Bool {
        isCommentRequired && comment.isEmpty
    }

    private var payloadPolicy: TransferPayloadPolicy {
        TransferPayloadPolicy(
            flow: .nft,
            chain: configuration.chain,
            isMemoRequired: isCommentRequired,
            isHardwareAccount: account.isHardware,
            hasBinaryPayload: false
        )
    }

    private var draftComment: String? {
        guard configuration.chain.isTransferPayloadSupported else {
            return nil
        }
        return comment.nilIfEmpty
    }

    private func setupObservers() {
        // Wallet-state events revalidate the same request silently; the
        // request itself is observed by the draft engine.
        observers += observe { [weak self] in
            guard let self else { return }
            _ = $account.balances[feeToken.slug]
            draft.refresh()
        }
        observers += observe { [weak self] in
            guard let self else { return }
            _ = (account.id, addressOrDomain)
            didConfirmDomainScamWarning = false
        }
    }

    private func applyScanResult(_ result: ScanResult) {
        switch result {
        case .url(let url):
            guard let parsed = parseTonTransferUrl(url) else { return }
            recipient.textFieldInput = parsed.address
            if let comment = parsed.comment {
                self.comment = comment
            }
        case .address(let address, _):
            recipient.textFieldInput = address
        }
    }
}
