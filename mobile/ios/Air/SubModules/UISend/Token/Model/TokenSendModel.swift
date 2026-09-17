import Dependencies
import Foundation
import Perception
import SwiftNavigation
import UIComponents
import WalletContext
import WalletCore

enum TokenSelectionSource {
    case automatic
    case explicit
    case user

    func shouldShowIncompatibleRecipientError(
        hasCurrentDraft: Bool
    ) -> Bool {
        switch self {
        case .automatic:
            hasCurrentDraft
        case .explicit, .user:
            true
        }
    }
}

private struct TokenSendEnvironment: Equatable {
    let accountId: String
    let asset: TokenSendAsset
    let tokenBalance: BigInt?
    let nativeTokenBalance: BigInt?
    let tokenPrice: Double?
    let tokenDecimals: Int
    let baseCurrencyDecimals: Int
    let isHardwareAccount: Bool
}

private struct TokenSendMemoRequirement {
    let accountId: String
    let asset: TokenSendAsset
    let recipient: String
    let isRequired: Bool
}

typealias TokenSendDraftSnapshot = OperationDraftSnapshot<
    TokenSendDraftRequest,
    TokenSendValidatedDraft
>

extension OperationDraftSnapshot
where Request == TokenSendDraftRequest, Draft == TokenSendValidatedDraft {
    var isAccepted: Bool {
        draft.recipient.error == nil
    }
}

@Perceptible @MainActor
final class TokenSendModel: Sendable {
    @PerceptionIgnored
    @AccountContext var account: MAccount

    @PerceptionIgnored
    @Dependency(\.tokenStore) private var tokenStore
    @PerceptionIgnored
    @Dependency(\.tokenStore.baseCurrency) var baseCurrency

    let configuration: TokenSendConfiguration
    let recipient: SendRecipientModel

    @PerceptionIgnored
    let flow: TokenSendFlow
    @PerceptionIgnored
    @TokenProvider var token: ApiToken
    @PerceptionIgnored
    private var observers: [ObserveToken] = []
    @PerceptionIgnored
    private var feeQuoteTask: Task<Void, Never>?
    @PerceptionIgnored
    private var feeQuoteRevision: UInt64 = 0
    @PerceptionIgnored
    private var loadingFeeRequest: TokenSendFeeQuoteRequest?
    @PerceptionIgnored
    private var maximumCandidates: [BigInt] = []
    @PerceptionIgnored
    private var isReconcilingMaximum = false
    @PerceptionIgnored
    var onDraftFailure: ((any Error) -> Void)?
    @PerceptionIgnored
    let draftCoordinator: OperationDraftCoordinator<
        TokenSendDraftRequest,
        TokenSendValidatedDraft
    >

    private var environment: TokenSendEnvironment
    private var amountInput: TokenSendAmountInput
    private var commentInput: String
    private var encryptedMessageInput = false
    private var memoRequirement: TokenSendMemoRequirement?

    private(set) var binaryPayload: String?
    private(set) var feeQuote: TokenSendFeeQuote?
    private(set) var maximumAmount: BigInt?
    private(set) var maximumFailure: TokenSendMaxFailure?
    private(set) var tokenSelectionSource: TokenSelectionSource
    var didConfirmDomainScamWarning = false

