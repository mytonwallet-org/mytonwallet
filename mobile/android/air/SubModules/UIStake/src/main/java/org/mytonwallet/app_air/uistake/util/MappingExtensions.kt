package org.mytonwallet.app_air.uistake.util

import org.mytonwallet.app_air.uistake.earn.models.EarnItem
import org.mytonwallet.app_air.walletcontext.utils.CoinUtils
import org.mytonwallet.app_air.walletbasecontext.utils.smartDecimalsCount
import org.mytonwallet.app_air.walletbasecontext.utils.toString
import org.mytonwallet.app_air.walletcore.STAKED_USDE_SLUG
import org.mytonwallet.app_air.walletcore.USDE_SLUG
import org.mytonwallet.app_air.walletcore.moshi.ApiTransactionType
import org.mytonwallet.app_air.walletcore.moshi.MApiTransaction
import org.mytonwallet.app_air.walletcore.moshi.MStakeHistoryItem
import java.math.BigInteger


fun MStakeHistoryItem.toViewItem(): EarnItem = let {
    val amount = CoinUtils.fromDecimal(profit, 9) ?: BigInteger.ZERO
    EarnItem.Profit(
        id = "$timestamp|$profit",
        timestamp = timestamp,
        amount = CoinUtils.fromDecimal(profit, 9) ?: BigInteger.ZERO,
        formattedAmount = amount.toString(
            9,
            "",
            amount.smartDecimalsCount(9),
            false,
            true
        ),
        profit = profit,
    )
}

private fun tokenDecimals(tokenSlug: String): Int {
    return when (tokenSlug) {
        USDE_SLUG, STAKED_USDE_SLUG -> 6
        else -> 9
    }
}

fun MApiTransaction.toViewItem(tokenSlug: String, stakedTokenSlug: String): EarnItem = let {
    if (this !is MApiTransaction.Transaction) {
        throw Exception()
    }
    val amountAbs = amount.abs()
    val decimals = tokenDecimals(tokenSlug)
    val formattedAmount = amountAbs.toString(
        decimals,
        "",
        amountAbs.smartDecimalsCount(decimals),
        showPositiveSign = false,
        forceCurrencyToRight = true
    )
    when {
        slug == tokenSlug && type == ApiTransactionType.UNSTAKE -> EarnItem.Unstaked(
            id,
            timestamp,
            amountAbs,
            formattedAmount
        )

        slug == stakedTokenSlug && isIncoming && type != ApiTransactionType.MINT -> EarnItem.Staked(
            id,
            timestamp,
            amountAbs,
            formattedAmount
        )

        (slug == tokenSlug || slug == stakedTokenSlug) && type == ApiTransactionType.STAKE -> EarnItem.Staked(
            id,
            timestamp,
            amountAbs,
            formattedAmount
        )

        slug == tokenSlug && type == ApiTransactionType.UNSTAKE_REQUEST -> EarnItem.UnstakeRequest(
            id,
            timestamp,
            amountAbs,
            formattedAmount
        )

        else -> EarnItem.None(id, timestamp, amountAbs, formattedAmount)
    }
}
