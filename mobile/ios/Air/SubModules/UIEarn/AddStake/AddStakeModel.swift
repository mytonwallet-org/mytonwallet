//
//  StakingVC.swift
//  UIEarn
//
//  Created by Sina on 5/13/24.
//

import Combine
import Foundation
import SwiftUI
import UIKit
import UIComponents
import WalletCore
import WalletContext
import Perception
import SwiftNavigation

private let log = Log("AddStakeModel")

@MainActor @Perceptible
final class AddStakeModel: WalletCoreData.EventsObserver {
    
    let config: StakingConfig
    @PerceptionIgnored
    @AccountContext private var account: MAccount
    
    public init(config: StakingConfig, stakingState: ApiStakingState, accountContext: AccountContext) {
        self.config = config
        self.stakingState = stakingState
        self._account = accountContext
        updateAccountBalances()
        WalletCoreData.add(eventObserver: self)
    }
    
    // MARK: External dependencies
    
    var stakingState: ApiStakingState
    var nativeBalance: BigInt = 0
    var baseTokenBalance: BigInt = 0
    var baseCurrency: MBaseCurrency { TokenStore.baseCurrency }

    public func walletCore(event: WalletCoreData.Event) {
        switch event {
        case .balanceChanged, .tokensChanged:
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
    var type: ApiStakingType { stakingState.type }

    var isNativeToken: Bool {
        baseToken.slug == nativeTokenSlug
    }
    
    var minAmount: BigInt { getStakingMinAmount(type: type) }
    
    var fees: TonOperationFees { getStakeOperationFee(stakingType: type, stakeOperation: .stake) }
    var networkFee: BigInt { fees.gas.orZero }
    var realFee: BigInt { fees.real.orZero }
    
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
    
    // MARK: User input
    
    var switchedToBaseCurrencyInput: Bool = false
    var amount: BigInt? = nil {
        didSet {
            if oldValue != amount {
                draft = nil
                draftAmount = nil
            }
        }
    }
    var amountInBaseCurrency: BigInt? = nil
    var isAmountFieldFocused: Bool = false
    
    // MARK: Wallet state
    
    var baseToken: ApiToken { config.baseToken }
    var nativeTokenSlug: String { config.nativeTokenSlug }
    var tokenSlug: String { baseToken.slug }
    
    var draft: ApiCheckTransactionDraftResult?
    var draftAmount: BigInt?
    
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
    
    @PerceptionIgnored
    private var observers: Set<AnyCancellable> = []
    
    
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

    func updateFee() async {
        guard let amount else {
            draft = nil
            draftAmount = nil
            return
        }
        draft = nil
        draftAmount = nil
        do {
            let draft =  try await Api.checkStakeDraft(accountId: account.id, amount: amount, state: stakingState)
            try handleDraftError(draft)
            guard !Task.isCancelled, self.amount == amount else { return }
            self.draft = draft
            self.draftAmount = amount
        } catch {
            if !Task.isCancelled {
                AppActions.showError(error: error)
            }
        }
    }
}
