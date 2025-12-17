//
//  MStakingHistoryItem.swift
//  WalletCore
//
//  Created by Sina on 5/13/24.
//

import UIKit
import WalletContext

public struct MStakingHistoryItem: Equatable, Hashable, Encodable, Identifiable {

    public enum ItemType: Hashable, Encodable {
        case staked
        case unstaked
        case profit
        case unstakeRequest
        
        public var localized: String {
            switch self {
            case .profit:
                return lang("Earned")
            case .staked:
                return lang("Staked")
            case .unstaked:
                return lang("Unstaked")
            case .unstakeRequest:
                return lang("Requested Unstake")
            }
        }
        
        private var inProgressLocalized: String {
            switch self {
            case .staked:
                return lang("Staking")
            default:
                return localized
            }
        }
        
        public var image: UIImage? {
            switch self {
            case .profit:
                return UIImage(named: "EarnedIcon", in: AirBundle, compatibleWith: nil)
            case .staked:
                return UIImage(named: "StakedIcon", in: AirBundle, compatibleWith: nil)
            case .unstaked:
                return UIImage(named: "UnstakedIcon", in: AirBundle, compatibleWith: nil)
            case .unstakeRequest:
                return UIImage(named: "UnstakedIcon", in: AirBundle, compatibleWith: nil)
            }
        }
    }
    
    public var id: MStakingHistoryItem { self }
    
    public var type: ItemType
    public var timestamp: Int64
    public var amount: BigInt
    public var isLocal: Bool
    
    public init(stakingHistory: ApiStakingHistory) {
        self.timestamp = stakingHistory.timestamp
        self.amount = doubleToBigInt(stakingHistory.profit.value, decimals: 9)
        self.type = .profit
        self.isLocal = false
    }
    
    public init?(tokenSlug: String, stakedTokenSlug: String, transaction: ApiActivity) {
        guard transaction.slug == tokenSlug || transaction.slug == stakedTokenSlug else { return nil }
        if transaction.type == .stake  {
            self.type = .staked
        } else if transaction.type == .unstake {
            self.type = .unstaked
        } else if transaction.type == .unstakeRequest {
            self.type = .unstakeRequest
        } else {
            return nil
        }
        self.timestamp = transaction.timestamp
        self.amount = transaction.transaction?.amount ?? 0
        self.isLocal = transaction.isLocal
    }
}
