import WalletContext
import WalletCore

struct AddStakeDraftRequest: Equatable, Sendable {
    let accountId: String
    let amount: BigInt
    let stakingState: ApiStakingState
}

struct UnstakeDraftRequest: Equatable, Sendable {
    let accountId: String
    let amount: BigInt
    let stakingState: ApiStakingState
}

struct StakingDraftClient: Sendable {
    let checkStake: @Sendable (
        AddStakeDraftRequest
    ) async throws -> ApiCheckTransactionDraftResult
    let checkUnstake: @Sendable (
        UnstakeDraftRequest
    ) async throws -> ApiCheckTransactionDraftResult
}

extension StakingDraftClient {
    static let live = StakingDraftClient(
        checkStake: { request in
            let draft = try await Api.checkStakeDraft(
                accountId: request.accountId,
                amount: request.amount,
                state: request.stakingState
            )
            try handleDraftError(draft)
            return draft
        },
        checkUnstake: { request in
            let draft = try await Api.checkUnstakeDraft(
                accountId: request.accountId,
                amount: request.amount,
                state: request.stakingState
            )
            try handleDraftError(draft)
            return draft
        }
    )
}
