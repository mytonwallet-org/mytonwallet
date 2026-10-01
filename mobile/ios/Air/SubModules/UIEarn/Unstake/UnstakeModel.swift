//
//  StakingVC.swift
//  UIEarn
//
//  Created by Sina on 5/13/24.
//

import Foundation
import SwiftUI
import UIKit
import UIComponents
import WalletCore
import WalletContext
import Perception
import SwiftNavigation

// display available amount
// actual available (incl. for fees)
// display token
// actual token
//

@MainActor
@Perceptible
final class UnstakeModel: WalletCoreData.EventsObserver {
    
    @PerceptionIgnored
    let config: StakingConfig
    @PerceptionIgnored
    @AccountContext private var account: MAccount
    
    init(
        config: StakingConfig,
        stakingState: ApiStakingState,
        accountContext: AccountContext,
        draftClient: StakingDraftClient = .live
    ) {
        self.config = config
        self.stakingState = stakingState
        self._account = accountContext
        self.draftEngine = DraftEngine(
            debounce: .milliseconds(250),
            load: { request, _ in
                try await draftClient.checkUnstake(request)
            }
        )
        draftEngine.onFailure = { [weak self] _, error in
            self?.onDraftFailure?(error)
        }
        updateAccountBalances()
        WalletCoreData.add(eventObserver: self)
        draftEngine.start { [weak self] in
            self?.currentDraftRequest
        }
    }
    
    // MARK: External dependencies
    
    var stakingState: ApiStakingState
    // Wallet state is an event: balance changes revalidate the current
    // request silently instead of forming a new draft identity.
    var nativeBalance: BigInt = 0 {
        didSet {
            if oldValue != nativeBalance {
                draftEngine.refresh()
            }
        }
    }
    var stakedTokenBalance: BigInt = 0 {
        didSet {
            if oldValue != stakedTokenBalance {
                draftEngine.refresh()
            }
        }
    }
    var baseCurrency: MBaseCurrency { TokenStore.baseCurrency }
    
    public func walletCore(event: WalletCoreData.Event) {
        switch event {
        case .balanceChanged, .tokensChanged:
            updateAccountBalances()
        case .accountChanged(let accountId, _):
            guard $account.source == .current,
                  accountId == $account.accountId else { return }
            updateAccountBalances()
        case .stakingAccountData(let data):
            guard data.accountId == $account.accountId else { return }
            if let stakingState = config.stakingState(
                stakingData: $account.stakingData
            ) {
                self.stakingState = stakingState
            }
            updateAccountBalances()
        default:
            break
        }
    }
    
    func updateAccountBalances() {
        let nativeBalance = $account.balances[nativeTokenSlug] ?? 0
        let stakedTokenBalance = $account.stakingData?.byStakedSlug(stakedTokenSlug)?.balance ?? .zero
        self.nativeBalance = nativeBalance
        self.stakedTokenBalance = stakedTokenBalance
        
        if let amountInBaseCurrency, switchedToBaseCurrencyInput && amount != maxAmount {
            updateAmountFromBaseCurrency(amountInBaseCurrency)
        } else {
            updateBaseCurrencyAmount(amount)
        }
    }
    
    var maxAmount: BigInt {
        stakedTokenBalance
    }
    
    // MARK: View controller callbacks
    
    var onAmountChanged: ((BigInt?) -> ())?
    @PerceptionIgnored
    var onDraftFailure: ((any Error) -> Void)?
    
    // User input
    
    var switchedToBaseCurrencyInput: Bool = false
    var amount: BigInt? = nil
    var amountInBaseCurrency: BigInt? = nil
    var isAmountFieldFocused: Bool = false
    
    // Wallet state
    
    var baseToken: ApiToken { config.baseToken }
    var stakedToken: ApiToken { config.stakedToken }
    var nativeTokenSlug: String { config.nativeTokenSlug }
    var stakedTokenSlug: String { config.stakedTokenSlug }

    @PerceptionIgnored
    let draftEngine: DraftEngine<
        UnstakeDraftRequest,
        ApiCheckTransactionDraftResult
    >

    var currentDraftRequest: UnstakeDraftRequest? {
        guard let amount, amount > 0 else { return nil }
        return UnstakeDraftRequest(
            accountId: $account.accountId,
            amount: amount,
            stakingState: stakingState
        )
    }

    var currentDraftSnapshot: OperationDraftSnapshot<
        UnstakeDraftRequest,
        ApiCheckTransactionDraftResult
    >? {
        draftEngine.current
    }

    var draft: ApiCheckTransactionDraftResult? {
        currentDraftSnapshot?.draft
    }

    var draftPhase: OperationDraftPhase {
        if draftEngine.current != nil { return .ready }
        if draftEngine.canRetry { return .failed }
        if draftEngine.isLoading { return .loading }
        return .idle
    }

    var canRetryDraft: Bool {
        draftEngine.canRetry
    }
    
    var fee: MFee? {
        let stakeOperationFee = getStakeOperationFee(stakingType: stakingState.type, stakeOperation: .unstake).real
        return MFee(precision: .exact, terms: .init(token: nil, native: stakeOperationFee, stars: nil), nativeSum: stakeOperationFee)
    }
    
    var tokenChain: ApiChain? { baseToken.chain }
    
    // Validation

    var insufficientFunds: Bool = false

    var shouldRenderBalanceWithSmallFee = false
    
    enum WithdrawalType {
        case instant
        case loading
        case timed(TimeInterval)
    }
    var withdrawalType: WithdrawalType = .instant
    
    var canContinue: Bool {
        !insufficientFunds && (amount ?? 0 > 0)
    }
    
    // MARK: - View callbacks
    
    @MainActor func onBackgroundTapped() {
        topViewController()?.view.endEditing(true)
    }
        
    @MainActor func onUseAll() {
        topViewController()?.view.endEditing(true)
        self.amount = maxAmount
        self.amountInBaseCurrency = convertAmount(maxAmount, price: baseToken.price ?? 0, tokenDecimals: baseToken.decimals, baseCurrencyDecimals: baseCurrency.decimalsCount)
        onAmountChanged?(amount)
    }
    
    // MARK: -
    
    func updateBaseCurrencyAmount(_ amount: BigInt?) {
        guard let amount else { return }
        let price = config.baseToken.price ?? 0
        self.amountInBaseCurrency = convertAmount(amount, price: price, tokenDecimals: baseToken.decimals, baseCurrencyDecimals: baseCurrency.decimalsCount)
        onAmountChanged?(amount)
    }
    
    func updateAmountFromBaseCurrency(_ baseCurrency: BigInt) {
        let price = config.baseToken.price ?? 0
        let baseCurrencyDecimals = self.baseCurrency.decimalsCount
        if price > 0 {
            self.amount = convertAmountReverse(baseCurrency, price: price, tokenDecimals: baseToken.decimals, baseCurrencyDecimals: baseCurrencyDecimals)
        } else {
            self.amount = 0
            self.switchedToBaseCurrencyInput = false
        }
        onAmountChanged?(amount)
    }

    func retryDraft() {
        draftEngine.retry()
    }
}
