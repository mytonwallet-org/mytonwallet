//
//  FeeEstimationHelpers.swift
//  WalletCore
//
//  Created by Sina on 10/23/24.
//

import WalletContext

public class FeeEstimationHelpers {
    private init() {}
    
    public static func networkFeeBigInt(sellToken: ApiToken?, swapType: SwapType, networkFee: Double?) -> NetworkFeeData? {
        guard let sellToken else {
            return nil
        }
        let tokenInChain = sellToken.chain
        let nativeUserTokenIn = sellToken.isOnChain == true && tokenInChain.isSupported ? TokenStore.tokens[tokenInChain.nativeToken.slug] : nil
        let isNativeIn = sellToken.slug == nativeUserTokenIn?.slug
        let chainConfigIn = tokenInChain.isSupported ? tokenInChain.gas : nil
        let fee = {
            var value: BigInt = 0
            if chainConfigIn == nil {
                return value
            }
            
            if let networkFee, networkFee > 0, let decimals = nativeUserTokenIn?.decimals {
                value = doubleToBigInt(networkFee, decimals: decimals)
            } else if (swapType == SwapType.onChain) {
                value = chainConfigIn?.maxSwap ?? 0
            } else if (swapType == SwapType.crosschainFromWallet || swapType == SwapType.crosschainInsideWallet) {
                value = (isNativeIn == true ? chainConfigIn?.maxTransfer : chainConfigIn?.maxTransferToken) ?? 0
            }
            
            return value;
        }()
        return NetworkFeeData(chain: tokenInChain.isSupported ? tokenInChain : nil, isNativeIn: isNativeIn, fee: fee)
    }
}
