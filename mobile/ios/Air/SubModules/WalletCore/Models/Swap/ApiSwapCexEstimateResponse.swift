//
//  MSwapEstimate.swift
//  WalletCore
//
//  Created by Sina on 5/10/24.
//

import Foundation
import WalletContext

let DEFAULT_OUR_SWAP_FEE = 0.875

public struct NetworkFeeData {
    public let chain: ApiChain?
    public let isNativeIn: Bool
    public let fee: BigInt
}

public struct ApiSwapCexEstimateResponse: Equatable, Hashable, Codable, Sendable {
    public var from: String
    public var fromAmount: MDouble
    public var to: String
    public var toAmount: MDouble
    public let swapFee: MDouble
    public var networkFee: MDouble? = nil
    public var realNetworkFee: MDouble? = nil
    // additional
    public var fromMin: MDouble?
    public var fromMax: MDouble?
    public var toMin: MDouble?
    public var toMax: MDouble?
    public var dieselStatus: DieselStatus?

    // Late-init properties
    public var isEnoughNative: Bool? = nil
    
    mutating public func reverse() {
        (from, to) = (to, from)
        (fromAmount, toAmount) = (toAmount, fromAmount)
        (toMin, toMax) = (fromMin, fromMax)
    }
}
