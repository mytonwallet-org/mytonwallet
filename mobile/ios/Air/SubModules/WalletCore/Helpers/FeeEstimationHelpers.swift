//
//  FeeEstimationHelpers.swift
//  WalletCore
//
//  Created by Sina on 10/23/24.
//

import WalletContext
import WalletCoreTypes

public class FeeEstimationHelpers {
    private init() {}
    
    public static func networkFeeBigInt(sellToken: ApiToken?, swapType: SwapType, networkFee: Double?) -> NetworkFeeData? {
        guard let sellToken else {
            return nil
        }
        let tokenInChain = sellToken.chain
        let nativeTokenIn = tokenInChain.isSupported ? tokenInChain.nativeToken : nil
        let isNativeIn = sellToken.slug == nativeTokenIn?.slug
        let chainConfigIn = tokenInChain.isSupported ? tokenInChain.gas : nil
        let fee = {
            var value: BigInt = 0
            if chainConfigIn == nil {
                return value
            }
            
            if let networkFee, networkFee > 0, let decimals = nativeTokenIn?.decimals {
                value = doubleToBigInt(networkFee, decimals: decimals)
            } else if swapType.route == .dex {
                value = chainConfigIn?.maxSwap ?? 0
            } else if swapType.cexTopology != .toWallet {
                value = (isNativeIn == true ? chainConfigIn?.maxTransfer : chainConfigIn?.maxTransferToken) ?? 0
            }
            
            return value;
        }()
        return NetworkFeeData(chain: tokenInChain.isSupported ? tokenInChain : nil, isNativeIn: isNativeIn, fee: fee)
    }
}
