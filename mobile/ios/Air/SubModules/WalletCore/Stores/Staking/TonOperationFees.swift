//
//  TonOperationFees.swift
//  MyTonWalletAir
//
//  Created by nikstar on 18.07.2025.
//

import Foundation
import WalletContext

public let ONE_TON: BigInt = 1_000_000_000
public let DEFAULT_FEE: BigInt = 15_000_000
public let TOKEN_TRANSFER_AMOUNT: BigInt = 50_000_000 // 0.05 TON

enum JettonStakingGas {
  static let MIN_RESERVE: BigInt = 20_000_000
  static let DEPLOY_POOL: BigInt = 340_000_000
  static let NOTIFICATION: BigInt = 340_000_000
  static let JETTON_TRANSFER: BigInt = 55_000_000
  static let BURN_JETTONS: BigInt = 340_000_000
  static let STAKE_JETTONS: BigInt = 300_000_000 // It was 340000000n
  static let UNSTAKE_JETTONS: BigInt = 340_000_000
  static let CANCEL_UNSTAKE: BigInt = 340_000_000
  static let SEND_COMMISSIONS: BigInt = 340_000_000
  static let SIMPLE_UPDATE_REQUEST: BigInt = 340_000_000
  static let ADD_REWARDS: BigInt = 340_000_000
  static let APPROVE_TRANSFER: BigInt = 340_000_000
  static let SAVE_UPDATED_REWARDS: BigInt = 340_000_000
  static let MIN_EXCESS: BigInt = 10_000_000
  static let SEND_STAKED_JETTONS: BigInt = 630_000_000
}

public struct TonOperationFees {
    public let gas: BigInt?
    public let real: BigInt?
}

private let TON_GAS: [TonOperation: BigInt] = [
    .stakeNominators: ONE_TON,
    .unstakeNominators: ONE_TON,
    .stakeLiquid: ONE_TON,
    .unstakeLiquid: ONE_TON,
    .stakeJettonsForward: JettonStakingGas.STAKE_JETTONS,
    .stakeJettons: JettonStakingGas.STAKE_JETTONS + TOKEN_TRANSFER_AMOUNT,
    .unstakeJettons: JettonStakingGas.UNSTAKE_JETTONS,
    .claimJettons: JettonStakingGas.JETTON_TRANSFER + JettonStakingGas.SIMPLE_UPDATE_REQUEST,
    .changeDns: 15_000_000, // 0.015 TON
    .stakeEthena: TOKEN_TRANSFER_AMOUNT + 100_000_000, // 0.15 TON
    .stakeEthenaForward: 100_000_000, // 0.1 TON
    .unstakeEthena: TOKEN_TRANSFER_AMOUNT + 100_000_000, // 0.15 TON
    .unstakeEthenaForward: 100_000_000, // 0.1 TON
    .unstakeEthenaLocked: 150_000_000, // 0.15 TON
    .unstakeEthenaLockedForward: 70_000_000, // 0.07 TON
]

private let TON_GAS_REAL: [TonOperation: BigInt] = [
    .stakeNominators: 1_000_052_853,
    .unstakeNominators: 148_337_433,
    .stakeLiquid: 20_251_387,
    .unstakeLiquid: 18_625_604,
    .stakeJettons: 74_879_996,
    .unstakeJettons: 59_971_662,
    .claimJettons: 57_053_859,
    .stakeEthena: 116_690_790,
    .unstakeEthena: 113_210_330,
    .unstakeEthenaLocked: 37_612_000,
]

public enum TonOperation {
    case stakeNominators
    case unstakeNominators
    case stakeLiquid
    case unstakeLiquid
    case stakeJettonsForward
    case stakeJettons
    case unstakeJettons
    case claimJettons
    case changeDns
    case stakeEthena
    case stakeEthenaForward
    case unstakeEthena
    case unstakeEthenaForward
    case unstakeEthenaLocked
    case unstakeEthenaLockedForward
}

public func getFee(_ operation: TonOperation) -> TonOperationFees {
    TonOperationFees(
        gas: TON_GAS[operation].flatMap { $0 + DEFAULT_FEE },
        real: TON_GAS_REAL[operation],
    )
}

public enum TonStakeOperation {
    case stake
    case unstake
}

public func getStakeOperationFee(stakingType: ApiStakingType, stakeOperation: TonStakeOperation) -> TonOperationFees {
    let operation: TonOperation? = switch (stakingType, stakeOperation) {
    case (.nominators, .stake):
        .stakeNominators
    case (.nominators, .unstake):
        .unstakeNominators
    case (.liquid, .stake):
        .stakeLiquid
    case (.liquid, .unstake):
        .unstakeLiquid
    case (.jetton, .stake):
        .stakeJettons
    case (.jetton, .unstake):
        .unstakeJettons
    case (.ethena, .stake):
        .stakeEthena
    case (.ethena, .unstake):
        .unstakeEthena
    default:
        nil
    }
    return if let operation {
        getFee(operation)
    } else {
        TonOperationFees(gas: nil, real: nil)
    }
}
