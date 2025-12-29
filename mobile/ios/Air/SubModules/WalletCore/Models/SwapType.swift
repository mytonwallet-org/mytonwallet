//
//  MSwapType.swift
//  WalletCore
//
//  Created by Sina on 5/11/24.
//

import Foundation

public enum SwapType {
    case onChain
    /** The swap is crosschain (Changelly CEX) and happens within a single account */
    case crosschainInsideWallet
    /** The swap is crosschain (Changelly CEX), the "in" token is sent from the app, and the "out" token is sent outside */
    case crosschainFromWallet
    /**
     * The swap is crosschain (Changelly CEX), the "in" token is sent manually by the user from another source, and the
     * "out" token is sent to the user account.
     */
    case crosschainToWallet
}
