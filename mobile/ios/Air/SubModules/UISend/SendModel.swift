//
//  SendModel.swift
//  MyTonWalletAir
//
//  Created by nikstar on 20.11.2024.
//

import Foundation
import SwiftUI
import UIKit
import UIComponents
import WalletCore
import WalletContext
import Perception
import SwiftNavigation
import Dependencies

private let log = Log("SendModel")
private let NFT_BURN_PLACEHOLDER_ADDRESS = "placeholder_address"

let debounceCheckTransactionDraft: Duration = .seconds(0.250)

struct DraftData {
    enum DraftStatus: Equatable {
        case none
        case loading
        case invalid
        case valid
    }
    
    var status: DraftStatus
    var transactionDraft: ApiCheckTransactionDraftResult?
}

@Perceptible @MainActor
public final class SendModel: Sendable {
    
    @PerceptionIgnored
    @AccountContext(source: .current) var account: MAccount
    
    @PerceptionIgnored
    @Dependency(\.tokenStore.baseCurrency) var baseCurrency
    
    // MARK: - User input
    
    @PerceptionIgnored
    var addressInput: AddressInputModel!
    
    var addressOrDomain: String { addressInput.draftAddressOrDomain }
    
    var amount: BigInt? = nil
    var amountInBaseCurrency: BigInt? = nil
    var switchedToBaseCurrencyInput: Bool = false
    
    var isMessageEncrypted: Bool = false
    var comment: String = ""
    var binaryPayload: String?
    
    var nfts: [ApiNft]?

    let mode: SendMode

    let stateInit: String?
    
    @PerceptionIgnored
    var addressViewModel: AddressViewModel {
        let apiName = draftData.transactionDraft?.addressName
        let chain = nfts?.first?.chain ?? token.chain
        
        // A temporary solution to detect how would (if any) the address be saved
        var saveKey: String?
        switch addressInput.source {
        case .savedAccount(_, let saveKey1):
            saveKey = saveKey1
        case .myAccount:
            break
        case .constant:
            if let apiName, chain.isValidDomain(apiName) {
                saveKey = apiName // name returned by API is a domain 🤷
            }
        }
        
        return AddressViewModel(
            chain: chain,
            apiAddress: draftData.transactionDraft?.resolvedAddress,
            apiName: apiName,
            saveKey: saveKey
        )
    }
    
    // MARK: - Wallet state
    
    var accountBalance: TokenAmount? {
        guard let balance = $account.balances[token.slug] else { return nil }
        return TokenAmount(balance, token)
    }
    var maxToSend: TokenAmount? = nil
    
    var draftData: DraftData = .init(status: .none, transactionDraft: nil)
    
    var explainedFee: ExplainedTransferFee?
    
    @PerceptionIgnored
    @TokenProvider var token: ApiToken
    
    @PerceptionIgnored
    private var observers: [ObserveToken] = []
    @PerceptionIgnored
    var checkTransactionDraftTask: Task<Void, any Error>?

    private let flow: any SendFlow

    init(prefilledValues: SendPrefilledValues) {
        @Dependency(\.tokenStore) var tokenStore
        @Dependency(\.accountStore) var accountStore
        
        self.mode = prefilledValues.mode
        
        let tokenSlug: String = if let jetton = prefilledValues.jetton?.nilIfEmpty, let tokenSlug = tokenStore.tokens.first(where: { tokenSlug, token in token.tokenAddress == jetton })?.key {
            tokenSlug
        } else if let nftChain = prefilledValues.nfts?.first?.chain {
            nftChain.nativeToken.slug
        } else if let token = prefilledValues.token {
            token
        } else {
            accountStore.get(accountIdOrCurrent: nil).firstChain.nativeToken.slug
        }
        self._token = TokenProvider(tokenSlug: tokenSlug)

        addressInput = AddressInputModel(account: _account, token: _token)

        do {
            if let address = prefilledValues.address {
                self.addressInput.textFieldInput = address
            }
            if let amount = prefilledValues.amount {
                self.amount = amount
            }
            if let commentOrMemo = prefilledValues.commentOrMemo {
                self.comment = commentOrMemo
            }
            if let binaryPayload = prefilledValues.binaryPayload?.nilIfEmpty {
                self.binaryPayload = binaryPayload
            }
            if let nfts = prefilledValues.nfts {
                self.nfts = nfts
            }
        }
        
        self.stateInit = prefilledValues.stateInit
        let isNftFlow = mode.isNftRelated || ((prefilledValues.nfts?.isEmpty == false))
        self.flow = isNftFlow ? NftSendFlow() : TokenSendFlow()

        if mode == .burnNft {
            let burnChain = self.nfts?.first?.chain ?? self.token.chain
            self.addressInput.textFieldInput = burnChain == .ton ? BURN_ADDRESS : NFT_BURN_PLACEHOLDER_ADDRESS
        }
        
        addressInput.onScanResult = { [weak self] in
            self?.onScanResult($0)
        }
        
        setupObservers()

        updateAccountBalance()
    }
    
