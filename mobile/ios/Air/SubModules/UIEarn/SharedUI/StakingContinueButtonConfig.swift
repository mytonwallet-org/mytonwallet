//
//  StakingContinueButtonConfig.swift
//  UIEarn
//
//  Created by nikstar on 28.07.2025.
//

import UIKit
import UIComponents
import WalletContext

extension WButtonConfig {
    static let insufficientStakedBalance: WButtonConfig = .init(title: "Insufficient Staked Balance", isEnabled: false)
    static func insufficientFee(minAmount: BigInt) -> WButtonConfig { .init(title: WStrings.Staking_InsufficientFeeAmount_Text(amount: minAmount.doubleAbsRepresentation(decimals: 9)), isEnabled: false) }
    static func `continue`(title: String?, isEnabled: Bool) -> WButtonConfig { .init(title: title ?? "", isEnabled: isEnabled) }
}
