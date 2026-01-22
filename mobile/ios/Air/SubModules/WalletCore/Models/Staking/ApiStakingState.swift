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
    
    public var balance: BigInt {
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
    
    var type: ApiStakingType {
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

public enum ApiStakingType: String, Equatable, Hashable, Codable, Sendable {
    case nominators = "nominators"
    case liquid = "liquid"
    case jetton = "jetton"
    case ethena = "ethena"
    case unknown
}