    private func setupObservers() {
        
        observers += observe { [weak self] in
            guard let self else { return }
            _ = (self.account.id, self.addressOrDomain, self.token, self.amount, self.commentPayload)
            self.checkTransactionDraft()
        }
        observers += observe { [weak self] in
            guard let self else { return }
            _ = draftData
            self.updateMaxToSend()
        }
        observers += observe { [weak self] in
            guard let self else { return }
            _ = self.isEncryptedMessageAvailable
            if self.isMessageEncrypted && !self.isEncryptedMessageAvailable {
                self.isMessageEncrypted = false
            }
        }
    }

    deinit {
        checkTransactionDraftTask?.cancel()
    }
    
    // MARK: - Check transaction draft
    
    func checkTransactionDraft() {
        checkTransactionDraftTask?.cancel()
        checkTransactionDraftTask = Task {
            let context = makeDraftContext()
            do {
                draftData.status = .loading
                try await Task.sleep(for: debounceCheckTransactionDraft)
                let result = try await flow.validateDraft(context: context)
                self.applyDraftResult(result)
            } catch {
                if error is CancellationError { return }
                self.handleValidationError(error, context: context)
            }
        }
    }
    
    private func updateMaxToSend() {
        guard let explainedFee else {
            maxToSend = accountBalance
            return
        }
        let balance = accountBalance?.amount
        let maxAmount = getMaxTransferAmount(
            .init(
                tokenBalance: balance,
                tokenSlug: token.slug,
                fullFee: explainedFee.fullFee?.terms,
                canTransferFullBalance: explainedFee.canTransferFullBalance
            )
        )
        maxToSend = maxAmount.map { TokenAmount($0, token) }
        if let balance, amount == balance, amount ?? 0 > (maxAmount ?? 0) {
            amount = maxAmount
        }
    }
    
    private func applyDraftResult(_ result: SendFlowDraftResult) {
        explainedFee = result.explainedFee
        draftData = result.draftData
        updateRequireMemo(result.requiresMemo)
    }
    
    private func handleValidationError(_ error: Error, context: SendDraftContext) {
        if error is CancellationError { return }
        log.error("validate error: \(error, .public)")
        if !error.localizedDescription.contains("Invalid amount provided") {
            AppActions.showError(error: error)
        }
        explainedFee = nil
        draftData = .init(
            status: .none,
            transactionDraft: nil
        )
        updateRequireMemo(false)
    }
    
    func updateAccountBalance() {
        let balance = accountBalance?.amount
        if let amountInBaseCurrency, switchedToBaseCurrencyInput && amount != balance {
            updateAmountFromBaseCurrency(amountInBaseCurrency)
        } else {
            updateBaseCurrencyAmount(amount)
        }
    }
    
    func updateRequireMemo(_ isRequired: Bool) {
        if isRequired {
            isMessageEncrypted = false
        }
    }
    
    // MARK: - Validation
    
    var isCommentRequired: Bool {
        draftData.transactionDraft?.isMemoRequired ?? false
    }
    
    var isEncryptedMessageAvailable: Bool {
        !isCommentRequired && token.chain.isEncryptedCommentSupported && !mode.isNftRelated && account.isHardware != true
    }
    
    var resolvedAddress: String? {
        draftData.transactionDraft?.resolvedAddress
    }
    
    var toAddressInvalid: Bool {
        if draftData.status == .invalid {
            return true
        }
        return false
    }
    
    var insufficientFunds: Bool {
        if let amount, let balance = accountBalance?.amount {
            let maxAmount = maxToSend?.amount ?? balance
            return amount > maxAmount
        }
        return false
    }

    var isAddressCompatibleWithToken: Bool {
        if addressOrDomain.isEmpty { return true } // do not validate before user inputs address
        let chain = token.chain
        let address = draftData.transactionDraft?.resolvedAddress ?? addressOrDomain
        return chain.isValidAddressOrDomain(address) &&
            (
                chain.isSendToSelfAllowed || address != account.getAddress(chain: chain)
            )
    }