    init(
        accountContext: AccountContext,
        configuration: TokenSendConfiguration,
        flow: TokenSendFlow = TokenSendFlow(),
        recipientResolver: RecipientResolverClient = .live
    ) {
        @Dependency(\.tokenStore) var tokenStore
        @Dependency(\.tokenStore.baseCurrency) var initialBaseCurrency

        self._account = accountContext
        self.configuration = configuration
        self.flow = flow
        self.draftCoordinator = OperationDraftCoordinator(
            debounce: .milliseconds(250),
            load: flow.validateDraft
        )

        let tokenSlug: String
        let tokenSelectionSource: TokenSelectionSource
        if let jetton = configuration.jettonAddress,
           let slug = tokenStore.tokens.first(where: {
               $0.value.tokenAddress == jetton
           })?.key {
            tokenSlug = slug
            tokenSelectionSource = .explicit
        } else if let explicitToken = configuration.initialTokenSlug {
            tokenSlug = explicitToken
            tokenSelectionSource = .explicit
        } else {
            tokenSlug = Self.bestTokenSlug(
                accountContext: accountContext,
                compatibleChains: configuration.initialAddress.map { address in
                    ApiChain.allCases.filter {
                        $0.isValidAddressOrDomain(address.trimmingCharacters(in: .whitespacesAndNewlines))
                    }
                }
            )
            tokenSelectionSource = .automatic
        }
        self.tokenSelectionSource = tokenSelectionSource

        let initialTokenProvider = TokenProvider(tokenSlug: tokenSlug)
        self._token = initialTokenProvider
        let initialToken = initialTokenProvider.wrappedValue

        let recipient = SendRecipientModel(
            account: accountContext,
            chain: initialToken.chain,
            recipientPolicy: .flexibleChain(
                suggestions: tokenSelectionSource == .automatic
                    ? .all
                    : .preferActiveChain
            ),
            resolver: recipientResolver
        )
        if let address = configuration.initialAddress {
            recipient.textFieldInput = address
        }
        self.recipient = recipient

        self.environment = Self.makeEnvironment(
            accountContext: accountContext,
            token: initialToken,
            baseCurrencyDecimals: initialBaseCurrency.decimalsCount
        )
        self.amountInput = TokenSendAmountInput(
            tokenAmount: configuration.initialAmount,
            price: initialToken.price,
            tokenDecimals: initialToken.decimals,
            baseCurrencyDecimals: initialBaseCurrency.decimalsCount
        )
        self.commentInput = TransferPayloadPolicy.sanitizeComment(
            configuration.initialComment
        )
        self.binaryPayload = configuration.binaryPayload
        self.maximumAmount = accountContext.balances[initialToken.slug]

        recipient.onScanResult = { [weak self] result in
            self?.applyScanResult(result)
        }
        recipient.onSuggestionChainSelected = { [weak self] chain in
            self?.switchToPreferredToken(chain: chain)
        }
        recipient.onCompatibleChainsDetected = { [weak self] chains in
            self?.switchToCompatibleTokenIfNeeded(chains)
        }
        draftCoordinator.didPublishSnapshot = { [weak self] snapshot in
            guard let self else { return }
            guard currentDraftRequest == snapshot.request else {
                refreshDraft()
                return
            }
            applyDraftDerivedState(
                snapshot.draft,
                request: snapshot.request
            )
        }
        draftCoordinator.didFailRequest = { [weak self] request, error in
            guard let self else { return }
            guard currentDraftRequest == request else {
                refreshDraft()
                return
            }
            onDraftFailure?(error)
        }

        setupObservers()
        refreshFeeQuote()
        refreshDraft()
    }

    deinit {
        feeQuoteTask?.cancel()
    }

    var amount: BigInt? {
        amountInput.amount
    }

    var amountInBaseCurrency: BigInt? {
        amountInput.amountInBaseCurrency
    }

    var switchedToBaseCurrencyInput: Bool {
        amountInput.mode == .baseCurrency
    }

    var comment: String {
        get { commentInput }
        set {
            let value = TransferPayloadPolicy.sanitizeComment(newValue)
            guard value != commentInput else { return }
            commentInput = value
            inputDidChange()
        }
    }

    var isMessageEncrypted: Bool {
        get { encryptedMessageInput }
        set {
            guard newValue != encryptedMessageInput else { return }
            encryptedMessageInput = newValue
            inputDidChange()
        }
    }

    var addressOrDomain: String {
        recipient.draftAddressOrDomain
    }

    var activeChain: ApiChain {
        recipient.chain
    }

    var currentDraftRequest: TokenSendDraftRequest? {
        guard let amount = amountInput.amount,
              amount > 0,
              !addressOrDomain.isEmpty else {
            return nil
        }
        return TokenSendDraftRequest(
            accountId: environment.accountId,
            address: addressOrDomain,
            asset: environment.asset,
            amount: amount,
            payload: payloadPolicy.makeTokenPayload(
                comment: commentInput,
                binaryPayload: binaryPayload,
                isMessageEncrypted: encryptedMessageInput
            ),
            stateInit: configuration.stateInit
        )
    }

