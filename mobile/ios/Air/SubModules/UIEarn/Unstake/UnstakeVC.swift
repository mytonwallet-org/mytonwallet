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

private let DAYS: Double = 24 * 3600


public class UnstakeVC: WViewController, WalletCoreData.EventsObserver {

    let model: UnstakeModel
    @AccountContext private var account: MAccount
    
    var config: StakingConfig { model.config }
    var stakingState: ApiStakingState { model.stakingState }
    
    var fakeTextField = UITextField(frame: .zero)
    private var continueButton: WButton { self.bottomButton! }
    private var taskError: BridgeCallError? = nil
    private var awaitingActivity = false
    private var pendingActivityId: String?
    
    public init(config: StakingConfig, stakingState: ApiStakingState, accountContext: AccountContext) {
        self._account = accountContext
        self.model = UnstakeModel(config: config, stakingState: stakingState, accountContext: accountContext)
        
        super.init(nibName: nil, bundle: nil)
        WalletCoreData.add(eventObserver: self)
        
        model.onAmountChanged = { [weak self] amount in
            self?.amountChanged(amount: amount)
        }
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
        
    public func walletCore(event: WalletCoreData.Event) {
        switch event {
        case .newLocalActivity(let update):
            handleNewActivities(accountId: update.accountId, activities: update.activities)
        case .newActivities(let update):
            handleNewActivities(accountId: update.accountId, activities: update.activities)
        default:
            break
        }
    }

    private func handleNewActivities(accountId: String, activities: [ApiActivity]) {
        guard awaitingActivity, accountId == account.id else { return }
        let activity = activities.first(where: { $0.id == pendingActivityId }) ??
        activities.first(where: { $0.isStakingTransaction })
        guard let activity else { return }
        awaitingActivity = false
        pendingActivityId = nil
        AppActions.showActivityDetails(accountId: accountId, activity: activity, context: .unstakeRequestConfirmation)
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
        let headerView = StakingConfirmHeaderView(mode: .unstake,
                                                  tokenAmount: TokenAmount(model.amount ?? 0, config.baseToken))
        let headerVC = UIHostingController(rootView: headerView)
        headerVC.view.backgroundColor = .clear
        
        let realFee = getStakeOperationFee(stakingType: stakingState.type, stakeOperation: .unstake).real
        let stakingState = self.stakingState
        let submitAmount: BigInt = switch stakingState.type {
        case .nominators:
            stakingState.balance
        default:
            try (model.draft?.tokenAmount).orThrow()
        }

        do {
            awaitingActivity = true
            pendingActivityId = nil
            try await self.pushAuthUsingPasswordOrLedger(
                title: lang("Confirm Unstaking"),
                headerView: headerView,
                passwordAction: { [weak self] password in
                    let activityId = try await Api.submitUnstake(
                        accountId: account.id,
                        password: password,
                        amount: submitAmount,
                        state: stakingState,
                        realFee: realFee
                    )
                    await MainActor.run {
                        self?.pendingActivityId = activityId
                    }
                },
                ledgerSignData: .staking(
                    isStaking: false,
                    accountId: account.id,
                    amount: submitAmount,
                    stakingState: stakingState,
                    realFee: realFee
                )
            )
        } catch {
            awaitingActivity = false
            pendingActivityId = nil
            showAlert(error: error) { [weak self] in
                self?.navigationController?.popViewController(animated: true)
            }
        }
    }
}
