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

private let log = Log("StakeUnstakeModel")

// display available amount
// actual available (incl. for fees)
// display token
// actual token
//

@MainActor
final class UnstakeModel: ObservableObject, WalletCoreData.EventsObserver {
    
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
    @Published var stakedTokenBalance: BigInt = 0
    var baseCurrency: MBaseCurrency { TokenStore.baseCurrency }
    
    public func walletCore(event: WalletCoreData.Event) {
        switch event {
        case .balanceChanged, .tokensChanged:
            updateAccountBalances()
        default:
            break
        }
    }
    
    func updateAccountBalances() {
        let nativeBalance = BalanceStore.currentAccountBalances[nativeTokenSlug] ?? 0
        let stakedTokenBalance = StakingStore.currentAccount?.byStakedSlug(stakedTokenSlug)?.balance ?? .zero
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
    
    // User input
    
    @Published var switchedToBaseCurrencyInput: Bool = false
    @Published var amount: BigInt? = nil
    @Published var amountInBaseCurrency: BigInt? = nil
    @Published var isAmountFieldFocused: Bool = false
    
    // Wallet state
    
    var baseToken: ApiToken { config.baseToken }
    var stakedToken: ApiToken { config.stakedToken }
    var nativeTokenSlug: String { config.nativeTokenSlug }
    var stakedTokenSlug: String { config.stakedTokenSlug }

    @Published var draft: ApiCheckTransactionDraftResult?
    
    var fee: MFee? {
        let stakeOperationFee = getStakeOperationFee(stakingType: stakingState.type, stakeOperation: .unstake).real
        return MFee(precision: .exact, terms: .init(token: nil, native: stakeOperationFee, stars: nil), nativeSum: stakeOperationFee)
    }
    
    var tokenChain: ApiChain? { availableChain(slug: baseToken.chain) }
    
    // Validation

    @Published var insufficientFunds: Bool = false

    @Published var shouldRenderBalanceWithSmallFee = false
    
    enum WithdrawalType {
        case instant
        case loading
        case timed(TimeInterval)
    }
    @Published var withdrawalType: WithdrawalType = .instant
    
    var canContinue: Bool {
        !insufficientFunds && (amount ?? 0 > 0)
    }
    
    private var observers: Set<AnyCancellable> = []
        
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

    func updateFee() async {
        if let accountId = AccountStore.accountId, let amount = amount {
            do {
                let draft: ApiCheckTransactionDraftResult = try await Api.checkUnstakeDraft(accountId: accountId, amount: amount, state: stakingState)
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
