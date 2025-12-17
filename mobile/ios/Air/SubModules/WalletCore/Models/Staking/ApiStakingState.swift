//
//  ApiStakingState.swift
//  WalletCore
//
//  Created by Sina on 5/13/24.
//

import Foundation
import WalletContext

private let log = Log("ApiStakingState")

// MARK: Staking state

public enum ApiStakingState: Equatable, Hashable, Codable, Sendable {
    case liquid(ApiStakingStateLiquid)
    case nominators(ApiStakingStateNominators)
    case jetton(ApiStakingStateJetton)
    case ethena(ApiEthenaStakingState)
    case unknown(String)
    
    enum CodingKeys: CodingKey {
        case type
    }
    
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "liquid":
            self = try .liquid(ApiStakingStateLiquid(from: decoder))
        case "nominators":
            self = try .nominators(ApiStakingStateNominators(from: decoder))
        case "jetton":
            self = try .jetton(ApiStakingStateJetton(from: decoder))
        case "ethena":
            self = try .ethena(ApiEthenaStakingState(from: decoder))
        default:
            log.error("Unexpected staking type = \(type)")
            self = .unknown(type)
        }
    }
    
    public func encode(to encoder: any Encoder) throws {
        switch self {
        case .liquid(let ApiStakingStateLiquid):
            try ApiStakingStateLiquid.encode(to: encoder)
        case .nominators(let ApiStakingStateNominators):
            try ApiStakingStateNominators.encode(to: encoder)
        case .jetton(let ApiStakingStateJetton):
            try ApiStakingStateJetton.encode(to: encoder)
        case .ethena(let ethena):
            try ethena.encode(to: encoder)
        case .unknown:
            break
        }
    }
}

extension ApiStakingState: MBaseStakingState { // less cringey way to do this?
    public var id: String {
        switch self {
        case .liquid(let v): v.id
        case .nominators(let v): v.id
        case .jetton(let v): v.id
        case .ethena(let v): v.id
        case .unknown(let type): type
        }
    }
    
    public var tokenSlug: String {
        switch self {
        case .liquid(let v): v.tokenSlug
        case .nominators(let v): v.tokenSlug
        case .jetton(let v): v.tokenSlug
        case .ethena(let v): v.tokenSlug
        case .unknown(let type): type
        }
    }
    
    public var annualYield: MDouble {
        switch self {
        case .liquid(let v): v.annualYield
        case .nominators(let v): v.annualYield
        case .jetton(let v): v.annualYield
        case .ethena(let v): v.annualYield
        case .unknown: .zero
        }
    }
    
    public var yieldType: ApiYieldType {
        switch self {
        case .liquid(let v): v.yieldType
        case .nominators(let v): v.yieldType
        case .jetton(let v): v.yieldType
        case .ethena(let v): v.yieldType
        case .unknown: .apy
        }
    }
    
    public var balance: BigIntLib.BigInt {
        switch self {
        case .liquid(let v): v.balance
        case .nominators(let v): v.balance
        case .jetton(let v): v.balance
        case .ethena(let v): v.balance
        case .unknown: .zero
        }
    }
    
    public var pool: String {
        switch self {
        case .liquid(let v): v.pool
        case .nominators(let v): v.pool
        case .jetton(let v): v.pool
        case .ethena(let v): v.pool
        case .unknown(let type): type
        }
    }
    
    public var unstakeRequestAmount: BigInt? {
        switch self {
        case .liquid(let v): v.unstakeRequestAmount
        case .nominators(let v): v.unstakeRequestAmount
        case .jetton(let v): v.unstakeRequestAmount
        case .ethena(let v): v.unstakeRequestAmount
        case .unknown: nil
        }
    }
    
    public var end: Int? {
        switch self {
        case .liquid(let v): return v.end
        case .nominators(let v): return v.end
        case .jetton: return nil
        case .ethena: return nil
        case .unknown: return nil
        }
    }
    
    public var unclaimedRewards: BigInt? {
        if case .jetton(let v) = self {
            return v.unclaimedRewards
        }
        return nil
    }
}

public extension ApiStakingState {
    
    var type: MStakingType {
        switch self {
        case .liquid: .liquid
        case .nominators: .nominators
        case .jetton: .jetton
        case .ethena: .ethena
        case .unknown: .unknown
        }
    }
    
    var apy: Double { self.annualYield.value }
    
