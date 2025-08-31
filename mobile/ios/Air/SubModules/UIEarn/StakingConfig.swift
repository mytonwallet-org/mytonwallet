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
    public let explainContent: String
    
    init(id: String, baseToken: ApiToken, stakedToken: ApiToken, displayTitle: String, explainTitle: String, explainContent: String) {
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
        explainTitle: lang("Why Staking is Safe"),
        explainContent: lang("Staking is **fully decentralized** and operated by the **official TON Liquid Staking** smart contracts.|The deposited stake will be used for the TON network validation as part of its **proof-of-stake** essence.|You can withdraw your stake at **any time** and it will be deposited back to your account within **two days**."),
    )
    
    static let tonNominators = StakingConfig(
        id: "nominators",
        baseToken: .TONCOIN,
        stakedToken: .STAKED_TON,
        displayTitle: "TON",
        explainTitle: lang("Why Staking is Safe"),
        explainContent: lang("Staking is **fully decentralized** and operated by the **official TON Liquid Staking** smart contracts.|The deposited stake will be used for the TON network validation as part of its **proof-of-stake** essence.|You can withdraw your stake at **any time** and it will be deposited back to your account within **two days**."),
    )
    
    static var ton: StakingConfig {
        StakingStore.currentAccount?.shouldUseNominators == true ? tonNominators : tonLiquid
    }

    static let mycoin = StakingConfig(
        id: MYCOIN_STAKING_POOL,
        baseToken: .MYCOIN,
        stakedToken: .STAKED_MYCOIN,
        displayTitle: "MY",
        explainTitle: lang("Why Staking is Safe"),
        explainContent: "Token staking is **fully decentralized** and operated by the **open-source** smart contracts developed by [**JVault**](https://jvault.xyz) and passed **security audits**.|You can withdraw your stake at **any time** and it will be deposited back to your account **instantly**.",

    )

    static let ethena = StakingConfig(
        id: "ethena",
        baseToken: .TON_USDE,
        stakedToken: .TON_TSUSDE,
        displayTitle: "USDe",
        explainTitle: "How does it work?",
        explainContent: "Staking is fully decentralized and operated by **Ethena’s official** audited liquid staking **smart contracts**.|The deposited USDe stake is used in Ethena’s **trading and investment strategies** to yield rewards automatically and transparently.|You can **withdraw** your stake with rewards at any time, and it will be returned to your account **in 7 days**, according to Ethena’s standard withdrawal period.",
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
