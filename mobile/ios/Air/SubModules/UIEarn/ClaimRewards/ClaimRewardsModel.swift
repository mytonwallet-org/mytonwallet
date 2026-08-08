//
//  ClaimRewardsModel.swift
//  UIEarn
//
//  Created by nikstar on 21.07.2025.
//

import SwiftUI
import ProtectedAction
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
        let protectedAction = try ProtectedAction.claimRewards(
            account: account,
            stakingState: stakingState.orThrow(),
            amount: amount,
            onCommitted: { [weak viewController] in
                viewController?.navigationController?.popToRootViewController(animated: true)
            }
        )
        _ = await ProtectedActionExecutor.execute(protectedAction, on: viewController)
    }
}