    var canContinue: Bool {
        !addressOrDomain.isEmpty &&
        isAddressCompatibleWithToken &&
        !insufficientFunds &&
        resolvedAddress != nil &&
        !(isCommentRequired && comment.isEmpty) &&
        (amount ?? 0 > 0 || nfts?.count ?? 0 > 0) &&
        !shouldShowMultisigWarning &&
        !shouldShowGasWarning &&
        !shouldShowDomainScamWarning
    }
    
    var shouldShowMultisigWarning: Bool {
        if account.getChainInfo(chain: token.chain)?.isMultisig == true {
            return true
        }
        return false
    }

    var shouldShowGasWarning: Bool {
        let chain = token.chain
        if !chain.shouldShowScamWarningIfNotEnoughGas {
            return false
        }
        guard draftData.transactionDraft?.error == .insufficientBalance else { return false }
        
        // Check if account has that chain tokens (like USDT)
        let usdtSlug = chain.usdtSlug[account.network]
        for (slug, balance) in $account.balances {
            guard balance > 0 else { continue }
            if slug == usdtSlug {
                return true
            }
            if let token = TokenStore.tokens[slug], token.chain == chain, token.isNative == false {
                return true
            }
        }
        return false
    }
    
    var shouldShowDomainScamWarning: Bool {
        guard draftData.transactionDraft?.error != .domainNotResolved else { return false }
        guard case .constant(let input) = addressInput.source else { return false }
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        return trimmed.firstMatch(of: DOMAIN_SCAM_REGEX) != nil
    }
    
    var seedPhraseScamHelpUrl: URL {
        let urlString = Language.current == .ru ? HELP_CENTER_SEED_SCAM_URL_RU : HELP_CENTER_SEED_SCAM_URL
        return URL(string: urlString)!
    }
    
    var domainScamHelpUrl: URL {
        let urlString = Language.current == .ru ? HELP_CENTER_DOMAIN_SCAM_URL_RU : HELP_CENTER_DOMAIN_SCAM_URL
        return URL(string: urlString)!
    }
    
    var dieselStatus: DieselStatus? {
        draftData.transactionDraft?.diesel?.status
    }
    
    var showingFee: MFee? {
        let fee = draftData.transactionDraft?.fee
        let isNativeFullBalance = token.isNative && token.chain.canTransferFullNativeBalance && accountBalance?.amount == amount
        let nativeTokenBalance = $account.balances[token.nativeTokenSlug] ?? 0
        let isEnoughNativeCoin = if isNativeFullBalance {
            fee != nil && fee! < nativeTokenBalance
        } else {
            fee != nil && (fee! + (token.isNative && token.chain.canTransferFullNativeBalance ? amount ?? 0 : 0)) <= nativeTokenBalance
        }
        let isGaslessWithStars = dieselStatus == .starsFee
        let isDieselAvailable = dieselStatus == .available || isGaslessWithStars
        let withDiesel = explainedFee?.isGasless == true
        let dieselAmount = draftData.transactionDraft?.diesel?.tokenAmount ?? 0
        let isEnoughDiesel = withDiesel && amount ?? 0 > 0 && (accountBalance?.amount ?? 0) > 0 && dieselAmount > 0
          ? (isGaslessWithStars
            ? true
            : (accountBalance?.amount ?? 0) - (amount ?? 0) >= dieselAmount)
          : false
        let isInsufficientFee = (fee != nil && !isEnoughNativeCoin && !isDieselAvailable) || (withDiesel && !isEnoughDiesel)
        let isInsufficientBalance = accountBalance != nil && amount != nil && amount! > (accountBalance?.amount ?? 0)
        let shouldShowFull = isInsufficientFee && !isInsufficientBalance
        return shouldShowFull ? explainedFee?.fullFee : explainedFee?.realFee
    }
    
    var explainedTransferFee: ExplainedTransferFee? {
        explainedFee ?? draftData.transactionDraft.flatMap { explainApiTransferFee(input: $0, tokenSlug: token.slug) }
    }
    
    var commentPayload: AnyTransferPayload? {
        if let binaryPayload = self.binaryPayload?.nilIfEmpty {
            return .base64(data: binaryPayload)
        } else if let _comment = self.comment.nilIfEmpty {
            return .comment(text: _comment, shouldEncrypt: self.isMessageEncrypted && self.isEncryptedMessageAvailable)
        } else {
            return nil
        }
    }
    
    // MARK: - View controller callbacks
    
    var continueState: (canContinue: Bool, insufficientFunds: Bool, draftData: DraftData, isAddressLoading: Bool) {
        return (canContinue, insufficientFunds, draftData, addressInput.isAddressLoading)
    }

    // MARK: - View callbacks
    