    var currentDraftSnapshot: TokenSendDraftSnapshot? {
        draftCoordinator.snapshot(for: currentDraftRequest)
    }

    var currentDraft: TokenSendValidatedDraft? {
        currentDraftSnapshot?.draft
    }

    var hasCurrentDraftFailure: Bool {
        draftCoordinator.hasFailed(currentDraftRequest)
    }

    var isDraftLoading: Bool {
        draftCoordinator.isLoading(currentDraftRequest)
    }

    var addressViewModel: AddressViewModel {
        recipient.makeAddressViewModel(
            validatedRecipient: currentDraft?.recipient
        )
    }

    var recipientValidationState: SendRecipientValidationState? {
        recipient.validationState(
            validatedRecipient: currentDraft?.recipient,
            showsIncompatibleError: tokenSelectionSource
                .shouldShowIncompatibleRecipientError(
                    hasCurrentDraft: currentDraft != nil
                )
        )
    }

    var accountBalance: TokenAmount? {
        environment.tokenBalance.map { TokenAmount($0, token) }
    }

    var maxToSend: TokenAmount? {
        maximumAmount.map { TokenAmount($0, token) }
    }

    var isCommentRequired: Bool {
        guard let memoRequirement else { return false }
        return memoRequirement.accountId == environment.accountId
            && memoRequirement.asset == environment.asset
            && memoRequirement.recipient == addressOrDomain
            && memoRequirement.isRequired
    }

    var explainedFee: ExplainedTransferFee? {
        displayedExplainedFee
    }

    private var balanceEvaluation: TokenSendBalanceEvaluation {
        SendBalancePolicy.evaluate(
            tokenBalance: environment.tokenBalance,
            tokenSlug: environment.asset.slug,
            isNativeToken: token.isNative,
            nativeTokenBalance: environment.nativeTokenBalance,
            transferAmount: amountInput.amount,
            displayedFee: displayedExplainedFee,
            computationalFee: computationalFee,
            displayedDiesel: displayedDraftForFee?.diesel,
            computationalDiesel: currentDraft?.diesel,
            draftError: currentDraft?.recipient.error
        )
    }

    var balanceStatus: SendBalanceStatus {
        balanceEvaluation.status
    }

    var hasInsufficientAmount: Bool {
        balanceStatus == .insufficientAmount
    }

    var hasInsufficientFee: Bool {
        balanceStatus == .insufficientFee
    }

    var primaryAction: TokenSendPrimaryAction {
        guard (amountInput.amount ?? 0) > 0,
              !addressOrDomain.isEmpty else {
            return .unavailable(.incompleteInput)
        }
        if balanceStatus == .insufficientAmount {
            return .unavailable(.insufficientAmount)
        }
        if isDraftLoading {
            return .validating
        }
        if hasCurrentDraftFailure {
            return .retryDraft
        }
        if let maximumFailure {
            return .retryMaximum(maximumFailure)
        }
        guard let snapshot = currentDraftSnapshot else {
            return .unavailable(.draftRejected)
        }
        let draft = snapshot.draft
        if isSendAddressDraftError(draft.recipient.error)
            || !recipient.isCompatible(
                resolvedAddress: draft.recipient.resolvedAddress
            ) {
            return .unavailable(.invalidRecipient)
        }
        switch draft.diesel?.status {
        case .notAuthorized:
            guard let url = account.dieselAuthLink else {
                return .unavailable(
                    .dieselAuthorizationUnavailable
                )
            }
            return .authorizeDiesel(url)
        case .pendingPrevious:
            return .awaitingPreviousDiesel
        case .notAvailable, .available, .starsFee, nil:
            break
        }
        if shouldShowMultisigWarning {
            return .unavailable(.multisigWarning)
        }
        if shouldShowGasWarning {
            return .unavailable(.gasWarning)
        }
        if balanceStatus == .insufficientFee {
            return .unavailable(.insufficientFee)
        }
        if isCommentRequired && commentInput.isEmpty {
            return .unavailable(.requiredCommentMissing)
        }
        guard snapshot.isAccepted else {
            return .unavailable(.draftRejected)
        }
        guard draft.recipient.resolvedAddress != nil else {
            return .unavailable(.unresolvedRecipient)
        }
        return .continueToReview
    }

