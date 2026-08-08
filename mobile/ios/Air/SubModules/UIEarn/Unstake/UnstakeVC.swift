//
//  StakingVC.swift
//  UIEarn
//
//  Created by Sina on 5/13/24.
//

import Foundation
import ProtectedAction
import SwiftUI
import UIKit
import UIComponents
import WalletCore
import WalletContext

private let DAYS: Double = 24 * 3600


public class UnstakeVC: WViewController {

    let model: UnstakeModel
    @AccountContext private var account: MAccount
    
    var config: StakingConfig { model.config }
    var stakingState: ApiStakingState { model.stakingState }
    
    var fakeTextField = UITextField(frame: .zero)
    private var continueButton: WButton?
    public init(config: StakingConfig, stakingState: ApiStakingState, accountContext: AccountContext) {
        self._account = accountContext
        self.model = UnstakeModel(config: config, stakingState: stakingState, accountContext: accountContext)
        
        super.init(nibName: nil, bundle: nil)
        model.onAmountChanged = { [weak self] amount in
            self?.amountChanged(amount: amount)
        }
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
        
    public override func viewDidLoad() {
        super.viewDidLoad()
        setupViews()
        observe { [weak self] in
            guard let self else { return }
            _ = model.draft
            _ = model.draftAmount
            amountChanged(amount: model.amount)
        }
    }
    
    private func setupViews() {
        
        title = lang("Unstake")

        let hostingController = addHostingController(
            UnstakeView(model: model),
            constraints: { [self] v in
                NSLayoutConstraint.activate([
                    v.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                    v.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                    v.topAnchor.constraint(equalTo: view.topAnchor),
                    v.bottomAnchor.constraint(equalTo: view.bottomAnchor),
                ])
            }
        )
        hostingController.view.backgroundColor = .air.sheetBackground
        
        let continueButton = addBottomButton()
        self.continueButton = continueButton
        let title: String = lang("$unstake_asset", arg1: model.baseToken.symbol)
        continueButton.setTitle(title, for: .normal)
        continueButton.addTarget(self, action: #selector(continuePressed), for: .touchUpInside)
        continueButton.isEnabled = false
        
        fakeTextField.keyboardType = .decimalPad
        if #available(iOS 18.0, *) {
            fakeTextField.writingToolsBehavior = .none
        }
        view.addSubview(fakeTextField)

        amountChanged(amount: nil)
    }
    
    public override func viewDidAppear(_ animated: Bool) {
        model.isAmountFieldFocused = true
    }
    
    func amountChanged(amount: BigInt?) {
        guard let continueButton else { return }
        
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
            let calculatedFee = getStakeOperationFee(stakingType: stakingState.type, stakeOperation: .unstake).gas ?? 0
            let nativeBalance = model.nativeBalance
            let isDraftReady = model.draft != nil && model.draftAmount == amount
            
            if amount > maxAmount {
                model.insufficientFunds = true
                continueButton.showLoading = false
                continueButton.apply(config: .insufficientStakedBalance)
            } else if nativeBalance < calculatedFee {
                model.insufficientFunds = true
                continueButton.showLoading = false
                continueButton.apply(config: .insufficientFee(minAmount: calculatedFee))
            } else {
                model.insufficientFunds = false
                continueButton.showLoading = !isDraftReady
                continueButton.apply(config: .continue(title: title, isEnabled: amount > 0 && isDraftReady))
            }
        } else {
            continueButton.showLoading = false
            continueButton.isEnabled = false
        }
    }
    
    @objc func continuePressed() {
        view.endEditing(true)
        Task {
            do {
                try await confirmAction(account: account)
            } catch {
                showAlert(error: error)
            }
        }
    }
    
    func confirmAction(account: MAccount) async throws {
        let protectedAction = try ProtectedAction.unstake(model: model, account: account)
        _ = await ProtectedActionExecutor.execute(protectedAction, on: self)
    }
}
