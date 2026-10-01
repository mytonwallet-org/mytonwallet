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
    private var continueButtonPresenter: DraftButtonPresenter?
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
        continueButtonPresenter = DraftButtonPresenter(button: continueButton)
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
        guard let continueButtonPresenter else { return }
        
        let isLong = getIsLongUnstake(state: stakingState, amount: amount)
        let unlockTime = getUnstakeTime(state: stakingState)
        model.withdrawalType = if case .ethena = stakingState {
            .timed(7 * DAYS)
        } else if isLong == true, let unlockTime {
            .timed(unlockTime.timeIntervalSinceNow)
        } else {
            .instant
        }
        
        continueButtonPresenter.apply(buttonConfiguration(amount: amount))
    }

    private func buttonConfiguration(amount: BigInt?) -> DraftButtonConfiguration {
        let title = L10n.unstakeAsset(symbol: model.baseToken.symbol)
        if isConfirming {
            return .init(title: .text(title), isEnabled: false, showLoading: true)
        }
        model.insufficientFunds = false
        guard let amount, amount > 0 else {
            return .init(title: .text(title), isEnabled: false, showLoading: false)
        }
        let calculatedFee = getStakeOperationFee(stakingType: stakingState.type, stakeOperation: .unstake).gas ?? 0
        if amount > model.maxAmount {
            model.insufficientFunds = true
            return .init(title: .text(lang("Insufficient Balance")), isEnabled: false, showLoading: false)
        }
        if model.nativeBalance < calculatedFee {
            model.insufficientFunds = true
            return .insufficientStakingFee(minAmount: calculatedFee)
        }
        return .staking(title: title, phase: model.draftPhase, canRetry: model.canRetryDraft, draftError: model.draft?.error)
    }

    @objc func continuePressed() {
        guard !isConfirming else { return }
        view.endEditing(true)
        if model.canRetryDraft {
            model.retryDraft()
            return
        }
        guard model.canContinue, model.draftPhase == .ready else { return }
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