    var isAllowSuspiciousActions: Bool {
        $account.settings.isAllowSuspiciousActions
    }

    var shouldConfirmDomainScamWarning: Bool {
        shouldShowDomainScamWarning && !didConfirmDomainScamWarning
    }

    var isScamRecipient: Bool {
        currentDraft?.recipient.isScam == true
    }

    var shouldShowMultisigWarning: Bool {
        account.getChainInfo(chain: activeChain)?.isMultisig == true
    }

    var shouldShowGasWarning: Bool {
        if token.isNative
            || !activeChain.shouldShowScamWarningIfNotEnoughGas
            || currentDraft?.recipient.error != .insufficientBalance {
            return false
        }

        let usdtSlug = activeChain.usdtSlug[account.network]
        return $account.balances.contains { slug, balance in
            guard balance > 0 else { return false }
            if slug == usdtSlug {
                return true
            }
            return tokenStore.tokens[slug].map {
                $0.chain == activeChain && !$0.isNative
            } ?? false
        }
    }

    var shouldShowDomainScamWarning: Bool {
        recipient.shouldShowDomainScamWarning(
            draftError: currentDraft?.recipient.error
        )
    }

    var showingFee: MFee? {
        let explainedFee = displayedExplainedFee
        return balanceEvaluation.shouldShowFullFee
            ? explainedFee?.fullFee
            : explainedFee?.realFee
    }

    var isTransferPayloadAvailable: Bool {
        payloadPolicy.availability.isVisible
    }

    var isSellSupported: Bool {
        environment.asset.chain.isOfframpSupported
    }

    var isPayloadSectionVisible: Bool {
        isTransferPayloadAvailable
            || SendSigningData(
                binaryPayload: binaryPayload,
                stateInit: configuration.stateInit
            ).isPresent
    }

    var isEncryptedMessageAvailable: Bool {
        payloadPolicy.encryption == .available
    }

    func confirmDomainScamWarning() {
        didConfirmDomainScamWarning = true
    }

    func retryDraft() {
        refreshFeeQuote(force: true)
        draftCoordinator.retry()
    }

    func retryMaximum() {
        maximumCandidates = []
        maximumFailure = nil
        isReconcilingMaximum = true
        let amountChanged = updateMaximum(
            using: computationalFee ?? displayedExplainedFee
        )
        refreshDraft(
            debounce: false,
            force: !amountChanged
        )
    }

    func refreshWalletState() {
        synchronizeEnvironment()
        refreshFeeQuote(force: true)
        if !hasCurrentDraftFailure {
            refreshDraft(force: true)
        }
    }

    func selectAccount(accountId: String) async throws {
        guard accountId != account.id else { return }

        try await AccountStore.activateAccount(accountId: accountId)
        $account.accountId = accountId
        switchToSupportedTokenAfterAccountChangeIfNeeded()
        synchronizeEnvironment()
    }

    func selectToken(
        _ newToken: ApiToken,
        source: TokenSelectionSource = .automatic
    ) {
        if source == .user {
            recipient.preferActiveChainSuggestions()
        }
        tokenSelectionSource = source
        guard newToken.slug != token.slug else { return }

        $token.slug = newToken.slug
        recipient.updateChain(newToken.chain)
        synchronizeEnvironment()
    }

    func selectAll() {
        guard let maximumAmount else { return }
        maximumFailure = nil
        maximumCandidates = [maximumAmount]
        isReconcilingMaximum = true
        amountInput.selectAll(
            maximumAmount,
            price: environment.tokenPrice,
            tokenDecimals: environment.tokenDecimals,
            baseCurrencyDecimals: environment.baseCurrencyDecimals
        )
        didConfirmDomainScamWarning = false
        refreshDraft()
    }

