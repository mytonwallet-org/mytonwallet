//
//  StakingConfig.swift
//  MyTonWalletAir
//
//  Created by nikstar on 18.07.2025.
//

import Foundation
import WalletCore
import WalletContext


public struct StakingConfig: Identifiable, Equatable, Hashable {
    public let id: String
    let _baseToken: ApiToken
    let _stakedToken: ApiToken
    public let displayTitle: String
    public let explainTitle: String
    public let explainContent: [String]
    
    init(id: String, baseToken: ApiToken, stakedToken: ApiToken, displayTitle: String, explainTitle: String, explainContent: [String]) {
        self.id = id
        self._baseToken = baseToken
        self._stakedToken = stakedToken
        self.displayTitle = displayTitle
        self.explainTitle = explainTitle
        self.explainContent = explainContent
    }
}

public extension StakingConfig {
    
    static let tonLiquid = StakingConfig(
        id: "liquid",
        baseToken: .TONCOIN,
        stakedToken: .STAKED_TON,
        displayTitle: "TON",
        explainTitle: lang("Why is staking safe?"),
        explainContent: [
            lang("$safe_staking_description1"),
            lang("$safe_staking_description2"),
            lang("$safe_staking_description3"),
        ],
    )
    
    static let tonNominators = StakingConfig(
        id: "nominators",
        baseToken: .TONCOIN,
        stakedToken: .STAKED_TON,
        displayTitle: "TON",
        explainTitle: lang("Why is staking safe?"),
        explainContent: [
            lang("$safe_staking_description1"),
            lang("$safe_staking_description2"),
            lang("$safe_staking_description3"),
        ],
    )
    
    static var ton: StakingConfig {
        StakingStore.currentAccount?.shouldUseNominators == true ? tonNominators : tonLiquid
    }

    static let mycoin = StakingConfig(
        id: MYCOIN_STAKING_POOL,
        baseToken: .MYCOIN,
        stakedToken: .STAKED_MYCOIN,
        displayTitle: "MY",
        explainTitle: lang("Why is staking safe?"),
        explainContent: [
            lang("$safe_staking_description_jetton1", arg1: "[JVault](\(JVAULT_URL))"),
            lang("$safe_staking_description_jetton2")
        ],
    )

    static let ethena = StakingConfig(
        id: "ethena",
        baseToken: .TON_USDE,
        stakedToken: .TON_TSUSDE,
        displayTitle: "USDe",
        explainTitle: lang("How does it work?"),
        explainContent: [
            lang("$safe_staking_ethena_description1"),
            lang("$safe_staking_ethena_description2"),
            lang("$safe_staking_ethena_description3"),
        ],
    )
}

public extension StakingConfig {
    var baseTokenSlug: String { _baseToken.slug }
    var stakedTokenSlug: String { _stakedToken.slug }
    var nativeTokenSlug: String { TONCOIN_SLUG }
    
    var baseToken: ApiToken { TokenStore.tokens[baseTokenSlug] ?? _baseToken }
    var stakedToken: ApiToken { TokenStore.tokens[stakedTokenSlug] ?? _stakedToken }
    var nativeToken: ApiToken { TokenStore.tokens[nativeTokenSlug] ?? .TONCOIN }
    
    var stakingState: ApiStakingState? { StakingStore.currentAccount?.stateById[id] }

    var fullStakingBalance: BigInt? {
        stakingState.flatMap(getFullStakingBalance(state:))
    }
    var unstakeTime: Date? {
        stakingState.flatMap(getUnstakeTime(state:))
    }
}
