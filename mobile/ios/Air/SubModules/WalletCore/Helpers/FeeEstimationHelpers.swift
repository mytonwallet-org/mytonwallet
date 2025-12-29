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
        let tokenInChain = ApiChain(rawValue: sellToken.chain)
        let nativeUserTokenIn = sellToken.isOnChain == true ? TokenStore.tokens[tokenInChain?.nativeToken.slug ?? ""] : nil
        let isNativeIn = sellToken.slug == nativeUserTokenIn?.slug
        let chainConfigIn = tokenInChain?.gas
        let fee = {
            var value: BigInt = 0
            if chainConfigIn == nil {
                return value
            }
            
            if (networkFee ?? 0 > 0) {
                value = doubleToBigInt(networkFee!, decimals: nativeUserTokenIn?.decimals ?? 9)
            } else if (swapType == SwapType.onChain) {
                value = chainConfigIn?.maxSwap ?? 0
            } else if (swapType == SwapType.crosschainFromWallet) {
                value = (isNativeIn == true ? chainConfigIn?.maxTransfer : chainConfigIn?.maxTransferToken) ?? 0
            }
            
            return value;
        }()
        return NetworkFeeData(chain: tokenInChain, isNativeIn: isNativeIn, fee: fee)
    }
}