    func setTokenAmount(_ amount: BigInt?) {
        amountInput.setTokenAmount(
            amount,
            price: environment.tokenPrice,
            tokenDecimals: environment.tokenDecimals,
            baseCurrencyDecimals: environment.baseCurrencyDecimals
        )
        maximumCandidates = []
        maximumFailure = nil
        isReconcilingMaximum = false
        _ = updateMaximum(using: displayedExplainedFee)
        inputDidChange()
    }

    func setBaseCurrencyAmount(_ amount: BigInt?) {
        amountInput.setBaseCurrencyAmount(
            amount,
            price: environment.tokenPrice,
            tokenDecimals: environment.tokenDecimals,
            baseCurrencyDecimals: environment.baseCurrencyDecimals
        )
        maximumCandidates = []
        maximumFailure = nil
        isReconcilingMaximum = false
        _ = updateMaximum(using: displayedExplainedFee)
        inputDidChange()
    }

    func setBaseCurrencyInputEnabled(_ enabled: Bool) {
        amountInput.setMode(enabled ? .baseCurrency : .token)
    }

    func synchronizeEnvironment() {
        let newEnvironment = Self.makeEnvironment(
            accountContext: $account,
            token: token,
            baseCurrencyDecimals: baseCurrency.decimalsCount
        )
        guard newEnvironment != environment else { return }

        let oldEnvironment = environment
        let hadDraftFailure = hasCurrentDraftFailure
        let identityChanged =
            oldEnvironment.accountId != newEnvironment.accountId
            || oldEnvironment.asset != newEnvironment.asset
        let assetChanged =
            oldEnvironment.asset != newEnvironment.asset
        let walletChanged =
            oldEnvironment.tokenBalance != newEnvironment.tokenBalance
            || oldEnvironment.nativeTokenBalance
                != newEnvironment.nativeTokenBalance
        let conversionChanged =
            oldEnvironment.tokenPrice != newEnvironment.tokenPrice
            || oldEnvironment.tokenDecimals
                != newEnvironment.tokenDecimals
            || oldEnvironment.baseCurrencyDecimals
                != newEnvironment.baseCurrencyDecimals
        let hardwareChanged =
            oldEnvironment.isHardwareAccount
                != newEnvironment.isHardwareAccount

        environment = newEnvironment
        if assetChanged {
            amountInput.changeToken(
                fromDecimals: oldEnvironment.tokenDecimals,
                toDecimals: newEnvironment.tokenDecimals,
                price: newEnvironment.tokenPrice,
                baseCurrencyDecimals:
                    newEnvironment.baseCurrencyDecimals,
                maximumAmount: newEnvironment.tokenBalance
            )
        } else if conversionChanged {
            amountInput.refreshConversion(
                price: newEnvironment.tokenPrice,
                tokenDecimals: newEnvironment.tokenDecimals,
                baseCurrencyDecimals:
                    newEnvironment.baseCurrencyDecimals
            )
        }

        if identityChanged {
            invalidateDraftIdentity()
            feeQuote = nil
            loadingFeeRequest = nil
            feeQuoteTask?.cancel()
            feeQuoteRevision &+= 1
            memoRequirement = nil
        }
        if amountInput.intent == .all
            && (identityChanged || walletChanged) {
            maximumCandidates = []
            maximumFailure = nil
            isReconcilingMaximum = true
        }
        let amountChanged = updateMaximum(
            using: displayedExplainedFee
        )
        if normalizeEncryption() {
            didConfirmDomainScamWarning = false
        }

        refreshFeeQuote(force: identityChanged)
        refreshDraft(
            force: identityChanged
                || amountChanged
                || hardwareChanged
                || (walletChanged && !hadDraftFailure)
        )
    }

