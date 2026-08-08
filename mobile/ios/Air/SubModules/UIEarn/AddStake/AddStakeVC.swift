//
//  StakingVC.swift
//  UIEarn
//
//  Created by Sina on 5/13/24.
//

import Foundation
import ProtectedAction
import SwiftUI
import UIComponents
import UIKit
import WalletContext
import WalletCore

public class AddStakeVC: WViewController {

    let model: AddStakeModel
    @AccountContext private var account: MAccount

    var config: StakingConfig { model.config }
    var stakingState: ApiStakingState { model.stakingState }

    var fakeTextField = UITextField(frame: .zero)
    private var continueButton: WButton?
    public init(config: StakingConfig, stakingState: ApiStakingState, accountContext: AccountContext) {
        _account = accountContext
        model = AddStakeModel(config: config, stakingState: stakingState, accountContext: accountContext)

        super.init(nibName: nil, bundle: nil)
        model.onAmountChanged = { [weak self] amount in
            self?.amountChanged(amount: amount)
        }
        model.onWhyIsSafe = { [weak self] in
            self?.view.endEditing(true)
            showWhyIsSafe(config: config)
        }
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
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

        title = lang("Add Stake")

        let hostingController = addHostingController(
            AddStakeView(model: model),
            constraints: .fill
        )
        hostingController.view.backgroundColor = .air.sheetBackground

        let continueButton = addBottomButton()
        self.continueButton = continueButton
        let title: String = lang("$stake_asset", arg1: model.baseToken.symbol)
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

    public override func viewDidAppear(_: Bool) {
        model.isAmountFieldFocused = true
    }

    func amountChanged(amount: BigInt?) {
        guard let continueButton else { return }

        guard let amount else {
            continueButton.isEnabled = false
            return
        }
        let minAmount = getStakingMinAmount(type: stakingState.type)
        let maxAmount = model.maxAmount
        let calculatedFee = getStakeOperationFee(stakingType: stakingState.type, stakeOperation: .stake).gas ?? 0
        let isNativeToken = model.isNativeToken
        let toncoinBalance = model.nativeBalance
        let isDraftReady = model.draft != nil && model.draftAmount == amount

        if amount < minAmount { // Insufficient min amount for staking
            model.insufficientFunds = true
            let symbol = model.baseToken.symbol
            continueButton.showLoading = false
            continueButton.setTitle("Minimum 1 \(symbol)", for: .normal)
            continueButton.isEnabled = false
        } else if amount > maxAmount {
            model.insufficientFunds = true
            let symbol = model.baseToken.symbol
            continueButton.showLoading = false
            continueButton.setTitle("Insufficient \(symbol) Balance", for: .normal)
            continueButton.isEnabled = false
        } else if !isNativeToken, toncoinBalance < calculatedFee {
            model.insufficientFunds = true
            continueButton.showLoading = false
            continueButton.apply(config: .insufficientFee(minAmount: minAmount))
        } else {
            model.insufficientFunds = false
            continueButton.showLoading = !isDraftReady
            continueButton.setTitle(title, for: .normal)
            continueButton.isEnabled = amount > 0 && isDraftReady
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
        let protectedAction = try ProtectedAction.stake(model: model, account: account)
        let outcome = await ProtectedActionExecutor.execute(protectedAction, on: self)
        guard case .completed = outcome else { return }
        // from user perspective staked token is automatically pinned to be shown in UI at top of tokens list
        AssetsAndActivityDataStore.update(accountId: account.id, update: { [slug = model.baseToken.slug] settings in
            settings.saveTokenPinning(slug: slug, isStaking: true, isPinned: true)
        })
    }
}
