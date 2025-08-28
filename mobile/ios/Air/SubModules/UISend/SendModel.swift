//
//  SendModel.swift
//  MyTonWalletAir
//
//  Created by nikstar on 20.11.2024.
//

import Foundation
import SwiftUI
import Combine
import UIKit
import UIComponents
import UIQRScan
import WalletCore
import WalletContext

private let log = Log("SendModel")

@MainActor public final class SendModel: ObservableObject, Sendable {
    
    public typealias PrefilledValues = SendPrefilledValues

    init(prefilledValues: PrefilledValues? = nil) {
        if let prefilledValues {
            if let address = prefilledValues.address {
                self.addressOrDomain = address
            }
            if let amount = prefilledValues.amount {
                self.amount = amount
            }
            if let jetton = prefilledValues.jetton?.nilIfEmpty, let tokenSlug = TokenStore.tokens.first(where: { tokenSlug, token in token.tokenAddress == jetton })?.key {
                self.tokenSlug = tokenSlug
            } else if let token = prefilledValues.token {
                self.tokenSlug = token
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

        if nftSendMode == .burn {
            self.addressOrDomain = BURN_ADDRESS
        }
        
        setupObservers()

        WalletCoreData.add(eventObserver: self)
        updateAccountBalance()
    }
    
    // View controller callbacks
    
    var present: ((UIViewController) -> ())? = nil
    var dismiss: ((UIViewController) -> ())? = nil
    var push: ((UIViewController) -> ())? = nil
    var showAlert: ((any Error) -> ())? = nil
    var showToast: ((_ animationName: String?, _ message: String) -> ())? = nil
    var continueStateChanged: ((Bool, Bool, DraftData) -> ())? = nil
    
    // User input
    
    @Published var addressOrDomain: String = "" {
        didSet {
            validateAddressOrDomain(addressOrDomain, tokenSlug: tokenSlug)
            onContinueStateChanged(canContinue: canContinue, insufficientFunds: insufficientFunds, draftData: draftData)
        }
    }
    @Published var tokenSlug: String = "toncoin" {
        didSet {
            validateAddressOrDomain(addressOrDomain, tokenSlug: tokenSlug)
            onContinueStateChanged(canContinue: canContinue, insufficientFunds: insufficientFunds, draftData: draftData)
        }
    }
    @Published var switchedToBaseCurrencyInput: Bool = false
    @Published var amount: BigInt? = nil
    @Published var amountInBaseCurrency: BigInt? = nil
    @Published var isMessageEncrypted: Bool = false
    @Published var comment: String = ""
    @Published var binaryPayload: String?
    @Published var nfts: [ApiNft]?
    @Published var nftSendMode: NftSendMode?
    var isSendNft: Bool { nftSendMode != nil }
    
    // Wallet state
    
    @Published var accountBalance: BigInt? = nil
    @Published var maxToSend: BigInt? = nil {
        didSet {
            onContinueStateChanged(canContinue: canContinue, insufficientFunds: insufficientFunds, draftData: draftData)
        }
    }
    
    @Published var draftData: DraftData = .init(status: .none, transactionDraft: nil) {
        didSet {
            updateFee()
            onContinueStateChanged(canContinue: canContinue, insufficientFunds: insufficientFunds, draftData: draftData)
        }
    }

    var explainedFee: TransferHelpers.ExplainedTransferFee? {
        if let token, let toAddressDraft {
            return TransferHelpers.explainApiTransferFee(chain: token.chain, isNativeToken: token.isNative, input: toAddressDraft)
        }
        return nil
    }
    var token: ApiToken? { TokenStore.tokens[tokenSlug] }
    var tokenChain: ApiChain? { (token?.chain).flatMap(availableChain(slug:)) }
    var nativeToken: ApiToken? { TokenStore.tokens[tokenChain?.tokenSlug ?? ""] }
    
    struct DraftData {
        enum DraftStatus: Equatable {
            case none
            case loading
            case invalid
            case valid
        }
        
        let status: DraftStatus
        let address: String?
        let tokenSlug: String?
        let amount: BigInt?
        let comment: String?
        let transactionDraft: MTransactionDraft?
        
        init(status: DraftStatus,
             address: String? = nil,
             tokenSlug: String? = nil,
             amount: BigInt? = nil,
             comment: String? = nil,
             transactionDraft: MTransactionDraft?) {
            self.status = status
            self.address = address
            self.tokenSlug = tokenSlug
            self.amount = amount
            self.comment = comment
            self.transactionDraft = transactionDraft
        }
    }

    private var observers: Set<AnyCancellable> = []

    private func setupObservers() {
        Publishers.CombineLatest($accountBalance, $tokenSlug)
            .sink { [weak self] v in
                let (accountBalance, tokenSlug) = v
                guard let self else { return }
                let token = TokenStore.tokens[tokenSlug]
                guard let token, let toAddressDraft else {
                    maxToSend = accountBalance
                    return
                }
            }
            .store(in: &observers)

        $amount
            .debounce(for: 0.25, scheduler: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }
                validateAddressOrDomain(addressOrDomain, tokenSlug: tokenSlug)
                updateFee()
                onContinueStateChanged(canContinue: canContinue, insufficientFunds: insufficientFunds, draftData: draftData)
            }
            .store(in: &observers)
        
        $comment
            .debounce(for: 0.35, scheduler: RunLoop.main)
            .sink { [weak self] _ in
                self?.validateAndEstimate()
            }
            .store(in: &observers)
    }
    
    private func updateFee() {
        let token = TokenStore.tokens[tokenSlug]
        guard let token, let toAddressDraft else {
            return
        }
        let isNative = token.isNative
        maxToSend = TransferHelpers.getMaxTransferAmount(tokenBalance: accountBalance,
                                                         isNativeToken: isNative,
                                                         fullFee: explainedFee?.fullFee?.terms,
                                                         canTransferFullBalance: explainedFee!.canTransferFullBalance)
        if amount == accountBalance, amount ?? 0 > maxToSend ?? 0 {
            amount = maxToSend
        }
    }
    
    // Validation
    var isCommentRequired: Bool {
        toAddressDraft?.isMemoRequired ?? false
    }
    
    var isEncryptedMessageAvailable: Bool {
        !isCommentRequired && nftSendMode == nil && AccountStore.account?.isHardware != true
    }
    
    var resolvedAddress: String? {
        toAddressDraft?.resolvedAddress
    }
    
    var toAddressInvalid: Bool {
        if draftData.status == .invalid,
           draftData.address == self.addressOrDomain,
           draftData.tokenSlug == self.tokenSlug {
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
        guard let token else { return false }
        return token.chainValue.validate(address: draftData.address ?? "") == true
    }

    var canContinue: Bool {
        !addressOrDomain.isEmpty &&
        isAddressCompatibleWithToken &&
        !insufficientFunds &&
        resolvedAddress != nil &&
        !(isCommentRequired && comment.isEmpty) &&
        (amount ?? 0 > 0 || nfts?.count ?? 0 > 0)
    }
    
    var toAddressDraft: MTransactionDraft? {
        draftData.transactionDraft
    }
    
    var dieselStatus: DieselStatus? {
        draftData.transactionDraft?.diesel?.status
    }
    
    var showingFee: MFee? {
        let fee = draftData.transactionDraft?.fee
        let isToncoinFullBalance = tokenSlug == "toncoin" && accountBalance == amount
        let nativeTokenBalance = BalanceStore.currentAccountBalances[nativeToken?.slug ?? ""] ?? 0
        let isEnoughNativeCoin = isToncoinFullBalance ?
            (fee != nil && fee! < nativeTokenBalance) : (fee != nil && (fee! + (tokenSlug == "toncoin" ? amount ?? 0 : 0)) <= nativeTokenBalance);
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
        if let draft = draftData.transactionDraft {
            return explainApiTransferFee(input: draft, tokenSlug: tokenSlug)
        }
        return nil
    }
    
    // MARK: - View callbacks
    
    func onBackgroundTapped() {
        topViewController()?.view.endEditing(true)
    }
    
    func onAddressPastePressed() {
        if let pastedAddress = UIPasteboard.general.string, !pastedAddress.isEmpty {
            // todo: handle urls; extract that code from qr code scanning to avoid duplication
            self.addressOrDomain = pastedAddress
            validateAddressOrDomain(nil, tokenSlug: tokenSlug)
            topViewController()?.view.endEditing(true)
        } else {
            showToast?(nil, lang("Clipboard empty"))
        }
    }
    
    func onScanPressed() {
        let qrScanVC = QRScanVC(callback: { [weak self] result in
            guard let self else {return}
            topViewController()?.view.endEditing(true)
            switch result {
            case .url(let url):
                guard let parsedWalletURL = parseTonTransferUrl(url) else {
                    return
                }
                self.tokenSlug = parsedWalletURL.token ?? "toncoin"
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

            @unknown default:
                break
            }
            
        })
        present?(WNavigationController(rootViewController: qrScanVC))
    }
    
    func onTokenTapped() {
        let vc = SendCurrencyVC(walletTokens: [], currentTokenSlug: self.tokenSlug, onSelect: { token in })
        vc.onSelect = { [weak self] newToken in
            guard let self else { return }
            
            let oldDecimals = self.token?.decimals ?? 9
            self.tokenSlug = newToken.slug
            
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
            self.dismiss?(vc)
        }
        let nav = WNavigationController(rootViewController: vc)
        present?(nav)
    }
    
    func onComposeContinue() {
        topViewController()?.view.endEditing(true)
        let vc = SendConfirmVC(model: self)
        push?(vc)
    }
    
    func onUseAll() {
        guard let maxToSend else {
            return
        }
        self.amount = maxToSend
        self.amountInBaseCurrency = if let token, let baseCurrency = TokenStore.baseCurrency {
            convertAmount(maxToSend, price: token.price ?? 0, tokenDecimals: token.decimals, baseCurrencyDecimals: baseCurrency.decimalsCount)
        } else {
            0
        }
        topViewController()?.view.endEditing(true)
    }
    
    func onContinueStateChanged(canContinue: Bool, insufficientFunds: Bool, draftData: DraftData) {
        continueStateChanged?(canContinue, insufficientFunds, draftData)
    }
    
    @MainActor func onAddressCopy() {
        AppActions.copyString(resolvedAddress, toastMessage: lang("Address was copied to clipboard."))
    }
    
    func onOpenAddressInExplorer() {
        if let chain = self.tokenChain {
            let url = ExplorerHelper.addressUrl(chain: chain, address: resolvedAddress ?? addressOrDomain)
            AppActions.openInBrowser(url)
        }
    }
    
    func onSaveToFavorites() {
        showToast?(nil, "Not implemented")
        UINotificationFeedbackGenerator().notificationOccurred(.error)
    }
    
    // MARK: -
    
    func updateBaseCurrencyAmount(_ amount: BigInt?) {
        guard let amount else { return }
        self.amountInBaseCurrency = if let token, let baseCurrency = TokenStore.baseCurrency {
            convertAmount(amount, price: token.price ?? 0, tokenDecimals: token.decimals, baseCurrencyDecimals: baseCurrency.decimalsCount)
        } else {
            0
        }
        accountBalance = BalanceStore.currentAccountBalances[tokenSlug] ?? 0
    }
    
    func updateAmountFromBaseCurrency(_ baseCurrency: BigInt) {
        guard let token else { return }
        let price = token.price ?? 0
        let baseCurrencyDecimals = TokenStore.baseCurrency?.decimalsCount ?? 2
        if price > 0 {
            self.amount = convertAmountReverse(baseCurrency, price: price, tokenDecimals: token.decimals, baseCurrencyDecimals: baseCurrencyDecimals)
        } else {
            self.amount = 0
            self.switchedToBaseCurrencyInput = false
        }
        accountBalance = BalanceStore.currentAccountBalances[tokenSlug] ?? 0
    }
    
    func validateAddressOrDomain(_ addressOrDomain: String?, tokenSlug: String?) {
        guard let chain = ApiChain(rawValue: token?.chain ?? "") else{
            return
        }
        let address = addressOrDomain ?? self.addressOrDomain
        let tokenSlug = tokenSlug ?? self.tokenSlug
        if chain.validate(address: address) == false {
            draftData = .init(status: .invalid, address: address, tokenSlug: tokenSlug, amount: amount, comment: comment, transactionDraft: nil)
        } else {
            validateAndEstimate()
        }
    }
    
    func _prepareCommentOptions() -> (isBase64Data: Bool?, comment: String?, shouldEncrypt: Bool?) {
        let isBase64Data: Bool?
        let comment: String?
        let shouldEncrypt: Bool?
        if let binaryPayload = self.binaryPayload?.nilIfEmpty {
            isBase64Data = true
            comment = binaryPayload
            shouldEncrypt = false
        } else if let _comment = self.comment.nilIfEmpty {
            isBase64Data = false
            comment = _comment
            shouldEncrypt = self.isMessageEncrypted
        } else {
            isBase64Data = nil
            comment = nil
            shouldEncrypt = nil
        }
        return (isBase64Data: isBase64Data, comment: comment, shouldEncrypt: shouldEncrypt)
    }
    
    func makeCheckTransactionOptions(addressOrDomain: String, amount: BigInt?, comment: String?) -> Api.CheckTransactionDraftOptions? {
        guard let token = token else {
            return nil
        }
        let (isBase64Data, comment, shouldEncrypt) = _prepareCommentOptions()
        return Api.CheckTransactionDraftOptions(
            accountId: AccountStore.accountId!,
            toAddress: addressOrDomain,
            amount: amount ?? 0,
            tokenAddress: token.tokenAddress,
            data: comment,
            stateInit: nil,
            shouldEncrypt: shouldEncrypt,
            isBase64Data: isBase64Data,
            forwardAmount: nil,
            allowGasless: true
        )
    }
    
    func makeSubmitTransferOptions(passcode: String?, addressOrDomain: String, amount: BigInt?, comment: String?) async throws -> Api.SubmitTransferOptions? {
        guard let token = token else {
            return nil
        }
        let (isBase64Data, comment, shouldEncrypt) = _prepareCommentOptions()
        let account = AccountStore.account!
        var stateInit: String?
        let isInitialized = try? await Api.isWalletInitialized(network: .mainnet, address: addressOrDomain)
        if isInitialized == false {
            stateInit = try await Api.getWalletStateInit(accountId: account.id)
        }
        let draft = draftData.transactionDraft
        return Api.SubmitTransferOptions(
            accountId: account.id,
            password: passcode,
            toAddress: addressOrDomain,
            amount: amount ?? 0,
            comment: comment,
            tokenAddress: token.tokenAddress,
            fee: explainedFee?.fullFee?.nativeSum,
            realFee: explainedFee?.realFee?.nativeSum,
            shouldEncrypt: shouldEncrypt,
            isBase64Data: isBase64Data,
            withDiesel: explainedFee?.isGasless,
            dieselAmount: draftData.transactionDraft?.diesel?.tokenAmount,
            stateInit: stateInit,
            forwardAmount: nil,
            noFeeCheck: nil,
        )
    }
    
    private func validateAndEstimate() {
        Task {
            if nftSendMode == nil {
                await validateAndEstimateBase()
            } else {
                await validateAndEstimateNft()
            }
        }
    }
    
    @MainActor private func validateAndEstimateBase() async {
        do {
            if addressOrDomain == draftData.address,
               tokenSlug == draftData.tokenSlug,
               (
                draftData.status == .invalid ||
                (amount == draftData.amount &&
                 comment == draftData.comment)
               ) {
                // no need to re-check
                return
            }
            let keepTransactionDraftWhenLoading = addressOrDomain == draftData.address && tokenSlug == draftData.tokenSlug
            self.draftData = .init(status: .loading, address: addressOrDomain, tokenSlug: tokenSlug, transactionDraft: keepTransactionDraftWhenLoading ? draftData.transactionDraft : nil)
            
            guard let chain = token?.chain,
                  let draftOptions = makeCheckTransactionOptions(addressOrDomain: addressOrDomain, amount: amount, comment: comment) else {
                self.draftData = .init(status: .none, transactionDraft: nil)
                return
            }
            log.info("checkTransactionDraft \(chain, .public) \(draftOptions.amount, .public)")
            let draft = try await Api.checkTransactionDraft(chain: chain, options: draftOptions)
            try handleDraftError(draft)
            switch draft.error {
            case .domainNotResolved:
                self.draftData = .init(status: .invalid, address: addressOrDomain, transactionDraft: nil)
                return
            case .walletNotInitialized:
                self.draftData = .init(status: .none, address: addressOrDomain, transactionDraft: nil)
                showAlert?(BridgeCallError.message(.walletNotInitialized, nil))
                return
            default:
                break
            }
            self.draftData = .init(status: .valid, address: addressOrDomain, tokenSlug: tokenSlug, amount: amount, comment: comment, transactionDraft: draft)
            requireMemo(draft.isMemoRequired ?? false)
        } catch {
            if !Task.isCancelled {
                log.error("validate error: \(error, .public)")
                if !error.localizedDescription.contains("Invalid amount provided") {
                    showAlert?(error)
                }
                self.draftData = .init(status: .none, address: addressOrDomain, tokenSlug: tokenSlug, amount: amount, comment: comment, transactionDraft: nil)
                requireMemo(false)
            }
        }
    }
    
    @MainActor private func validateAndEstimateNft() async {
        do {
            let draftData = self.draftData
            let keepTransactionDraftWhenLoading = addressOrDomain == draftData.address && tokenSlug == draftData.tokenSlug
            self.draftData = .init(status: .loading, address: addressOrDomain, tokenSlug: tokenSlug, transactionDraft: keepTransactionDraftWhenLoading ? draftData.transactionDraft : nil)

            let nfts = self.nfts ?? []
            let accountId = AccountStore.accountId!
            let toAddress = self.addressOrDomain
            let comment = self.comment.nilIfEmpty
            let estimate = try await Api.checkNftTransferDraft(options: .init(accountId: accountId, nfts: nfts, toAddress: toAddress, comment: comment))
            try handleDraftError(estimate)
            self.draftData = .init(status: .valid, address: toAddress, tokenSlug: tokenSlug, amount: amount, comment: comment, transactionDraft: estimate)
        } catch {
            if !Task.isCancelled {
                showAlert?(error)
            }
            self.draftData = .init(status: .none, address: addressOrDomain, tokenSlug: tokenSlug, amount: amount, comment: comment, transactionDraft: nil)
        }
    }

    func updateAccountBalance() {
        self.accountBalance = BalanceStore.currentAccountBalances[tokenSlug]
        if let amountInBaseCurrency, switchedToBaseCurrencyInput && amount != accountBalance {
            updateAmountFromBaseCurrency(amountInBaseCurrency)
        } else {
            updateBaseCurrencyAmount(amount)
        }
    }
    
    func requireMemo(_ isReqired: Bool) {
        if isReqired {
            isMessageEncrypted = false
        }
    }
}


extension SendModel: WalletCoreData.EventsObserver {
    public func walletCore(event: WalletCoreData.Event) {
        switch event {
        case .balanceChanged, .tokensChanged:
            updateAccountBalance()
        default:
            break
        }
    }
}