    func makeConfirmedSend() throws -> ConfirmedTokenSend {
        guard let snapshot = currentDraftSnapshot,
              snapshot.isAccepted else {
            throw DisplayError(text: lang("Transaction is not ready"))
        }
        let request = snapshot.request
        let amountInBaseCurrency = environment.tokenPrice.flatMap {
            $0 > 0
                ? convertAmount(
                    request.amount,
                    price: $0,
                    tokenDecimals: environment.tokenDecimals,
                    baseCurrencyDecimals:
                        environment.baseCurrencyDecimals
                )
                : nil
        }.map {
            BaseCurrencyAmount($0, baseCurrency)
        }
        return ConfirmedTokenSend(
            account: account,
            token: token,
            addressViewModel: recipient.makeAddressViewModel(
                validatedRecipient: snapshot.draft.recipient
            ),
            submission: try snapshot.makeSubmission(),
            explainedFee: snapshot.draft.explainedFee,
            amountInBaseCurrency: amountInBaseCurrency,
            isScamRecipient: snapshot.draft.recipient.isScam,
            flow: flow
        )
    }

    private var currentFeeQuoteRequest: TokenSendFeeQuoteRequest {
        TokenSendFeeQuoteRequest(
            accountId: environment.accountId,
            asset: environment.asset
        )
    }

    private var displayedDraftForFee: TokenSendValidatedDraft? {
        guard let snapshot = draftCoordinator.lastSnapshot,
              snapshot.request.accountId == environment.accountId,
              snapshot.request.asset == environment.asset else {
            return nil
        }
        return snapshot.draft
    }

    private var displayedExplainedFee: ExplainedTransferFee? {
        displayedDraftForFee?.explainedFee
            ?? feeQuote.flatMap {
                $0.request == currentFeeQuoteRequest ? $0.fee : nil
            }
    }

    private var computationalFee: ExplainedTransferFee? {
        currentDraft?.explainedFee
            ?? feeQuote.flatMap {
                $0.request == currentFeeQuoteRequest ? $0.fee : nil
            }
    }

    private var payloadPolicy: TransferPayloadPolicy {
        TransferPayloadPolicy(
            flow: .token,
            chain: environment.asset.chain,
            isMemoRequired: isCommentRequired,
            isHardwareAccount: environment.isHardwareAccount,
            hasBinaryPayload: binaryPayload?.nilIfEmpty != nil
        )
    }

    private func inputDidChange() {
        didConfirmDomainScamWarning = false
        _ = normalizeEncryption()
        refreshDraft()
    }

    private func setupObservers() {
        observers += observe { [weak self] in
            guard let self else { return }
            _ = (
                self.account.id,
                self.account.isHardware,
                self.token.slug,
                self.token.chain,
                self.token.tokenAddress,
                self.token.price,
                self.token.decimals,
                self.baseCurrency.decimalsCount,
                self.$account.balances[self.token.slug],
                self.$account.balances[self.token.nativeTokenSlug]
            )
            self.synchronizeEnvironment()
        }
        observers += observe { [weak self] in
            guard let self else { return }
            _ = self.addressOrDomain
            self.inputDidChange()
        }
    }

    private func refreshFeeQuote(force: Bool = false) {
        let request = currentFeeQuoteRequest
        if !force {
            if loadingFeeRequest == request {
                return
            }
            if feeQuote?.request == request {
                return
            }
        }

        feeQuoteRevision &+= 1
        let revision = feeQuoteRevision
        loadingFeeRequest = request
        feeQuoteTask?.cancel()
        feeQuoteTask = Task { [weak self, flow] in
            do {
                let fee = try await flow.estimateFee(request)
                try Task.checkCancellation()
                guard let self,
                      feeQuoteRevision == revision,
                      currentFeeQuoteRequest == request else {
                    return
                }
                loadingFeeRequest = nil
                feeQuote = TokenSendFeeQuote(
                    request: request,
                    fee: fee
                )
                if updateMaximum(using: fee) {
                    refreshDraft(debounce: false)
                }
            } catch {
                guard let self, !Task.isCancelled,
                      feeQuoteRevision == revision,
                      currentFeeQuoteRequest == request else {
                    return
                }
                loadingFeeRequest = nil
            }
        }
    }

