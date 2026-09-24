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
    private var isConfirming = false
    public init(config: StakingConfig, stakingState: ApiStakingState, accountContext: AccountContext) {
        self._account = accountContext
        self.model = UnstakeModel(config: config, stakingState: stakingState, accountContext: accountContext)
        
        super.init(nibName: nil, bundle: nil)
        model.onAmountChanged = { [weak self] amount in
            self?.amountChanged(amount: amount)
        }
        model.onDraftFailure = { error in
            AppActions.showError(error: error)
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
            _ = model.draftPhase
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
        let title: String = L10n.unstakeAsset(symbol: model.baseToken.symbol)
        continueButton.setTitle(title, for: .normal)
        continueButton.addTarget(self, action: #selector(continuePressed), for: .touchUpInside)
        continueButton.isEnabled = false
        
        fakeTextField.keyboardType = .decimalPad
        if #available(iOS 18.0, *) {
            fakeTextField.writingToolsBehavior = .none
        }
        view.addSubview(fakeTextField)

        amountChanged(amount: nil)
        addCustomNavigationBarBackground(color: .air.sheetBackground)
    }
    
    public override func viewDidAppear(_ animated: Bool) {
        model.isAmountFieldFocused = true
    }
    
    func amountChanged(amount: BigInt?) {
        guard let continueButton else { return }
        if isConfirming {
            continueButton.showLoading = true
            continueButton.isEnabled = false
            return
        }
        let buttonTitle = L10n.unstakeAsset(symbol: model.baseToken.symbol)
        
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
            let isDraftReady = model.draftPhase == .ready
                && model.draft != nil
            
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
                switch model.draftPhase {
                case .loading:
                    continueButton.showLoading = true
                    continueButton.apply(
                        config: .continue(
                            title: buttonTitle,
                            isEnabled: false
                        )
                    )
                case .failed:
                    continueButton.showLoading = false
                    continueButton.apply(
                        config: .continue(
                            title: lang("Retry"),
                            isEnabled: model.canRetryDraft
                        )
                    )
                case .ready:
                    continueButton.showLoading = false
                    continueButton.apply(
                        config: .continue(
                            title: buttonTitle,
                            isEnabled: amount > 0 && isDraftReady
                        )
                    )
                case .idle:
                    continueButton.showLoading = false
                    continueButton.apply(
                        config: .continue(
                            title: buttonTitle,
                            isEnabled: false
                        )
                    )
                }
            }
        } else {
            continueButton.showLoading = false
            continueButton.isEnabled = false
        }
    }
    
    @objc func continuePressed() {
        guard !isConfirming else { return }
        view.endEditing(true)
        if model.canRetryDraft {
            model.retryDraft()
            return
        }
        isConfirming = true
        amountChanged(amount: model.amount)
        Task {
            defer {
                isConfirming = false
                amountChanged(amount: model.amount)
            }
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
