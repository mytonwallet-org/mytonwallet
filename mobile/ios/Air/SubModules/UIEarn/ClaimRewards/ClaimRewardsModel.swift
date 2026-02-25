//
//  ClaimRewardsModel.swift
//  UIEarn
//
//  Created by nikstar on 21.07.2025.
//

import SwiftUI
import WalletContext
import WalletCore
import UIPasscode
import Ledger
import Combine
import Perception
import SwiftNavigation

@MainActor
@Perceptible
final class ClaimRewardsModel {
    
    var stakingState: ApiStakingState?
    var token: ApiToken = .TONCOIN
    var amount: TokenAmount = TokenAmount(0, .TONCOIN)
    var isConfirming: Bool = false
    @PerceptionIgnored
    var onClaim: () -> () = { }
    @PerceptionIgnored
    weak var viewController: UIViewController?
    @PerceptionIgnored
    private var claimRewardsError: BridgeCallError?
    @PerceptionIgnored
    private var observeToken: ObserveToken?
    @PerceptionIgnored
    @AccountContext private var account: MAccount
    var accountContext: AccountContext { $account }
    
    init(accountContext: AccountContext) {
        self._account = accountContext
        observeToken = observe { [weak self] in
            guard let self else { return }
            switch stakingState {
            case .jetton(let jetton):
                amount = TokenAmount(jetton.unclaimedRewards, token)
            case .ethena(let ethena):
                amount = TokenAmount(ethena.unstakeRequestAmount ?? 0, token)
            case .liquid, .nominators, .unknown, nil:
                break
            }
        }
    }
    
    // MARK: Confirm action
    
    func confirmAction(account: MAccount) async throws {
        guard let viewController else { return }
        let headerView = StakingConfirmHeaderView(mode: token.slug == TON_USDE_SLUG ? .unstake : .claim,
                                                  tokenAmount: amount)
        let headerVC = UIHostingController(rootView: headerView)
        headerVC.view.backgroundColor = .clear
        
        self.claimRewardsError = nil
        
        let onDone: () -> () = { [weak self] in
                guard let self else { return }
                
                if let claimRewardsError {
                    viewController.showAlert(error: claimRewardsError) {
                        viewController.navigationController?.popViewController(animated: true)
                    }
                } else {
                    viewController.navigationController?.popToRootViewController(animated: true)
                }
        }
        let title = token.slug == TON_USDE_SLUG ? lang("Confirm Unstaking") : lang("Confirm Rewards Claim")
        if account.isHardware {
            try await confirmLedger(account: account, title: title, headerView: headerView, onDone: onDone)
        } else {
            confirmMnemonic(account: account, title: title, headerVC: headerVC, onDone: onDone)
        }
    }
    
    func confirmMnemonic(account: MAccount, title: String, headerVC: UIHostingController<StakingConfirmHeaderView>, onDone: @escaping () -> ()) {
        guard let viewController else { return }
        UnlockVC.pushAuth(on: viewController,
                          title: title,
                          customHeaderVC: headerVC,
                          onAuthTask: { [weak self, stakingState] password, onTaskDone in
            guard let self else { return }
            Task {
                do {
                    _ = try await Api.submitStakingClaimOrUnlock(accountId: account.id, password: password, state: stakingState.orThrow(), realFee: getFee(.claimJettons).real)
                } catch {
                    self.claimRewardsError = .customMessage("\(error)", nil)
                }
                onTaskDone()
            }
            
        }, onDone: { _ in onDone() })
    }
    
    func confirmLedger(account: MAccount, title: String, headerView: StakingConfirmHeaderView, onDone: @escaping () -> ()) async throws {
        guard let viewController else { return }
        
        let signModel = try await LedgerSignModel(
            accountId: account.id,
            fromAddress: account.firstAddress,
            signData: SignData.submitStakingClaimOrUnlock(
                accountId: account.id,
                state: stakingState.orThrow(),
                realFee: getFee(.claimJettons).real
            )
        )
        let vc = LedgerSignVC(
            model: signModel,
            title: lang("Confirm Sending"),
            headerView: headerView
        )
        vc.onDone = { _ in onDone() }
        viewController.navigationController?.pushViewController(vc, animated: true)
    }
}
