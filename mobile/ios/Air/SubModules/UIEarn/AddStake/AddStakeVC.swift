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
import WalletCoreTypes

public class AddStakeVC: WViewController {

    let model: AddStakeModel
    @AccountContext private var account: MAccount

    var config: StakingConfig { model.config }
    var stakingState: ApiStakingState { model.stakingState }
    private var stakeTitle: String { L10n.stakeAsset(symbol: model.baseToken.symbol) }

    var fakeTextField = UITextField(frame: .zero)
    private var continueButtonPresenter: DraftButtonPresenter?
    private var isConfirming = false
    private var foreignUnstakeTask: Task<Void, Never>?
    public init(
        config: StakingConfig,
        stakingState: ApiStakingState,
        accountContext: AccountContext,
        prefilledAmount: StakePrefilledAmount? = nil
    ) {
        _account = accountContext
        model = AddStakeModel(config: config, stakingState: stakingState, accountContext: accountContext)
        switch prefilledAmount {
        case .exact(let value):
            model.amount = MDouble(value)?.bigintAmount(decimals: model.baseToken.decimals)
        case .all:
            model.amount = model.maxAmount
        case nil:
            break
        }

        super.init(nibName: nil, bundle: nil)
        model.onAmountChanged = { [weak self] amount in
            self?.amountChanged(amount: amount)
        }
        model.onWhyIsSafe = { [weak self] in
            self?.view.endEditing(true)
            showWhyIsSafe(config: config)
        }
        model.onDraftFailure = { error in
            AppActions.showError(error: error)
        }
        model.onForeignUnstake = { [weak self] promotion in
            self?.confirmForeignUnstake(promotion)
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
            _ = model.draftPhase
            amountChanged(amount: model.amount)
        }
    }

    private func setupViews() {

        title = lang("Add Stake")
        addCloseNavigationItemIfNeeded()

        let hostingController = addHostingController(
            AddStakeView(model: model),
            constraints: .fill
        )
        hostingController.view.backgroundColor = .air.sheetBackground

        let continueButton = addBottomButton()
        continueButtonPresenter = DraftButtonPresenter(button: continueButton)
        continueButton.accessibilityIdentifier = "stake_submit"
        continueButton.setTitle(stakeTitle, for: .normal)
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

    public override func viewDidAppear(_: Bool) {
        model.isAmountFieldFocused = true
    }

    public override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if isBeingDismissed || isMovingFromParent || navigationController?.isBeingDismissed == true {
            foreignUnstakeTask?.cancel()
        }
    }

    private func confirmForeignUnstake(_ promotion: ApiPromotion) {
        guard foreignUnstakeTask == nil, !isConfirming,
              model.foreignStakingBanners.first?.id == promotion.id,
              let action = promotion.infoBanner?.actionButton,
              action.onClickAction == .unstakeForeign,
              let chain = action.chain, let providerName = action.providerName else { return }
        let account = account
        let banners = $account.config.banners
        model.foreignUnstakeLoadingId = promotion.id
        foreignUnstakeTask = Task { [weak self] in
            guard let self else { return }
            defer {
                model.foreignUnstakeLoadingId = nil
                foreignUnstakeTask = nil
            }
            do {
                let draft = try await Api.checkForeignUnstakeDraft(accountId: account.id, chain: chain, providerName: providerName)
                try Task.checkCancellation()
                guard self.account.id == account.id,
                      model.foreignStakingBanners.contains(where: { $0.id == promotion.id }) else { return }
                view.endEditing(true)
                let action = ProtectedAction.foreignUnstake(account: account, chain: chain, providerName: providerName, draft: draft)
                let outcome = await ProtectedActionExecutor.execute(action, on: self)
                guard case .completed = outcome else { return }
                banners.didSubmitUnstake(id: promotion.id)
                if !draft.isInstant, self.account.id == account.id, viewIfLoaded?.window != nil {
                    navigationController?.dismiss(animated: true)
                }
            } catch is CancellationError {
            } catch {
                guard !Task.isCancelled, self.account.id == account.id else { return }
                showAlert(error: error)
            }
        }
    }

    func amountChanged(amount: BigInt?) {
        guard let continueButtonPresenter else { return }
        continueButtonPresenter.apply(buttonConfiguration(amount: amount))
    }

    private func buttonConfiguration(amount: BigInt?) -> DraftButtonConfiguration {
        if isConfirming {
            return .init(title: .text(stakeTitle), isEnabled: false, showLoading: true)
        }
        model.insufficientFunds = false
        model.insufficientFee = false
        guard account.supportsEarn, let amount, amount > 0 else {
            return .init(title: .text(stakeTitle), isEnabled: false, showLoading: false)
        }
        let minAmount = getStakingMinAmount(type: stakingState.type)
        let calculatedFee = getStakeOperationFee(stakingType: stakingState.type, stakeOperation: .stake).gas ?? 0
        if amount < minAmount {
            model.insufficientFunds = true
            return .init(title: .text("Minimum 1 \(model.baseToken.symbol)"), isEnabled: false, showLoading: false)
        }
        if amount > model.maxAmount {
            model.insufficientFunds = true
            return .init(title: .text("Insufficient \(model.baseToken.symbol) Balance"), isEnabled: false, showLoading: false)
        }
        if !model.isNativeToken, model.nativeBalance < calculatedFee {
            model.insufficientFee = true
            return .insufficientStakingFee()
        }
        return .staking(title: stakeTitle, phase: model.draftPhase, canRetry: model.canRetryDraft, draftError: model.draft?.error)
    }

    @objc func continuePressed() {
        guard !isConfirming, foreignUnstakeTask == nil else { return }
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
        let protectedAction = try ProtectedAction.stake(model: model, account: account)
        let outcome = await ProtectedActionExecutor.execute(protectedAction, on: self)
        guard case .completed = outcome else { return }
        // from user perspective staked token is automatically pinned to be shown in UI at top of tokens list
        AssetsAndActivityDataStore.update(accountId: account.id, update: { [slug = model.baseToken.slug] settings in
            settings.saveTokenPinning(slug: slug, isStaking: true, isPinned: true)
        })
    }
}
