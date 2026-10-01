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

@MainActor @Perceptible
final class AddStakeModel: WalletCoreData.EventsObserver {
    
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
                try await draftClient.checkStake(request)
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
    var baseTokenBalance: BigInt = 0 {
        didSet {
            if oldValue != baseTokenBalance {
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
            if data.accountId == $account.accountId {
                if let stakingState = config.stakingState(stakingData: $account.stakingData) {
                    self.stakingState = stakingState
                }
            }
        default:
            break
        }
    }
    
    func updateAccountBalances() {
        let nativeBalance = $account.balances[nativeTokenSlug] ?? 0
        let baseTokenBalance = $account.balances[tokenSlug] ?? 0
        self.nativeBalance = nativeBalance
        self.baseTokenBalance = baseTokenBalance
        
        if let amountInBaseCurrency, switchedToBaseCurrencyInput && amount != maxAmount {
            updateAmountFromBaseCurrency(amountInBaseCurrency)
        } else {
            updateBaseCurrencyAmount(amount)
        }
    }
    
    var apy: Double { stakingState.apy }
    var yieldType: ApiYieldType { stakingState.yieldType }
    var type: ApiStakingType { stakingState.type }

    var isNativeToken: Bool {
        baseToken.slug == nativeTokenSlug
    }
    
    var minAmount: BigInt { getStakingMinAmount(type: type) }
    
    var fees: TonOperationFees { getStakeOperationFee(stakingType: type, stakeOperation: .stake) }
    var networkFee: BigInt { fees.gas.orZero }
    var realFee: BigInt { fees.real.orZero }
    
    var totalStakers: Int? { stakingState.totalStakers }
    
    var totalStaked: BigInt? { stakingState.totalStaked }
    
    var nativeAmount: BigInt {
        if let amount, isNativeToken {
            return amount + networkFee
        }
        return networkFee
    }
    var maxAmount: BigInt {
        let shouldLeaveForUnstake = isNativeToken && baseTokenBalance > 2*networkFee
        var value = baseTokenBalance
        if isNativeToken {
            value -= shouldLeaveForUnstake ? 2*networkFee : networkFee
        }
        return max(0, value)
    }
    
    // MARK: View controller callbacks
    
    var onAmountChanged: ((BigInt?) -> ())?
    var onWhyIsSafe: (() -> ())?
    @PerceptionIgnored
    var onDraftFailure: ((any Error) -> Void)?
    
    // MARK: User input
    
    var switchedToBaseCurrencyInput: Bool = false
    var amount: BigInt? = nil
    var amountInBaseCurrency: BigInt? = nil
    var isAmountFieldFocused: Bool = false
    
    // MARK: Wallet state
    
    var baseToken: ApiToken { config.baseToken }
    var nativeTokenSlug: String { config.nativeTokenSlug }
    var tokenSlug: String { baseToken.slug }
    
    @PerceptionIgnored
    let draftEngine: DraftEngine<
        AddStakeDraftRequest,
        ApiCheckTransactionDraftResult
    >

    var currentDraftRequest: AddStakeDraftRequest? {
        guard let amount, amount > 0 else { return nil }
        return AddStakeDraftRequest(
            accountId: $account.accountId,
            amount: amount,
            stakingState: stakingState
        )
    }

    var currentDraftSnapshot: OperationDraftSnapshot<
        AddStakeDraftRequest,
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
        let stakeOperationFee = getStakeOperationFee(stakingType: stakingState.type, stakeOperation: .stake).real
        return MFee(precision: .exact, terms: .init(token: nil, native: stakeOperationFee, stars: nil), nativeSum: stakeOperationFee)
    }
    
    var tokenChain: ApiChain? { baseToken.chain }
    
    // Validation

    var insufficientFunds: Bool = false
    var shouldRenderBalanceWithSmallFee = false
    
    var canContinue: Bool {
        !insufficientFunds && (amount ?? 0 > 0)
    }
    
    // MARK: - View callbacks
    
    func onBackgroundTapped() {
        topViewController()?.view.endEditing(true)
    }
        
    func onUseAll() {
        topViewController()?.view.endEditing(true)
        self.amount = maxAmount
        self.amountInBaseCurrency = convertAmount(maxAmount, price: baseToken.price ?? 0, tokenDecimals: baseToken.decimals, baseCurrencyDecimals: baseCurrency.decimalsCount)
        onAmountChanged?(amount)
    }
    
    // MARK: - Updates
    
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
