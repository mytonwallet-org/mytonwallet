
import Foundation
import WalletContext
import GRDB

public struct MStakingData: Equatable, Hashable, Codable, Sendable, FetchableRecord, PersistableRecord {
    public let accountId: String
    public var stateById: [String: ApiStakingState]
    public var totalProfit: BigInt
    public var shouldUseNominators: Bool?
    
    init(accountId: String, stateById: [String: ApiStakingState], totalProfit: BigInt, shouldUseNominators: Bool?) {
        self.accountId = accountId
        self.stateById = stateById
        self.totalProfit = totalProfit
        self.shouldUseNominators = shouldUseNominators
    }
    
    public static let databaseTableName = "account_staking"
}


extension MStakingData {
    public var tonState: ApiStakingState? {
        stateById.values.first { state in
            state.tokenSlug == TONCOIN_SLUG &&
            (shouldUseNominators == true ? state.type == .nominators : state.type == .liquid)
        }
    }
    public var tonLiquid: ApiStakingStateLiquid? {
        for state in stateById.values {
            if case .liquid(let liquid) = state {
                return liquid
            }
        }
        return nil
    }
    public var tonNominators: ApiStakingStateNominators? {
        for state in stateById.values {
            if case .nominators(let nominators) = state {
                return nominators
            }
        }
        return nil
    }
    public var mycoinState: ApiStakingState? {
        stateById.values.first { $0.tokenSlug == MYCOIN_SLUG }
    }
    public var mycoinJetton: ApiStakingStateJetton? {
        for state in stateById.values {
            if case .jetton(let jetton) = state, jetton.tokenSlug == MYCOIN_SLUG {
                return jetton
            }
        }
        return nil
    }
    public var ethenaState: ApiStakingState? {
        stateById["ethena"]
    }
    
    public func bySlug(_ tokenSlug: String) -> ApiStakingState? {
        if tokenSlug == TONCOIN_SLUG {
            return tonState
        } else if tokenSlug == MYCOIN_SLUG {
            return mycoinState
        } else if tokenSlug == TON_USDE_SLUG {
            return ethenaState
        } else {
            return nil
        }
    }

    public func byStakedSlug(_ tokenSlug: String) -> ApiStakingState? {
        if tokenSlug == STAKED_TON_SLUG {
            return tonState
        } else if tokenSlug == STAKED_MYCOIN_SLUG {
            return mycoinState
        } else if tokenSlug == TON_TSUSDE_SLUG {
            return ethenaState
        } else {
            return nil
        }
    }
}

