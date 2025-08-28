//
//  Helpers.swift
//  MyTonWalletAir
//
//  Created by nikstar on 15.07.2025.
//

import Foundation
import WalletContext

public let NOMINATORS_STAKING_MIN_AMOUNT: BigInt = 10_000 * ONE_TON
public let ETHENA_STAKING_MIN_AMOUNT: BigInt = 1_000_000 // 1 eUSD
public let STAKING_MIN_AMOUNT: BigInt = ONE_TON
public let MIN_ACTIVE_STAKING_REWARDS: BigInt = 100_000_000 // 0.1 MY

public func getStakingMinAmount(type: ApiStakingType?) -> BigInt {
    switch type {
    case .nominators:
        return NOMINATORS_STAKING_MIN_AMOUNT
    case .ethena:
        return ETHENA_STAKING_MIN_AMOUNT
    default:
        return STAKING_MIN_AMOUNT
    }
}

public func getUnstakeTime(state: ApiStakingState?) -> Date? {
    switch state {
    case .nominators(let v):
        return Date(unixMs: v.end)
    case .liquid(let v):
        return Date(unixMs: v.end)
    case .ethena(let v):
        return v.unlockTime.flatMap(Date.init(unixMs:))
    default:
        return nil
    }
}

public enum StakingStateStatus: String {
    case inactive
    case active
    case unstakeRequested
    case readyToClaim
}

public func getStakingStateStatus(state: ApiStakingState) -> StakingStateStatus {
    if let unstakeRequestAmount = state.unstakeRequestAmount, unstakeRequestAmount > 0 {
        if case .ethena = state, let unlockTime = getUnstakeTime(state: state), unlockTime <= .now {
            return .readyToClaim
        }
        return .unstakeRequested
    }
    if getIsActiveStakingState(state: state) {
        return .active
    }
    return .inactive
}

public func getIsActiveStakingState(state: ApiStakingState) -> Bool {
    return state.balance > 0
        || (state.unstakeRequestAmount ?? 0) > 0
        || (state.unclaimedRewards != nil && state.unclaimedRewards! > MIN_ACTIVE_STAKING_REWARDS)
}

public func getIsLongUnstake(state: ApiStakingState, amount: BigInt?) -> Bool? {
    switch state.type {
    case .nominators:
        return true
    case .liquid:
        if let amount = amount {
            return amount > state.instantAvailable
        } else {
            return false
        }
    case .jetton:
        return false
    case .ethena:
        return true
    default:
        return nil
    }
}

public func getFullStakingBalance(state: ApiStakingState) -> BigInt {
    switch state.type {
    case .jetton:
        return state.balance + (state.unclaimedRewards ?? 0)
    case .ethena:
        return state.balance + (state.unstakeRequestAmount ?? 0)
    default:
        return state.balance
    }
}
