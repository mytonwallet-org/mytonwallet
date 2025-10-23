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

    public static func submitStake(accountId: String, password: String?, amount: BigInt, state: ApiStakingState, realFee: BigInt?) async throws -> String {
        try await bridge.callApi("submitStake", accountId, password, amount, state, realFee, decoding: ActivityIdResult.self).activityId
    }
    
    public static func submitUnstake(accountId: String, password: String?, amount: BigInt, state: ApiStakingState, realFee: BigInt?) async throws -> String {
        try await bridge.callApi("submitUnstake", accountId, password, amount, state, realFee, decoding: ActivityIdResult.self).activityId
    }

    public static func getStakingHistory(accountId: String) async throws -> [ApiStakingHistory] {
        return try await bridge.callApi("getStakingHistory", accountId, decoding: [ApiStakingHistory].self)
    }
    
    public static func submitStakingClaimOrUnlock(accountId: String, password: String?, state: ApiStakingState, realFee: BigInt?) async throws -> String {
        try await bridge.callApi("submitStakingClaimOrUnlock", accountId, password, state, realFee, decoding: ActivityIdResult.self).activityId
    }
}


// MARK: - Types

fileprivate struct ActivityIdResult: Decodable {
    let activityId: String
}