    private func refreshDraft(
        debounce: Bool = true,
        force: Bool = false
    ) {
        draftCoordinator.setRequest(
            currentDraftRequest,
            debounce: debounce ? nil : .zero,
            refreshIfUnchanged: force
        )
    }

    private func applyDraftDerivedState(
        _ draft: TokenSendValidatedDraft,
        request: TokenSendDraftRequest
    ) {
        memoRequirement = TokenSendMemoRequirement(
            accountId: request.accountId,
            asset: request.asset,
            recipient: request.address,
            isRequired: draft.requiresMemo
        )
        let normalizedEncryption = normalizeEncryption()
        let amountChanged = updateMaximum(
            using: draft.explainedFee
        )
        if normalizedEncryption || amountChanged {
            refreshDraft(debounce: false)
        }
    }

    @discardableResult
    private func normalizeEncryption() -> Bool {
        guard encryptedMessageInput,
              payloadPolicy.encryption == .unavailable else {
            return false
        }
        encryptedMessageInput = false
        return true
    }

    @discardableResult
    private func updateMaximum(
        using fee: ExplainedTransferFee?
    ) -> Bool {
        let nextMaximum = calculateMaximum(using: fee)
        maximumAmount = nextMaximum

        if case .exact = amountInput.intent {
            isReconcilingMaximum = false
        }
        if let amount = amountInput.amount,
           amountInput.intent == .exact(amount),
           let balance = environment.tokenBalance,
           let nextMaximum,
           nextMaximum > 0,
           amount <= balance,
           amount > nextMaximum {
            amountInput.adjustExactAmount(
                to: nextMaximum,
                price: environment.tokenPrice,
                tokenDecimals: environment.tokenDecimals,
                baseCurrencyDecimals:
                    environment.baseCurrencyDecimals
            )
            return true
        }

        guard amountInput.intent == .all else {
            return false
        }
        guard maximumFailure == nil else {
            return false
        }
        guard amountInput.amount != nextMaximum else {
            isReconcilingMaximum = false
            return false
        }
        if !isReconcilingMaximum {
            maximumCandidates = []
            isReconcilingMaximum = true
        }
        guard let nextMaximum else {
            amountInput.updateMaximumAmount(
                nil,
                price: environment.tokenPrice,
                tokenDecimals: environment.tokenDecimals,
                baseCurrencyDecimals:
                    environment.baseCurrencyDecimals
            )
            isReconcilingMaximum = false
            return true
        }
        if maximumCandidates.contains(nextMaximum) {
            maximumFailure = .oscillating
            isReconcilingMaximum = false
            return false
        }
        guard maximumCandidates.count < 3 else {
            maximumFailure = .attemptLimit
            isReconcilingMaximum = false
            return false
        }
        maximumCandidates.append(nextMaximum)
        amountInput.updateMaximumAmount(
            nextMaximum,
            price: environment.tokenPrice,
            tokenDecimals: environment.tokenDecimals,
            baseCurrencyDecimals: environment.baseCurrencyDecimals
        )
        return true
    }

    private func calculateMaximum(
        using fee: ExplainedTransferFee?
    ) -> BigInt? {
        guard let fee else {
            return environment.tokenBalance
        }
        return getMaxTransferAmount(.init(
            tokenBalance: environment.tokenBalance,
            tokenSlug: environment.asset.slug,
            fullFee: fee.fullFee?.terms,
            canTransferFullBalance: fee.canTransferFullBalance
        ))
    }

    private func invalidateDraftIdentity() {
        draftCoordinator.reset()
        maximumCandidates = []
        maximumFailure = nil
        isReconcilingMaximum = false
    }

    private func applyScanResult(_ result: ScanResult) {
        switch result {
        case .url(let url):
            guard let parsed = parseTonTransferUrl(url) else { return }
            recipient.textFieldInput = parsed.address
            let newTokenSlug = parsed.token ?? TONCOIN_SLUG
            if let newToken = tokenStore.getToken(slug: newTokenSlug) {
                selectToken(newToken, source: .explicit)
            }
            if let amount = parsed.amount {
                setTokenAmount(amount)
            }
            if let binaryPayload = parsed.bin?.nilIfEmpty {
                self.binaryPayload = binaryPayload
                inputDidChange()
            } else if let comment = parsed.comment {
                commentInput =
                    TransferPayloadPolicy.sanitizeComment(comment)
                encryptedMessageInput = false
                inputDidChange()
            }
        case .address(let address, _):
            recipient.textFieldInput = address
        }
    }

