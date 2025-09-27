package org.mytonwallet.app_air.walletcore.models

import org.mytonwallet.app_air.walletbasecontext.utils.smartDecimalsCount
import org.mytonwallet.app_air.walletbasecontext.utils.toString
import org.mytonwallet.app_air.walletcore.moshi.IApiToken
import java.math.BigInteger

class MFee(
    var precision: FeePrecision,
    val terms: FeeTerms,
    /** The sum of `terms` measured in the native token */
    val nativeSum: BigInteger?,

    /** SwapOnly! Only the network fee terms (like `terms` but excluding our fee) */
    val networkTerms: FeeTerms? = null
) {

    class FeeTerms(
        /** The fee part paid in the transferred token */
        val token: BigInteger?,

        /** The fee part paid in the chain's native token */
        val native: BigInteger?,

        /**
         * The fee part paid in stars.
         * The BigInteger assumes the same number of decimal places as the transferred token.
         */
        val stars: BigInteger?
    )

    enum class FeePrecision(val prefix: String) {
        EXACT(""),
        APPROXIMATE("~"),
        LESS_THAN("<");
    }

    fun toString(token: IApiToken, appendNonNative: Boolean): String {
        var result = ""

        networkTerms?.native?.takeIf { it > BigInteger.ZERO }?.let { native ->
            result += native.toString(
                token.nativeToken!!.decimals,
                token.nativeToken!!.symbol,
                native.smartDecimalsCount(token.nativeToken!!.decimals),
                false
            )
        } ?: terms.native?.takeIf { it > BigInteger.ZERO }?.let { native ->
            result += native.toString(
                token.nativeToken!!.decimals,
                token.nativeToken!!.symbol,
                native.smartDecimalsCount(token.nativeToken!!.decimals),
                false
            )
        }

        if (appendNonNative) {
            terms.token?.takeIf { it > BigInteger.ZERO }?.let { tokenAmount ->
                if (result.isNotEmpty()) {
                    result = " + $result"
                }
                result = tokenAmount.toString(
                    token.decimals,
                    token.symbol ?: "",
                    tokenAmount.smartDecimalsCount(token.decimals),
                    false
                ) + result
            }

            terms.stars?.takeIf { it > BigInteger.ZERO }?.let { stars ->
                if (result.isNotEmpty()) {
                    result = " + $result"
                }
                result = stars.toString(
                    1,
                    "⭐️",
                    stars.smartDecimalsCount(1),
                    false
                ) + result
            }
        }

        if (result.isEmpty()) {
            result += BigInteger.ZERO.toString(
                0,
                token.nativeToken!!.symbol,
                0,
                false
            )
        }

        return precision.prefix + result
    }
}
