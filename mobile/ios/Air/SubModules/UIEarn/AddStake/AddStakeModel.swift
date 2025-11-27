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
import UIPasscode

private let log = Log("StakeUnstakeModel")

@MainActor
final class AddStakeModel: ObservableObject, WalletCoreData.EventsObserver {
    
    let config: StakingConfig
    
    public init(config: StakingConfig, stakingState: ApiStakingState) {
        self.config = config
        self.stakingState = stakingState
        updateAccountBalances()
        WalletCoreData.add(eventObserver: self)
    }
    
    // MARK: External dependencies
    
    @Published var stakingState: ApiStakingState
    @Published var nativeBalance: BigInt = 0
    @Published var baseTokenBalance: BigInt = 0
    var baseCurrency: MBaseCurrency { TokenStore.baseCurrency }

    public func walletCore(event: WalletCoreData.Event) {
        switch event {
        case .balanceChanged, .tokensChanged:
            updateAccountBalances()
        case .stakingAccountData(let data):
            if data.accountId == AccountStore.accountId {
                if let stakingState = config.stakingState {
                    self.stakingState = stakingState
                }
            }
        default:
            break
        }
    }
    
    func updateAccountBalances() {
        let nativeBalance = BalanceStore.currentAccountBalances[nativeTokenSlug] ?? 0
        let baseTokenBalance = BalanceStore.currentAccountBalances[tokenSlug] ?? 0
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
    
    @Published var switchedToBaseCurrencyInput: Bool = false
    @Published var amount: BigInt? = nil
    @Published var amountInBaseCurrency: BigInt? = nil
    @Published var isAmountFieldFocused: Bool = false
    
    // MARK: Wallet state
    
    var baseToken: ApiToken { config.baseToken }
    var nativeTokenSlug: String { config.nativeTokenSlug }
    var tokenSlug: String { baseToken.slug }
    
    @Published var draft: ApiCheckTransactionDraftResult?
    
    var fee: MFee? {
        let stakeOperationFee = getStakeOperationFee(stakingType: stakingState.type, stakeOperation: .stake).real
        return MFee(precision: .exact, terms: .init(token: nil, native: stakeOperationFee, stars: nil), nativeSum: stakeOperationFee)
    }
    
    var tokenChain: ApiChain? { availableChain(slug: baseToken.chain) }
    
    // Validation

    @Published var insufficientFunds: Bool = false
    @Published var shouldRenderBalanceWithSmallFee = false
    
    var canContinue: Bool {
        !insufficientFunds && (amount ?? 0 > 0)
    }
    
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
        self.amountInBaseCurrency = convertAmount(amount, price: price, tokenDecimals: baseToken.decimals, baseCurrencyDecimals: TokenStore.baseCurrency.decimalsCount)
        onAmountChanged?(amount)
    }
    
    func updateAmountFromBaseCurrency(_ baseCurrency: BigInt) {
        let price = config.baseToken.price ?? 0
        let baseCurrencyDecimals = TokenStore.baseCurrency.decimalsCount
        if price > 0 {
            self.amount = convertAmountReverse(baseCurrency, price: price, tokenDecimals: baseToken.decimals, baseCurrencyDecimals: baseCurrencyDecimals)
        } else {
            self.amount = 0
            self.switchedToBaseCurrencyInput = false
        }
        onAmountChanged?(amount)
    }

    func updateFee() async {
        if let accountId = AccountStore.accountId, let amount = amount {
            do {
                let draft: ApiCheckTransactionDraftResult =  try await Api.checkStakeDraft(accountId: accountId, amount: amount, state: stakingState)
                try handleDraftError(draft)
                if Task.isCancelled {
                    if self.draft == nil {
                        self.draft = draft
                    }
                    return
                }
                self.draft = draft
            } catch {
                if !Task.isCancelled {
                    topViewController()?.showAlert(error: error)
                }
                log.info("\(error)")
            }
        }
    }
}
