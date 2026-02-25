//
//  StakingVC.swift
//  UIEarn
//
//  Created by Sina on 5/13/24.
//

import Foundation
import SwiftUI
import UIComponents
import UIKit
import UIPasscode
import WalletContext
import WalletCore

public class AddStakeVC: WViewController, WalletCoreData.EventsObserver {

    let model: AddStakeModel
    @AccountContext private var account: MAccount

    var config: StakingConfig { model.config }
    var stakingState: ApiStakingState { model.stakingState }

    var fakeTextField = UITextField(frame: .zero)
    private var continueButton: WButton { bottomButton! }
    private var taskError: BridgeCallError?
    private var awaitingActivity = false
    private var pendingActivityId: String?

    public init(config: StakingConfig, stakingState: ApiStakingState, accountContext: AccountContext) {
        _account = accountContext
        model = AddStakeModel(config: config, stakingState: stakingState, accountContext: accountContext)

        super.init(nibName: nil, bundle: nil)
        WalletCoreData.add(eventObserver: self)

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
        AppActions.showActivityDetails(accountId: accountId, activity: activity, context: .stakeConfirmation)
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

    public override func viewDidAppear(_: Bool) {
        model.isAmountFieldFocused = true
    }

    public override func updateTheme() {}

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
        let headerView = StakingConfirmHeaderView(mode: .stake,
                                                  tokenAmount: TokenAmount(model.amount ?? 0, model.baseToken))
        let headerVC = UIHostingController(rootView: headerView)
        headerVC.view.backgroundColor = .clear

        let amount = try model.amount.orThrow("invalid amount")
        let realFee = getStakeOperationFee(stakingType: stakingState.type, stakeOperation: .stake).real
        let stakingState = model.stakingState

        do {
            awaitingActivity = true
            pendingActivityId = nil
            try await pushAuthUsingPasswordOrLedger(
                title: lang("Confirm Staking"),
                headerView: headerView,
                passwordAction: { [weak self] password in
                    let activityId = try await Api.submitStake(
                        accountId: account.id,
                        password: password,
                        amount: amount,
                        state: stakingState,
                        realFee: realFee
                    )
                    await MainActor.run {
                        self?.pendingActivityId = activityId
                    }
                },
                ledgerSignData: .staking(
                    isStaking: true,
                    accountId: account.id,
                    amount: amount,
                    stakingState: model.stakingState,
                    realFee: realFee
                )
            )
            // from user perspective staked token is automatically pinned to be shown in UI at top of tokens list
            AccountStore.updateAssetsAndActivityData(forAccountID: account.id, update: { settings in
                settings.saveTokenPinning(slug: model.baseToken.slug, isStaking: true, isPinned: true)
            })
        } catch {
            awaitingActivity = false
            pendingActivityId = nil
            showAlert(error: error) { [weak self] in
                self?.navigationController?.popViewController(animated: true)
            }
        }
    }
}
