package org.mytonwallet.app_air.walletcore.moshi.explainedFee

import com.squareup.moshi.JsonClass
import org.mytonwallet.app_air.walletbasecontext.utils.smartDecimalsCount
import org.mytonwallet.app_air.walletbasecontext.utils.toString
import org.mytonwallet.app_air.walletcore.moshi.IApiToken
import java.math.BigInteger

@JsonClass(generateAdapter = true)
class MFee(
    var precision: MFeePrecision,
    val terms: MFeeTerms,
    /** The sum of `terms` measured in the native token */
    val nativeSum: BigInteger?,

    /** SwapOnly! Only the network fee terms (like `terms` but excluding our fee) */
    val networkTerms: MFeeTerms? = null
) {

    val isNativeOnly: Boolean
        get() = (terms.token ?: BigInteger.ZERO) == BigInteger.ZERO
            && (terms.stars ?: BigInteger.ZERO) == BigInteger.ZERO

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
