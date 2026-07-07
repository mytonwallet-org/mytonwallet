//
//  ClaimRewardsModel.swift
//  UIEarn
//
//  Created by nikstar on 21.07.2025.
//

import SwiftUI
import UIComponents
import WalletContext
import WalletCore
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
    private var claimRewardsError: (any Error)?
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
        guard let viewController = viewController as? WViewController else { return }
        let headerView = StakingConfirmHeaderView(mode: token.slug == TON_USDE_SLUG ? .unstake : .claim,
                                                  tokenAmount: amount)
        
        self.claimRewardsError = nil
        
        let onDone: @MainActor () -> () = { [weak self, weak viewController] in
            guard let self, let viewController else { return }

            if let claimRewardsError {
                viewController.showAlert(error: claimRewardsError)
            } else {
                viewController.navigationController?.popToRootViewController(animated: true)
            }
        }
        let title = token.slug == TON_USDE_SLUG ? lang("Confirm Unstaking") : lang("Confirm Rewards Claim")
        do {
            _ = try await AppActions.authorizeProtectedAction(
                on: viewController,
                account: account,
                title: title,
                headerView: headerView,
                passwordAction: { [weak self, stakingState] password in
                    do {
                        return try await Api.submitStakingClaimOrUnlockProtected(
                            accountId: account.id,
                            password: password,
                            state: stakingState.orThrow(),
                            realFee: getFee(.claimJettons).real
                        )
                    } catch {
                        self?.claimRewardsError = error
                        throw error
                    }
                },
                ledgerSignData: { [stakingState] in
                    .submitStakingClaimOrUnlock(
                        accountId: account.id,
                        state: try stakingState.orThrow(),
                        realFee: getFee(.claimJettons).real
                    )
                },
                mfaTitle: title
            )
            onDone()
        } catch is CancellationError {
        } catch {
            self.claimRewardsError = error
            onDone()
        }
    }
}
