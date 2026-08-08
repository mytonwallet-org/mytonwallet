package org.mytonwallet.app_air.uisend.send.helpers

import java.math.BigInteger
import org.mytonwallet.app_air.walletcore.moshi.MDieselStatus
import org.mytonwallet.app_air.walletcore.moshi.MTransferDiesel
import org.mytonwallet.app_air.walletcore.moshi.explainedFee.MExplainedTransferFee
import org.mytonwallet.app_air.walletcore.moshi.explainedFee.MFeeTerms

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

        fun shouldShowFullFee(
            tokenBalance: BigInteger?,
            isNativeToken: Boolean,
            nativeTokenBalance: BigInteger?,
            transferAmount: BigInteger,
            explainedFee: MExplainedTransferFee?,
            diesel: MTransferDiesel?
        ): Boolean {
            if (tokenBalance == null || transferAmount > tokenBalance) return false

            val fullFee = explainedFee?.fullFee ?: return false
            val maximumAmount = if (explainedFee.canTransferFullBalance) {
                tokenBalance
            } else {
                val fee = getFullTransferFee(fullFee.terms, isNativeToken) ?: return false
                maxOf(tokenBalance - fee, BigInteger.ZERO)
            }
            if (transferAmount > maximumAmount) return true

            nativeTokenBalance ?: return false
            val fullNativeFee = fullFee.nativeSum
            val isSufficient = if (
                isNativeToken &&
                explainedFee.canTransferFullBalance &&
                transferAmount == tokenBalance &&
                fullNativeFee != null
            ) {
                fullNativeFee < nativeTokenBalance
            } else {
                val isFullTokenTransfer =
                    transferAmount == tokenBalance && explainedFee.canTransferFullBalance
                val tokenRequiredAmount =
                    (fullFee.terms.token ?: BigInteger.ZERO) +
                        (if (isFullTokenTransfer) BigInteger.ZERO else transferAmount)
                val nativeRequiredAmount = fullFee.terms.native ?: BigInteger.ZERO
                val isFullFeeCovered =
                    tokenRequiredAmount <= tokenBalance &&
                        nativeRequiredAmount <= nativeTokenBalance
                val dieselAmount = diesel?.amount

                if (explainedFee.isGasless &&
                    diesel?.status != MDieselStatus.STARS_FEE &&
                    dieselAmount != null
                ) {
                    isFullFeeCovered && transferAmount + dieselAmount <= tokenBalance
                } else {
                    isFullFeeCovered
                }
            }
            return !isSufficient
        }

        fun hasInsufficientFeeError(
            tokenBalance: BigInteger,
            nativeTokenBalance: BigInteger,
            transferAmount: BigInteger,
            fullFee: MFeeTerms?,
            canTransferFullBalance: Boolean,
            dieselStatus: MDieselStatus?
        ): Boolean {
            val isFullTokenTransfer =
                transferAmount == tokenBalance && canTransferFullBalance
            val tokenRequiredAmount =
                (fullFee?.token ?: BigInteger.ZERO) +
                    (if (isFullTokenTransfer) BigInteger.ZERO else transferAmount)
            val nativeRequiredAmount = fullFee?.native ?: BigInteger.ZERO
            val isEnoughBalance =
                tokenRequiredAmount <= tokenBalance &&
                    nativeRequiredAmount <= nativeTokenBalance
            val isAmountGreaterThanBalance = transferAmount > tokenBalance

            return !isEnoughBalance &&
                !isAmountGreaterThanBalance &&
                dieselStatus != MDieselStatus.NOT_AUTHORIZED &&
                dieselStatus != MDieselStatus.PENDING_PREVIOUS
        }
    }
}
