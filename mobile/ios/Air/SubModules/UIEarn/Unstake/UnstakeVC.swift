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
import Ledger
import WalletCore
import WalletContext
import UIPasscode

private let DAYS: Double = 24 * 3600


public class UnstakeVC: WViewController, WalletCoreData.EventsObserver {

    let model: UnstakeModel
    
    var config: StakingConfig { model.config }
    var stakingState: ApiStakingState { model.stakingState }
    
    var fakeTextField = UITextField(frame: .zero)
    private var continueButton: WButton { self.bottomButton! }
    private var taskError: BridgeCallError? = nil
    
    public init(config: StakingConfig, stakingState: ApiStakingState) {
        self.model = UnstakeModel(config: config, stakingState: stakingState)
        
        super.init(nibName: nil, bundle: nil)
        
        model.onAmountChanged = { [weak self] amount in
            self?.amountChanged(amount: amount)
        }
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
        
    public func walletCore(event: WalletCoreData.Event) {
        switch event {
        case .stakingAccountData(let data):
            if data.accountId == AccountStore.accountId {
                model.objectWillChange.send()
            }
        case .accountChanged:
            model.objectWillChange.send()
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
        
        title = lang("Unstake")
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
            UnstakeView(
                model: model,
                navigationBarInset: navigationBarHeight,
                onScrollPositionChange: { [weak self] y in
                    self?.navigationBar?.showSeparator = y < 0
                }
            ),
            constraints: { [self] v in
                NSLayoutConstraint.activate([
                    v.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                    v.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                    v.topAnchor.constraint(equalTo: view.topAnchor),
                    v.bottomAnchor.constraint(equalTo: view.bottomAnchor),
                ])
            }
        )
        hostingController.view.backgroundColor = WTheme.sheetBackground
        
        _ = addBottomButton()
        let title: String = lang("$unstake_asset", arg1: model.baseToken.symbol)
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
        
        let isLong = getIsLongUnstake(state: stakingState, amount: amount)
        let unlockTime = getUnstakeTime(state: stakingState)
        model.withdrawalType = if case .ethena = stakingState {
            .timed(7 * DAYS)
        } else if isLong == true, let unlockTime {
            .timed(unlockTime.timeIntervalSinceNow)
        } else {
            .instant
        }
        
        if let amount {
            let maxAmount = model.maxAmount
            let calculatedFee = getStakeOperationFee(stakingType: stakingState.type, stakeOperation: .stake).gas ?? 0
            let toncoinBalance = model.nativeBalance
            
            if amount > maxAmount {
                model.insufficientFunds = true
                continueButton.apply(config: .insufficientStakedBalance)
            } else if toncoinBalance < calculatedFee {
                model.insufficientFunds = true
                continueButton.apply(config: .insufficientFee(minAmount: calculatedFee))
            } else {
                model.insufficientFunds = false
                continueButton.apply(config: .continue(title: title, isEnabled: amount > 0))
            }
        } else {
            continueButton.isEnabled = false
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
            mode: .unstake,
            tokenAmount: TokenAmount(model.amount ?? 0, config.baseToken),
        )
        let headerVC = UIHostingController(rootView: headerView)
        headerVC.view.backgroundColor = .clear
        
        let amount = try model.amount.orThrow("invalid amount")
        let realFee = getStakeOperationFee(stakingType: stakingState.type, stakeOperation: .unstake).real

        do {
            try await self.pushAuthUsingPasswordOrLedger(
                title: lang("Confirm Unstaking"),
                headerView: headerView,
                passwordAction: { password in
                    _ = try await Api.submitUnstake(
                        accountId: account.id,
                        password: password,
                        amount: amount,
                        state: self.stakingState,
                        realFee: realFee
                    )
                },
                ledgerSignData: .staking(
                    isStaking: false,
                    accountId: account.id,
                    amount: amount,
                    stakingState: stakingState,
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
