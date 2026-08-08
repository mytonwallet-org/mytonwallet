import ProtectedAction
import WalletContext
import WalletCore

extension ProtectedAction where HeaderView == StakingConfirmHeaderView, Result == ApiMfaProtectedResult {
    static func stake(model: AddStakeModel, account: MAccount) throws -> Self {
        let amount = try model.amount.orThrow("invalid stake amount")
        let stakingState = model.stakingState
        let realFee = getStakeOperationFee(stakingType: stakingState.type, stakeOperation: .stake).real
        return Self(
            account: account,
            software: .single { enclaveToken in
                try await Api.submitStakeProtected(
                    accountId: account.id,
                    enclaveToken: enclaveToken,
                    amount: amount,
                    state: stakingState,
                    realFee: realFee
                )
            },
            hardware: .single {
                let activityId = try await Api.submitStake(
                    accountId: account.id,
                    enclaveToken: nil,
                    amount: amount,
                    state: stakingState,
                    realFee: realFee
                )
                return ActionSubmissionReceipt(activityIds: [activityId])
            },
            confirmation: .init(
                title: lang("Confirm Staking"),
                header: StakingConfirmHeaderView(
                    mode: .stake,
                    tokenAmount: TokenAmount(amount, model.baseToken)
                )
            ),
            completion: stakingActivityCompletion(context: .stakeConfirmation)
        )
    }

    static func unstake(model: UnstakeModel, account: MAccount) throws -> Self {
        let stakingState = model.stakingState
        let displayedAmount = model.amount ?? 0
        let submitAmount: BigInt = switch stakingState.type {
        case .nominators:
            stakingState.balance
        default:
            try (model.draft?.tokenAmount).orThrow()
        }
        let realFee = getStakeOperationFee(stakingType: stakingState.type, stakeOperation: .unstake).real
        return Self(
            account: account,
            software: .single { enclaveToken in
                try await Api.submitUnstakeProtected(
                    accountId: account.id,
                    enclaveToken: enclaveToken,
                    amount: submitAmount,
                    state: stakingState,
                    realFee: realFee
                )
            },
            hardware: .single {
                let activityId = try await Api.submitUnstake(
                    accountId: account.id,
                    enclaveToken: nil,
                    amount: submitAmount,
                    state: stakingState,
                    realFee: realFee
                )
                return ActionSubmissionReceipt(activityIds: [activityId])
            },
            confirmation: .init(
                title: lang("Confirm Unstaking"),
                header: StakingConfirmHeaderView(
                    mode: .unstake,
                    tokenAmount: TokenAmount(displayedAmount, model.baseToken)
                )
            ),
            completion: stakingActivityCompletion(context: .unstakeRequestConfirmation)
        )
    }

    static func claimRewards(
        account: MAccount,
        stakingState: ApiStakingState,
        amount: TokenAmount,
        onCommitted: @escaping @MainActor () -> Void
    ) -> Self {
        let isUnlock = amount.token.slug == TON_USDE_SLUG
        let title = isUnlock ? lang("Confirm Unstaking") : lang("Confirm Rewards Claim")
        let realFee = getFee(.claimJettons).real
        return Self(
            account: account,
            software: .single { enclaveToken in
                try await Api.submitStakingClaimOrUnlockProtected(
                    accountId: account.id,
                    enclaveToken: enclaveToken,
                    state: stakingState,
                    realFee: realFee
                )
            },
            hardware: .single {
                let activityId = try await Api.submitStakingClaimOrUnlock(
                    accountId: account.id,
                    enclaveToken: nil,
                    state: stakingState,
                    realFee: realFee
                )
                return ActionSubmissionReceipt(activityIds: [activityId])
            },
            confirmation: .init(
                title: title,
                header: StakingConfirmHeaderView(mode: isUnlock ? .unstake : .claim, tokenAmount: amount)
            ),
            completion: .finish { _ in
                onCommitted()
            }
        )
    }

    private static func stakingActivityCompletion(
        context: ActivityDetailsContext
    ) -> Completion<ApiMfaProtectedResult> {
        .activity(
            ActivityCompletion(
                sources: [.local, .pendingOrConfirmed],
                context: context,
                matches: { activity, receipt in
                    receipt.correlates(with: activity)
                }
            )
        )
    }

}
