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

let debounceAddressResolution: Duration = .seconds(0.250)
let debounceCheckTransactionDraft: Duration = .seconds(0.250)

struct DraftData {
    enum DraftStatus: Equatable {
        case none
        case loading
        case invalid
        case valid
    }
    
    var status: DraftStatus
    var address: String?
    var tokenSlug: String?
    var amount: BigInt?
    var comment: String?
    var transactionDraft: ApiCheckTransactionDraftResult?
}

@Perceptible @MainActor
public final class SendModel: Sendable {
    
    @PerceptionIgnored
    @AccountViewModel(source: .current) var account: MAccount
    
    @PerceptionIgnored
    @Dependency(\.tokenStore.baseCurrency) var baseCurrency
    
    // MARK: - User input
    
    var addressOrDomain: String = ""
    
    var amount: BigInt? = nil
    var amountInBaseCurrency: BigInt? = nil
    var switchedToBaseCurrencyInput: Bool = false
    
    var isMessageEncrypted: Bool = false
    var comment: String = ""
    var binaryPayload: String?
    
    var nfts: [ApiNft]?
    var nftSendMode: NftSendMode?
    let stateInit: String?
    
    // MARK: - Wallet state
    
    var accountBalance: BigInt? = nil
    var maxToSend: BigInt? = nil
    
    var draftData: DraftData = .init(status: .none, transactionDraft: nil)
    
    var explainedFee: ExplainedTransferFee?
    
    @PerceptionIgnored
    @TokenProvider var token: ApiToken
    
    @PerceptionIgnored
    private var observeAddress: ObserveToken?
    @PerceptionIgnored
    private var observeDraft: ObserveToken?
    @PerceptionIgnored
    private var observeExplainedFee: ObserveToken?
    @PerceptionIgnored
    var resolveAddressTask: Task<Void, any Error>?
    @PerceptionIgnored
    var checkTransactionDraftTask: Task<Void, any Error>?

    private let flow: any SendFlow