    private func switchToCompatibleTokenIfNeeded(
        _ possibleChains: [ApiChain]
    ) {
        guard tokenSelectionSource == .automatic,
              possibleChains.contains(where: { account.supports(chain: $0) }) else {
            return
        }
        let slug = Self.bestTokenSlug(
            accountContext: $account,
            compatibleChains: possibleChains
        )
        let candidate = tokenStore.getToken(slug: slug)
            ?? possibleChains.first(where: { account.supports(chain: $0) })?.nativeToken
        if let candidate {
            selectToken(candidate, source: .automatic)
        }
    }

    private func switchToPreferredToken(chain: ApiChain) {
        guard account.supports(chain: chain) else { return }
        let slug = Self.bestTokenSlug(
            accountContext: $account,
            compatibleChains: [chain]
        )
        selectToken(
            tokenStore.getToken(slug: slug) ?? chain.nativeToken,
            source: .automatic
        )
    }

    private func switchToSupportedTokenAfterAccountChangeIfNeeded() {
        guard !account.supports(chain: token.chain) else { return }
        let tokenSlug = Self.bestTokenSlug(accountContext: $account)
        let candidate = tokenStore.getToken(slug: tokenSlug)
            ?? account.firstChain.nativeToken
        selectToken(
            account.supports(chain: candidate.chain)
                ? candidate
                : account.firstChain.nativeToken,
            source: .automatic
        )
    }

    private static func makeEnvironment(
        accountContext: AccountContext,
        token: ApiToken,
        baseCurrencyDecimals: Int
    ) -> TokenSendEnvironment {
        TokenSendEnvironment(
            accountId: accountContext.account.id,
            asset: TokenSendAsset(token),
            tokenBalance: accountContext.balances[token.slug],
            nativeTokenBalance:
                accountContext.balances[token.nativeTokenSlug],
            tokenPrice: token.price,
            tokenDecimals: token.decimals,
            baseCurrencyDecimals: baseCurrencyDecimals,
            isHardwareAccount: accountContext.account.isHardware
        )
    }

    private static func bestTokenSlug(
        accountContext: AccountContext,
        compatibleChains: [ApiChain]? = nil
    ) -> String {
        let account = accountContext.account
        let chains = ApiChain.allCases.filter { chain in
            guard account.supports(chain: chain) else { return false }
            guard let compatibleChains, !compatibleChains.isEmpty else { return true }
            return compatibleChains.contains(chain)
        }
        return preferredToken(
            tokens: accountContext.walletTokenPresentation.visible
                .filter { !$0.isStaking }
                .compactMap(\.token),
            balances: accountContext.balances,
            compatibleChains: chains
        )?.slug
            ?? ApiToken.defaultSlugs(
                forNetwork: account.network,
                account: account
            ).first { slug in
                TokenStore.getToken(slug: slug).map { chains.contains($0.chain) } ?? false
            }
            ?? chains.first?.nativeToken.slug
            ?? account.firstChain.nativeToken.slug
    }

    static func preferredToken(
        tokens: [ApiToken],
        balances: [String: BigInt],
        compatibleChains: [ApiChain]
    ) -> ApiToken? {
        tokens.filter { compatibleChains.contains($0.chain) }.max { lhs, rhs in
            let lhsValue = (balances[lhs.slug] ?? 0)
                .doubleAbsRepresentation(decimals: lhs.decimals) * (lhs.priceUsd ?? 0)
            let rhsValue = (balances[rhs.slug] ?? 0)
                .doubleAbsRepresentation(decimals: rhs.decimals) * (rhs.priceUsd ?? 0)
            return lhsValue < rhsValue
        }
    }
}
