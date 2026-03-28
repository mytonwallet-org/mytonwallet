package org.mytonwallet.app_air.uisend.send.helpers

import org.mytonwallet.app_air.walletcore.moshi.explainedFee.MFeeTerms
import java.math.BigInteger

class TransferHelpers private constructor() {

    companion object {
        fun getFullTransferFee(terms: MFeeTerms?, isNativeToken: Boolean): BigInteger? {
            terms ?: return null
            val tokenPart = terms.token ?: BigInteger.ZERO
            val nativePart = if (isNativeToken) terms.native ?: BigInteger.ZERO else BigInteger.ZERO
            return tokenPart + nativePart
        }

        fun getMaxTransferAmount(
            tokenBalance: BigInteger?,
            isNativeToken: Boolean,
            fullFee: MFeeTerms?,
            canTransferFullBalance: Boolean
        ): BigInteger? {
            if (tokenBalance == null || tokenBalance <= BigInteger.ZERO) {
                return null
            }

            if (canTransferFullBalance || fullFee == null) {
                return null
            }

            val fee = getFullTransferFee(fullFee, isNativeToken) ?: return null
            return maxOf(tokenBalance - fee, BigInteger.ZERO)
        }
    }
}
