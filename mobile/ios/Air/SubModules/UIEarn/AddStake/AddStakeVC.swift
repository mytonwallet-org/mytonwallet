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
import UIPasscode


public class AddStakeVC: WViewController, WalletCoreData.EventsObserver {

    let model: AddStakeModel
    
    var config: StakingConfig { model.config }
    var stakingState: ApiStakingState { model.stakingState }
    
    var fakeTextField = UITextField(frame: .zero)
    private var continueButton: WButton { self.bottomButton! }
    private var taskError: BridgeCallError? = nil
    
    public init(config: StakingConfig, stakingState: ApiStakingState) {
        self.model = AddStakeModel(config: config, stakingState: stakingState)
        
        super.init(nibName: nil, bundle: nil)
        
        model.onAmountChanged = { [weak self] amount in
            self?.amountChanged(amount: amount)
        }
        model.onWhyIsSafe = { [weak self] in
            self?.view.endEditing(true)
            showWhyIsSafe(config: config)
        }
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    
    public func walletCore(event: WalletCoreData.Event) {
        switch event {
        default:
            break
        }
    }
    
    public override func viewDidLoad() {
        super.viewDidLoad()
        setupViews()
        
        // observe keyboard events
//        WKeyboardObserver.observeKeyboard(delegate: self)
    }
    
    private func setupViews() {
        
        title = lang("Add Stake")
        addNavigationBar(
            topOffset: 1,
            title: title,
            closeIcon: true,
            addBackButton: { [weak self] in
                self?.view.endEditing(true)
                self?.navigationController?.popViewController(animated: true)
            }
        )

        let hostingController = addHostingController(
            AddStakeView(
                model: model,
                navigationBarInset: navigationBarHeight,
                onScrollPositionChange: { [weak self] y in
                    self?.navigationBar?.showSeparator = y < 0
                }
            ),
            constraints: .fill
        )
        hostingController.view.backgroundColor = WTheme.sheetBackground
        
        _ = addBottomButton()
        let title: String = lang("$stake_asset", arg1: model.baseToken.symbol)
        continueButton.setTitle(title, for: .normal)
        continueButton.addTarget(self, action: #selector(continuePressed), for: .touchUpInside)
        continueButton.isEnabled = false
        
        fakeTextField.keyboardType = .decimalPad
        if #available(iOS 18.0, *) {
            fakeTextField.writingToolsBehavior = .none
        }
        view.addSubview(fakeTextField)
        
        bringNavigationBarToFront()

        updateTheme()
        
        amountChanged(amount: nil)
    }
    
    public override func viewDidAppear(_ animated: Bool) {
        model.isAmountFieldFocused = true
    }
    
    public override func updateTheme() {
    }
    
    func amountChanged(amount: BigInt?) {
        
        guard let amount else {
            continueButton.isEnabled = false
            return
        }
        let minAmount = getStakingMinAmount(type: stakingState.type)
        let maxAmount = model.maxAmount
        let calculatedFee = getStakeOperationFee(stakingType: stakingState.type, stakeOperation: .stake).gas ?? 0
        let isNativeToken = model.isNativeToken
        let toncoinBalance = model.nativeBalance
        
        if amount < minAmount { // Insufficient min amount for staking
            model.insufficientFunds = true
            let symbol = model.baseToken.symbol
            continueButton.setTitle("Minimum 1 \(symbol)", for: .normal)
            continueButton.isEnabled = false
        } else if amount > maxAmount {
            model.insufficientFunds = true
            let symbol = model.baseToken.symbol
            continueButton.setTitle("Insufficient \(symbol) Balance", for: .normal)
            continueButton.isEnabled = false
        } else if !isNativeToken && toncoinBalance < calculatedFee {
            model.insufficientFunds = true
            continueButton.apply(config: .insufficientFee(minAmount: minAmount))
        } else {
            model.insufficientFunds = false
            continueButton.setTitle(self.title, for: .normal)
            continueButton.isEnabled = amount > 0
        }
    }
    
    @objc func continuePressed() {
        view.endEditing(true)
        guard let account = AccountStore.account else { return }
        Task {
            do {
                try await confirmAction(account: account)
            } catch {
                showAlert(error: error)
            }
        }
    }
    
    func confirmAction(account: MAccount) async throws {
        let headerView = StakingConfirmHeaderView(
            mode: .stake,
            tokenAmount: TokenAmount(model.amount ?? 0, model.baseToken),
        )
        let headerVC = UIHostingController(rootView: headerView)
        headerVC.view.backgroundColor = .clear
        
        let amount = try model.amount.orThrow("invalid amount")
        let realFee = getStakeOperationFee(stakingType: stakingState.type, stakeOperation: .stake).real
        
        do {
            try await self.pushAuthUsingPasswordOrLedger(
                title: lang("Confirm Staking"),
                headerView: headerView,
                passwordAction: { password in
                    _ = try await Api.submitStake(
                        accountId: account.id,
                        password: password,
                        amount: amount,
                        state: self.model.stakingState,
                        realFee: realFee
                    )
                },
                ledgerSignData: .staking(
                    isStaking: true,
                    accountId: account.id,
                    amount: amount,
                    stakingState: self.model.stakingState,
                    realFee: realFee
                )
            )
            navigationController?.popToRootViewController(animated: true)
        } catch {
            showAlert(error: error) { [weak self] in
                self?.navigationController?.popViewController(animated: true)
            }
        }
    }
}