    init(prefilledValues: SendPrefilledValues? = nil) {
        @Dependency(\.tokenStore) var tokenStore
        @Dependency(\.accountStore) var accountStore
        if let prefilledValues {
            if let address = prefilledValues.address {
                self.addressOrDomain = address
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
            if let nftSendMode = prefilledValues.nftSendMode {
                self.nftSendMode = nftSendMode
            }
        }
        
        let tokenSlug: String = if let jetton = prefilledValues?.jetton?.nilIfEmpty, let tokenSlug = tokenStore.tokens.first(where: { tokenSlug, token in token.tokenAddress == jetton })?.key {
            tokenSlug
        } else if let token = prefilledValues?.token {
            token
        } else {
            accountStore.get(accountIdOrCurrent: nil).firstChain.nativeToken.slug
        }

        self.stateInit = prefilledValues?.stateInit
        let isNftFlow = (prefilledValues?.nftSendMode != nil) || ((prefilledValues?.nfts?.isEmpty == false))
        self.flow = isNftFlow ? NftSendFlow() : TokenSendFlow()
        self._token = TokenProvider(tokenSlug: tokenSlug)
        if nftSendMode == .burn {
            self.addressOrDomain = BURN_ADDRESS
        }
        
        setupObservers()

        updateAccountBalance()
    }
    
    private func setupObservers() {
        
        observeAddress = observe { [weak self] in
            guard let self else { return }
            _ = (self.account.id, self.addressOrDomain)
            resolveAddress()
        }
        observeDraft = observe { [weak self] in
            guard let self else { return }
            _ = (self.account.id, self.addressOrDomain, self.token, self.amount, self.commentPayload)
            self.checkTransactionDraft()
        }
        observeExplainedFee = observe { [weak self] in
            guard let self else { return }
            _ = draftData
            self.updateMaxToSend()
        }
    }

    deinit {
        resolveAddressTask?.cancel()
        checkTransactionDraftTask?.cancel()
    }
    
    // MARK: - Address resolution
    
    var isAddressLoading: Bool = false
    
    func resolveAddress() {
        resolveAddressTask?.cancel()
        resolveAddressTask = Task {
            do {
                let compatibleChains = account.supportedChains.filter { $0.isValidAddressOrDomain(addressOrDomain) }
                if compatibleChains.isEmpty {
                    addressInfos = nil
                }
                isAddressLoading = true
                try await Task.sleep(for: debounceAddressResolution)
                var addressInfos: [ApiChain: ApiGetAddressInfoResult] = [:]
                for chain in compatibleChains {
                    addressInfos[chain] = try await Api.getAddressInfo(chain: chain, network: account.network, address: addressOrDomain)
                    try Task.checkCancellation()
                }
                self.addressInfos = addressInfos
                isAddressLoading = false
            } catch {
                if !Task.isCancelled {
                    addressInfos = [:]
                    isAddressLoading = false
                }
            }
        }
    }
    
    var addressInfos: [ApiChain: ApiGetAddressInfoResult]?
    
    // MARK: - Check transaction draft
    
    func checkTransactionDraft() {
        checkTransactionDraftTask?.cancel()
        checkTransactionDraftTask = Task {
            let context = makeFlowContext()
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
        let isNative = token.isNative
        maxToSend = TransferHelpers.getMaxTransferAmount(tokenBalance: accountBalance,
                                                         isNativeToken: isNative,
                                                         fullFee: explainedFee.fullFee?.terms,
                                                         canTransferFullBalance: explainedFee.canTransferFullBalance)
        if amount == accountBalance, amount ?? 0 > maxToSend ?? 0 {
            amount = maxToSend
        }
    }
    
    private func setLoadingDraft(context: SendFlowContext) {
        let keepTransactionDraftWhenLoading = context.address == draftData.address && context.token.slug == draftData.tokenSlug
        draftData = DraftData(
            status: .loading,
            address: context.address,
            tokenSlug: context.token.slug,
            amount: context.amount,
            comment: context.comment,
            transactionDraft: keepTransactionDraftWhenLoading ? draftData.transactionDraft : nil
        )
    }
    
    private func applyDraftResult(_ result: SendFlowDraftResult) {
        explainedFee = result.explainedFee
        draftData = result.draftData
        updateRequireMemo(result.requiresMemo)
    }
    
    private func handleValidationError(_ error: Error, context: SendFlowContext) {
        if error is CancellationError { return }
        log.error("validate error: \(error, .public)")
        if !error.localizedDescription.contains("Invalid amount provided") {
            AppActions.showError(error: error)
        }
        explainedFee = nil
        draftData = .init(
            status: .none,
            address: context.address,
            tokenSlug: context.token.slug,
            amount: context.amount,
            comment: context.comment,
            transactionDraft: nil
        )
        updateRequireMemo(false)
    }
    
    func updateAccountBalance() {
        self.accountBalance = $account.balances[token.slug]
        if let amountInBaseCurrency, switchedToBaseCurrencyInput && amount != accountBalance {
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
        !isCommentRequired && nftSendMode == nil && account.isHardware != true
    }
    
    var resolvedAddress: String? {
        draftData.transactionDraft?.resolvedAddress
    }
    
    var toAddressInvalid: Bool {
        if draftData.status == .invalid,
           draftData.address == self.addressOrDomain,
           draftData.tokenSlug == self.token.slug {
            return true
        }
        return false
    }
    
    var insufficientFunds: Bool {
        if let amount, let accountBalance { return amount > maxToSend ?? accountBalance }
        return false
    }

    var isAddressCompatibleWithToken: Bool {
        if addressOrDomain.isEmpty { return true } // do not validate before user inputs address
        let chain = token.chainValue
        let address = draftData.address ?? ""
        return chain.isValidAddressOrDomain(address) &&
            (
                chain.isSendToSelfAllowed || address != account.addressByChain[chain.rawValue]
            )
    }

    var canContinue: Bool {
        !addressOrDomain.isEmpty &&
        isAddressCompatibleWithToken &&
        !insufficientFunds &&
        resolvedAddress != nil &&
        !(isCommentRequired && comment.isEmpty) &&
        (amount ?? 0 > 0 || nfts?.count ?? 0 > 0)
    }
    
    var dieselStatus: DieselStatus? {
        draftData.transactionDraft?.diesel?.status
    }
    
    var showingFee: MFee? {
        let fee = draftData.transactionDraft?.fee
        let isNativeFullBalance = token.isNative && token.chainValue.canTransferFullNativeBalance && accountBalance == amount
        let nativeTokenBalance = $account.balances[token.nativeTokenSlug] ?? 0
        let isEnoughNativeCoin = if isNativeFullBalance {
            fee != nil && fee! < nativeTokenBalance
        } else {
            fee != nil && (fee! + (token.isNative && token.chainValue.canTransferFullNativeBalance ? amount ?? 0 : 0)) <= nativeTokenBalance
        }
        let isGaslessWithStars = dieselStatus == .starsFee
        let isDieselAvailable = dieselStatus == .available || isGaslessWithStars
        let withDiesel = explainedFee?.isGasless == true
        let dieselAmount = draftData.transactionDraft?.diesel?.tokenAmount ?? 0
        let isEnoughDiesel = withDiesel && amount ?? 0 > 0 && accountBalance ?? 0 > 0 && dieselAmount > 0
          ? (isGaslessWithStars
            ? true
            : (accountBalance ?? 0) - (amount ?? 0) >= dieselAmount)
          : false;
        let isInsufficientFee = (fee != nil && !isEnoughNativeCoin && !isDieselAvailable) || (withDiesel && !isEnoughDiesel)
        let isInsufficientBalance = accountBalance != nil && amount != nil && amount! > accountBalance!
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
            return .comment(text: _comment, shouldEncrypt: self.isMessageEncrypted)
        } else {
            return nil
        }
    }
    
    // MARK: - View controller callbacks
    
    var continueState: (canContinue: Bool, insufficientFunds: Bool, draftData: DraftData, isAddressLoading: Bool) {
        return (canContinue, insufficientFunds, draftData, isAddressLoading)
    }

    // MARK: - View callbacks
    
    func onScanResult(_ result: ScanResult) {
        switch result {
        case .url(let url):
            guard let parsedWalletURL = parseTonTransferUrl(url) else {
                return
            }
            self.$token.slug = parsedWalletURL.token ?? "toncoin"
            self.addressOrDomain = parsedWalletURL.address
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
                self.addressOrDomain = address
            }
        }
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
        self.amount = maxToSend
        self.amountInBaseCurrency = convertAmount(maxToSend, price: token.price ?? 0, tokenDecimals: token.decimals, baseCurrencyDecimals: baseCurrency.decimalsCount)
        topViewController()?.view.endEditing(true)
    }
    
    // MARK: - Syncing amounts
    
    func updateBaseCurrencyAmount(_ amount: BigInt?) {
        guard let amount else { return }
        self.amountInBaseCurrency = convertAmount(amount, price: token.price ?? 0, tokenDecimals: token.decimals, baseCurrencyDecimals: baseCurrency.decimalsCount)
        accountBalance = $account.balances[token.slug] ?? 0
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
        accountBalance = $account.balances[token.slug] ?? 0
    }
    
    // MARK: - Send flow
    
    func submit(password: String?) async throws {
        let context = makeFlowContext()
        try await flow.submit(context: context, password: password, explainedFee: explainedFee)
    }
    
    func makeLedgerPayload() async throws -> SignData {
        let context = makeFlowContext()
        return try await flow.ledgerPayload(context: context, explainedFee: explainedFee)
    }
    
    private func makeFlowContext() -> SendFlowContext {
        SendFlowContext(
            accountId: account.id,
            address: addressOrDomain,
            resolvedAddress: resolvedAddress,
            token: token,
            amount: amount,
            comment: comment.nilIfEmpty,
            binaryPayload: binaryPayload,
            payload: commentPayload,
            stateInit: stateInit,
            nfts: nfts,
            nftSendMode: nftSendMode,
            diesel: draftData.transactionDraft?.diesel,
            transactionDraft: draftData.transactionDraft
        )
    }
}