    var instantAvailable: BigInt {
        if case .liquid(let ApiStakingStateLiquid) = self {
            return ApiStakingStateLiquid.instantAvailable
        }
        return 0
    }
}

public enum ApiYieldType: String, Equatable, Hashable, Codable, Sendable {
    case apy = "APY"
    case apr = "APR"
}

public protocol MBaseStakingState: Identifiable {
    var id: String { get }
    var tokenSlug: String { get }
    var annualYield: MDouble { get }
    var yieldType: ApiYieldType { get }
    var balance: BigInt { get }
    var pool: String { get }
    var unstakeRequestAmount: BigInt? { get }
}

public enum MStakingType: String, Equatable, Hashable, Codable, Sendable {
    case nominators = "nominators"
    case liquid = "liquid"
    case jetton = "jetton"
    case ethena = "ethena"
    case unknown
}
public typealias ApiStakingType = MStakingType

public enum MLoyaltyType: String, Equatable, Hashable, Codable, Sendable {
    case black = "black"
    case platinum = "platinum"
    case gold = "gold"
    case silver = "silver"
    case standard = "standard"
}

public struct MNominatorsPool: Equatable, Hashable, Codable, Sendable {
    public let address: String
    public let apy: Double
    public let start: Int64?
    public let end: Int64?
    
    public init(dictionary: [String: Any]) {
        self.address = dictionary["address"] as? String ?? ""
        self.apy = dictionary["apy"] as? Double ?? 0
        self.start = dictionary["start"] as? Int64
        self.end = dictionary["end"] as? Int64
    }
}


// MARK: - Common data

public struct MStakingCommonData: Equatable, Hashable, Codable, Sendable {
    public var liquid: MStakingCommonDataLiquid
    public var jettonPools: [MStakingJettonPool]
    public var round: MStakingCommonDataRound
    public var prevRound: MStakingCommonDataRound
}

extension MStakingCommonData {
    public var mycoinPool: MStakingJettonPool? {
        jettonPools.first(where: { $0.token == MYCOIN_SLUG })
    }
}


public struct MStakingCommonDataLiquid: Equatable, Hashable, Codable, Sendable {
    public var currentRate: MDouble
    public var nextRoundRate: MDouble
    public var collection: String?
    public var apy: MDouble
    public var available: BigInt
    public var loyaltyApy: [MLoyaltyType: MDouble]
    
    enum CodingKeys: CodingKey {
        case currentRate
        case nextRoundRate
        case collection
        case apy
        case available
        case loyaltyApy
    }
    
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.currentRate = try container.decode(MDouble.self, forKey: .currentRate)
        self.nextRoundRate = try container.decode(MDouble.self, forKey: .nextRoundRate)
        self.collection = try container.decodeIfPresent(String.self, forKey: .collection)
        self.apy = try container.decode(MDouble.self, forKey: .apy)
        self.available = try container.decode(BigInt.self, forKey: .available)
        
        let dict = try container.decode([String : MDouble].self, forKey: .loyaltyApy)
        let kv: [(MLoyaltyType, MDouble)] = dict.compactMap { k, v in
            if let type = MLoyaltyType(rawValue: k) {
                return (type, v)
            }
            Log.shared.error("Unknown loyalty type: \(k, .public)")
            return nil
        }
        self.loyaltyApy = Dictionary(uniqueKeysWithValues: kv)
    }
    
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(self.currentRate, forKey: .currentRate)
        try container.encode(self.nextRoundRate, forKey: .nextRoundRate)
        try container.encodeIfPresent(self.collection, forKey: .collection)
        try container.encode(self.apy, forKey: .apy)
        try container.encode(self.available, forKey: .available)
        
        let kv = self.loyaltyApy.map { k, v in (k.rawValue, v) }
        let dict = Dictionary(uniqueKeysWithValues: kv)
        try container.encode(dict, forKey: .loyaltyApy)
    }
}

public struct MStakingJettonPool: Equatable, Hashable, Codable, Sendable  {
    public var pool: String
    public var token: String
    public var periods: [MStakingJettonPoolPeriod]
}

public struct MStakingJettonPoolPeriod: Equatable, Hashable, Codable, Sendable  {
    public var period: MDouble
    public var token: String
    public var unstakeCommission: MDouble
}

public struct MStakingCommonDataRound: Equatable, Hashable, Codable, Sendable {
    public var start: Int
    public var end: Int
    public var unlock: Int
}
