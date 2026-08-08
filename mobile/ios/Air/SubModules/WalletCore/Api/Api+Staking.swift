//
//  Api+Stake.swift
//  WalletCore
//
//  Created by Sina on 5/13/24.
//

import Foundation
import WalletContext

extension Api {
    
    public static func checkStakeDraft(accountId: String, amount: BigInt, state: ApiStakingState) async throws -> ApiCheckTransactionDraftResult {
        try await bridge.callApi("checkStakeDraft", accountId, amount, state, decoding: ApiCheckTransactionDraftResult.self)
    }
    
    public static func checkUnstakeDraft(accountId: String, amount: BigInt, state: ApiStakingState) async throws -> ApiCheckTransactionDraftResult {
        try await bridge.callApi("checkUnstakeDraft", accountId, amount, state, decoding: ApiCheckTransactionDraftResult.self)
    }

    public static func submitStake(accountId: String, enclaveToken: EnclaveToken?, amount: BigInt, state: ApiStakingState, realFee: BigInt?) async throws -> String {
        try await submitStakeProtected(accountId: accountId, enclaveToken: enclaveToken, amount: amount, state: state, realFee: realFee).activityId.orThrow()
    }

    public static func submitStakeProtected(accountId: String, enclaveToken: EnclaveToken?, amount: BigInt, state: ApiStakingState, realFee: BigInt?) async throws -> ApiMfaProtectedResult {
        try await bridge.callApi("submitStake", accountId, enclaveToken, amount, state, realFee, decoding: ApiMfaProtectedResult.self)
    }
    
    public static func submitUnstake(accountId: String, enclaveToken: EnclaveToken?, amount: BigInt, state: ApiStakingState, realFee: BigInt?) async throws -> String {
        try await submitUnstakeProtected(accountId: accountId, enclaveToken: enclaveToken, amount: amount, state: state, realFee: realFee).activityId.orThrow()
    }

    public static func submitUnstakeProtected(accountId: String, enclaveToken: EnclaveToken?, amount: BigInt, state: ApiStakingState, realFee: BigInt?) async throws -> ApiMfaProtectedResult {
        try await bridge.callApi("submitUnstake", accountId, enclaveToken, amount, state, realFee, decoding: ApiMfaProtectedResult.self)
    }

    public static func getStakingHistory(accountId: String) async throws -> [ApiStakingHistory] {
        return try await bridge.callApi("getStakingHistory", accountId, decoding: [ApiStakingHistory].self)
    }
    
    public static func submitStakingClaimOrUnlock(accountId: String, enclaveToken: EnclaveToken?, state: ApiStakingState, realFee: BigInt?) async throws -> String {
        try await submitStakingClaimOrUnlockProtected(accountId: accountId, enclaveToken: enclaveToken, state: state, realFee: realFee).activityId.orThrow()
    }

    public static func submitStakingClaimOrUnlockProtected(accountId: String, enclaveToken: EnclaveToken?, state: ApiStakingState, realFee: BigInt?) async throws -> ApiMfaProtectedResult {
        try await bridge.callApi("submitStakingClaimOrUnlock", accountId, enclaveToken, state, realFee, decoding: ApiMfaProtectedResult.self)
    }
}
