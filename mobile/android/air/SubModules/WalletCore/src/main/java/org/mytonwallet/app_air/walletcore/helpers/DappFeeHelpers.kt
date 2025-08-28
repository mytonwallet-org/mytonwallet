package org.mytonwallet.app_air.walletcore.helpers

import org.mytonwallet.app_air.walletcontext.helpers.LocaleController
import org.mytonwallet.app_air.walletcontext.utils.smartDecimalsCount
import org.mytonwallet.app_air.walletcontext.utils.toString
import org.mytonwallet.app_air.walletcore.TONCOIN_SLUG
import org.mytonwallet.app_air.walletcore.models.MFee
import org.mytonwallet.app_air.walletcore.stores.TokenStore
import java.math.BigInteger

class DappFeeHelpers {
    companion object {
        fun calculateDappTransferFee(
            fullFee: BigInteger,
            received: BigInteger,
        ): String {
            val toncoin = TokenStore.getToken(TONCOIN_SLUG) ?: return ""
            if (received == BigInteger.ZERO) {
                return MFee(
                    precision = MFee.FeePrecision.EXACT,
                    terms = MFee.FeeTerms(
                        token = null,
                        native = fullFee,
                        stars = null
                    ),
                    nativeSum = fullFee
                ).toString(toncoin, appendNonNative = true)
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
                ).toString(toncoin, appendNonNative = true)
            }

            val realReceived = received - fullFee
            return LocaleController.getFormattedString(
                "%1$@ will be returned", listOf(
                    realReceived.toString(
                        toncoin.decimals,
                        toncoin.symbol,
                        realReceived.smartDecimalsCount(toncoin.decimals),
                        false
                    )
                )
            )
        }
    }
}
