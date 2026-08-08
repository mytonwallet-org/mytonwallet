import Foundation
import Perception
import SwiftNavigation
import UIComponents
import WalletContext
import WalletCore

struct NftSendContinueState {
    let canContinue: Bool
    let canRetryDraft: Bool
    let isDraftLoading: Bool
    let hasInsufficientBalanceError: Bool
    let isDraftRejected: Bool
}

struct NftSendDraftSnapshot: Equatable, Sendable {
    let request: NftSendDraftRequest
    let draft: NftSendValidatedDraft

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
    private var draftTask: Task<Void, Never>?
    @PerceptionIgnored
    private var draftRevision: UInt64 = 0
    @PerceptionIgnored
    var onDraftFailure: ((any Error) -> Void)?

    private(set) var draftSnapshot: NftSendDraftSnapshot?
    private(set) var loadingDraftRequest: NftSendDraftRequest?
    private(set) var failedDraftRequest: NftSendDraftRequest?
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

        setupObservers()
        refreshDraft()
    }

    deinit {
        draftTask?.cancel()
    }

    var comment: String {
        get { sanitizedComment }
        set {
            let value = TransferPayloadPolicy.sanitizeComment(newValue)
            guard value != sanitizedComment else { return }
            sanitizedComment = value
            didConfirmDomainScamWarning = false
            refreshDraft()
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
        guard let request = currentDraftRequest,
              draftSnapshot?.request == request else {
            return nil
        }
        return draftSnapshot
    }

    var currentValidatedDraft: NftSendValidatedDraft? {
        currentDraftSnapshot?.draft
    }

    var hasCurrentDraftFailure: Bool {
        currentDraftRequest != nil
            && failedDraftRequest == currentDraftRequest
    }

    var isDraftLoading: Bool {
        guard let request = currentDraftRequest else { return false }
        return loadingDraftRequest == request
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

    var continueState: NftSendContinueState {
        NftSendContinueState(
            canContinue: canContinue,
            canRetryDraft: hasCurrentDraftFailure,
            isDraftLoading: isDraftLoading,
            hasInsufficientBalanceError:
                hasInsufficientBalanceError,
            isDraftRejected: isRecipientInvalid
        )
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
        let explainedFee = displayedDraft?.explainedFee
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
        refreshDraft(debounce: false, force: true)
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

    private var displayedDraft: NftSendValidatedDraft? {
        guard let snapshot = draftSnapshot,
              snapshot.request.accountId == account.id,
              snapshot.request.chain == configuration.chain,
              snapshot.request.nfts == configuration.nfts,
              snapshot.request.mode == configuration.mode else {
            return nil
        }
        return snapshot.draft
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
        observers += observe { [weak self] in
            guard let self else { return }
            _ = (
                self.account.id,
                self.addressOrDomain,
                self.$account.balances[self.feeToken.slug]
            )
            self.didConfirmDomainScamWarning = false
            self.refreshDraft(
                force: !self.hasCurrentDraftFailure
            )
        }
    }

    private func refreshDraft(
        debounce: Bool = true,
        force: Bool = false
    ) {
        guard let request = currentDraftRequest else {
            draftRevision &+= 1
            draftTask?.cancel()
            loadingDraftRequest = nil
            failedDraftRequest = nil
            return
        }
        if !force {
            if loadingDraftRequest == request
                || draftSnapshot?.request == request
                || failedDraftRequest == request {
                return
            }
        }

        draftRevision &+= 1
        let revision = draftRevision
        loadingDraftRequest = request
        failedDraftRequest = nil
        draftTask?.cancel()
        draftTask = Task { [weak self, flow] in
            do {
                if debounce {
                    try await Task.sleep(for: .seconds(0.250))
                }
                let draft = try await flow.validateDraft(request)
                try Task.checkCancellation()
                guard let self,
                      draftRevision == revision,
                      currentDraftRequest == request else {
                    return
                }
                loadingDraftRequest = nil
                failedDraftRequest = nil
                draftSnapshot = NftSendDraftSnapshot(
                    request: request,
                    draft: draft
                )
            } catch {
                guard let self, !Task.isCancelled,
                      draftRevision == revision,
                      currentDraftRequest == request else {
                    return
                }
                loadingDraftRequest = nil
                failedDraftRequest = request
                onDraftFailure?(error)
            }
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
