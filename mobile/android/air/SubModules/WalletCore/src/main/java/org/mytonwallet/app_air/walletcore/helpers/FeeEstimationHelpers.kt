package org.mytonwallet.app_air.walletcore.helpers

import org.mytonwallet.app_air.walletcore.models.blockchain.MBlockchain
import org.mytonwallet.app_air.walletcore.models.SwapType
import org.mytonwallet.app_air.walletcore.moshi.IApiToken
import org.mytonwallet.app_air.walletcore.stores.TokenStore
import java.math.BigDecimal

class FeeEstimationHelpers private constructor() {
    data class NetworkFeeData(
        val chain: MBlockchain?,
        val isNativeIn: Boolean,
        val fee: BigDecimal?
    )

    companion object {
        fun networkFeeData(
            sellToken: IApiToken?,
            sellTokenIsOnChain: Boolean,
            swapType: SwapType,
            networkFee: Double?
        ): NetworkFeeData? {
            sellToken ?: return null

            val tokenInChain = sellToken.chain.let { MBlockchain.valueOf(it ?: "") }
            val nativeUserTokenIn = if (sellTokenIsOnChain) {
                TokenStore.getToken(tokenInChain.nativeSlug)
            } else {
                null
            }
            val isNativeIn = sellToken.slug == nativeUserTokenIn?.slug
            val chainConfigIn = tokenInChain.gas

            val fee: BigDecimal? = run {
                var value: BigDecimal? = BigDecimal.ZERO
                when {
                    networkFee != null && networkFee > 0 -> {
                        value = networkFee.toBigDecimal()
                    }

                    swapType == SwapType.ON_CHAIN -> {
                        value = chainConfigIn?.maxSwap ?: BigDecimal.ZERO
                    }

                    swapType == SwapType.CROSS_CHAIN_FROM_WALLET -> {
                        value = if (isNativeIn) {
                            chainConfigIn?.maxTransfer
                        } else {
                            chainConfigIn?.maxTransferToken
                        }
                    }
                }
                value
            }

            return NetworkFeeData(chain = tokenInChain, isNativeIn = isNativeIn, fee = fee)
        }
    }
}