    func onScanResult(_ result: ScanResult) {
        switch result {
        case .url(let url):
            guard let parsedWalletURL = parseTonTransferUrl(url) else {
                return
            }
            self.$token.slug = parsedWalletURL.token ?? "toncoin"
            self.addressInput.textFieldInput = parsedWalletURL.address
            if let amount = parsedWalletURL.amount {
                self.amount = amount
                self.updateBaseCurrencyAmount(amount)
            }
            if let bin = parsedWalletURL.bin?.nilIfEmpty {
                self.binaryPayload = bin
            } else if let comment = parsedWalletURL.comment {
                self.comment = comment
                self.isMessageEncrypted = false
            }
        
        case .address(let address, let possibleChains):
            if !possibleChains.isEmpty {
                switchToCompatibleNativeTokenIfNeeded(possibleChains)
                self.addressInput.textFieldInput = address
            }
        }
    }
    
    private func switchToCompatibleNativeTokenIfNeeded(_ possibleChains: [ApiChain]) {
        guard !mode.isNftRelated else { return }
        guard !possibleChains.contains(token.chain) else { return }
        guard let targetChain = (
            possibleChains.first(where: { account.supports(chain: $0) })
            ?? possibleChains.first
        ) else {
            return
        }
        let nativeToken = TokenStore.tokens[targetChain.nativeToken.slug] ?? targetChain.nativeToken
        onTokenSelected(newToken: nativeToken)
    }
    
    func onTokenSelected(newToken: ApiToken) {
        let oldDecimals = self.token.decimals
        self.$token.slug = newToken.slug
        
        if switchedToBaseCurrencyInput {
            // keep base currency the same and adjust token amount
            if let baseCurrency = self.amountInBaseCurrency {
                self.updateAmountFromBaseCurrency(baseCurrency)
            }
        } else {
            // new token might have different decimals, but we want user visible number to remain the same
            if let amount = self.amount {
                let newAmount = convertDecimalsKeepingDoubleValue(amount, fromDecimals: oldDecimals, toDecimals: newToken.decimals)
                self.amount = newAmount
                self.updateBaseCurrencyAmount(newAmount)
            }
        }
        
        self.updateAccountBalance()
    }
    
    func onUseAll() {
        guard let maxToSend else {
            return
        }
        self.amount = maxToSend.amount
        self.amountInBaseCurrency = convertAmount(maxToSend.amount, price: token.price ?? 0, tokenDecimals: token.decimals, baseCurrencyDecimals: baseCurrency.decimalsCount)
        endEditing()
    }
    
    // MARK: - Syncing amounts
    
    func updateBaseCurrencyAmount(_ amount: BigInt?) {
        guard let amount else { return }
        self.amountInBaseCurrency = convertAmount(amount, price: token.price ?? 0, tokenDecimals: token.decimals, baseCurrencyDecimals: baseCurrency.decimalsCount)
    }
    
    func updateAmountFromBaseCurrency(_ baseCurrency: BigInt) {
        let price = token.price ?? 0
        let baseCurrencyDecimals = self.baseCurrency.decimalsCount
        if price > 0 {
            self.amount = convertAmountReverse(baseCurrency, price: price, tokenDecimals: token.decimals, baseCurrencyDecimals: baseCurrencyDecimals)
        } else {
            self.amount = 0
            self.switchedToBaseCurrencyInput = false
        }
    }
    
    // MARK: - Send flow
    
    func submit(password: String?) async throws {
        let context = makeSubmitContext()
        try await flow.submit(context: context, password: password, explainedFee: explainedFee)
    }
    
    func makeLedgerPayload() async throws -> SignData {
        let context = makeSubmitContext()
        return try await flow.ledgerPayload(context: context, explainedFee: explainedFee)
    }
    
    private var nftSendMode: NftSendMode? {
        switch mode {
        case .burnNft: return .burn
        case .sendNft: return .send
        default: return  nil
        }
    }
    
    private func makeDraftContext() -> SendDraftContext {
        return SendDraftContext(
            accountId: account.id,
            address: addressOrDomain,
            token: token,
            amount: amount,
            payload: commentPayload,
            stateInit: stateInit,
            nfts: nfts,
            nftSendMode: nftSendMode
        )
    }
    
    private func makeSubmitContext() -> SendSubmitContext {
        SendSubmitContext(
            accountId: account.id,
            token: token,
            amount: amount,
            payload: commentPayload,
            stateInit: stateInit,
            nfts: nfts,
            nftSendMode: nftSendMode,
            transactionDraft: draftData.transactionDraft,
            diesel: draftData.transactionDraft?.diesel
        )
    }
}
