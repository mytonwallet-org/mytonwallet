package org.mytonwallet.app_air.walletcore.helpers

import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.utils.smartDecimalsCount
import org.mytonwallet.app_air.walletbasecontext.utils.toString
import org.mytonwallet.app_air.walletcore.models.MFee
import org.mytonwallet.app_air.walletcore.models.blockchain.MBlockchain
import org.mytonwallet.app_air.walletcore.stores.TokenStore
import java.math.BigInteger

class DappFeeHelpers {
    companion object {
        fun calculateDappTransferFee(
            operationChain: String,
            fullFee: BigInteger,
            received: BigInteger,
        ): String {
            val nativeToken = TokenStore.getToken(MBlockchain.valueOf(operationChain).nativeSlug) ?: return ""
            if (received == BigInteger.ZERO) {
                return MFee(
                    precision = MFee.FeePrecision.EXACT,
                    terms = MFee.FeeTerms(
                        token = null,
                        native = fullFee,
                        stars = null
                    ),
                    nativeSum = fullFee
                ).toString(nativeToken, appendNonNative = true)
            }

            if (fullFee >= received) {
                val realFee = fullFee - received
                return MFee(
                    precision = MFee.FeePrecision.APPROXIMATE,
                    terms = MFee.FeeTerms(
                        native = realFee,
                        token = null,
                        stars = null
                    ),
                    nativeSum = realFee
                ).toString(nativeToken, appendNonNative = true)
            }

            val realReceived = received - fullFee
            return LocaleController.getFormattedString(
                "%1$@ will be returned", listOf(
                    realReceived.toString(
                        nativeToken.decimals,
                        nativeToken.symbol,
                        realReceived.smartDecimalsCount(nativeToken.decimals),
                        false
                    )
                )
            )
        }
    }
}
