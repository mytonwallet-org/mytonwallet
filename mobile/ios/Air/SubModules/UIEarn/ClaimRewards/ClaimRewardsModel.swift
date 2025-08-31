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

@MainActor final class ClaimRewardsModel: ObservableObject {
    
    @Published var stakingState: ApiStakingState?
    @Published var token: ApiToken = .TONCOIN
    @Published var amount: TokenAmount = TokenAmount(0, .TONCOIN)
    @Published var isConfirming: Bool = false
    var onClaim: () -> () = { }
    weak var viewController: UIViewController?
    private var claimRewardsError: BridgeCallError?
    private var observables: Set<AnyCancellable> = []
    
    init() {
        $stakingState
            .sink { [weak self] stakingState in
                guard let self else { return }
                if case .jetton(let jetton) = stakingState {
                    self.amount = TokenAmount(jetton.unclaimedRewards, token)
                }
            }
            .store(in: &observables)
    }
    
    // MARK: Confirm action
    
    func confirmAction(account: MAccount) async throws {
        guard let viewController else { return }
        let headerView = StakingConfirmHeaderView(
            mode: .claim,
            tokenAmount: amount,
        )
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
        let title = "Confirm Rewards Claim"
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
                    _ = try await Api.submitStakingClaimOrUnlock(accountId: AccountStore.accountId!, password: password, state: stakingState.orThrow(), realFee: getFee(.claimJettons).real)
                } catch {
                    self.claimRewardsError = .customMessage("\(error)", nil)
                }
                onTaskDone()
            }
            
        }, onDone: { _ in onDone() })
    }
    
    func confirmLedger(account: MAccount, title: String, headerView: StakingConfirmHeaderView, onDone: @escaping () -> ()) async throws {
        guard
            let account = AccountStore.account,
            let fromAddress = account.tonAddress?.nilIfEmpty,
            let ledger = account.ledger,
            let viewController
        else { return }
        
        let signModel = try await LedgerSignModel(
            accountId: account.id,
            fromAddress: fromAddress,
            ledger: ledger,
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
