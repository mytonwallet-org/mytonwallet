package org.mytonwallet.app_air.walletcore.models

import org.mytonwallet.app_air.walletcore.TON_CHAIN
import org.mytonwallet.app_air.walletcore.moshi.IApiToken

enum class SwapType {
    ON_CHAIN,
    CROSS_CHAIN_FROM_WALLET,
    CROSS_CHAIN_TO_WALLET;

    companion object {
        fun from(
            tokenToSend: IApiToken,
            tokenToReceive: IApiToken,
            walletAddressByChain: Map<String, String>
        ): SwapType {
            if (tokenToSend.chain == TON_CHAIN && tokenToReceive.chain == TON_CHAIN) {
                return ON_CHAIN
            }

            if (walletAddressByChain.contains(tokenToSend.chain)) {
                return CROSS_CHAIN_FROM_WALLET
            }

            return CROSS_CHAIN_TO_WALLET
        }
    }
}
