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
    static let insufficientStakedBalance: WButtonConfig = .init(
        title: lang("Insufficient Balance"),
        isEnabled: false
    )
    static func insufficientFee(minAmount: BigInt) -> WButtonConfig {
        .init(
            title: lang("$insufficient_fee", arg1: "\(minAmount.doubleAbsRepresentation(decimals: 9)) TON"),
            isEnabled: false
        )
    }
    static func `continue`(title: String?, isEnabled: Bool) -> WButtonConfig {
        .init(
            title: title ?? "",
            isEnabled: isEnabled
        )
    }
}
