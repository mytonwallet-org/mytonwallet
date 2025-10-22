package org.mytonwallet.app_air.uistake.earn.models

import androidx.annotation.DrawableRes
import org.mytonwallet.app_air.uicomponents.R
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletcontext.utils.WEquatable
import org.mytonwallet.app_air.walletcore.moshi.MApiTransaction
import java.math.BigInteger

sealed class EarnItem(
    open val id: String,
    open val timestamp: Long,
    open val amount: BigInteger, // amount without decimal
    open val formattedAmount: String, // amount with decimal
) : WEquatable<MApiTransaction> {
    open var amountInBaseCurrency: String = ""

    abstract fun getTitle(): String?

    @DrawableRes
    abstract fun getIcon(): Int?

    abstract fun getGradientColors(): Pair<String, String>?

    override fun isSame(comparing: WEquatable<*>): Boolean {
        return if (comparing is EarnItem && comparing::class == this::class) {
            comparing.timestamp == timestamp && comparing.amount == amount
        } else false
    }

    override fun isChanged(comparing: WEquatable<*>): Boolean {
        return if (comparing is EarnItem && comparing::class == this::class) {
            comparing.formattedAmount != formattedAmount ||
                comparing.amountInBaseCurrency != amountInBaseCurrency
        } else false
    }

    data class Profit(
        override val id: String,
        override val timestamp: Long,
        override val amount: BigInteger,
        override val formattedAmount: String,
        override var amountInBaseCurrency: String = "",
        val profit: String,
    ) : EarnItem(id, timestamp, amount, formattedAmount) {
        override fun getTitle() =
            LocaleController.getString("Earned")

        @DrawableRes
        override fun getIcon() = R.drawable.ic_earned

        override fun getGradientColors() = ("#A0DE7E" to "#54CB68")
    }

    data class ProfitGroup(
        override val id: String,
        override val timestamp: Long,
        override val amount: BigInteger,
        override val formattedAmount: String,
        override var amountInBaseCurrency: String = "",
        val profit: String,
        val profitItems: MutableList<Profit>,
        val itemTitle: String
    ) : EarnItem(id, timestamp, amount, formattedAmount) {
        override fun getTitle() = itemTitle

        @DrawableRes
        override fun getIcon() = R.drawable.ic_earned

        override fun getGradientColors() = ("#A0DE7E" to "#54CB68")
    }

    data class Staked(
        override val id: String,
        override val timestamp: Long,
        override val amount: BigInteger,
        override val formattedAmount: String,
    ) : EarnItem(id, timestamp, amount, formattedAmount) {
        override fun getTitle() =
            LocaleController.getString("Staked")

        @DrawableRes
        override fun getIcon() = R.drawable.ic_staked

        override fun getGradientColors() = ("#72D5FD" to "#2A9EF1")
    }

    data class Unstaked(
        override val id: String,
        override val timestamp: Long,
        override val amount: BigInteger,
        override val formattedAmount: String,
    ) : EarnItem(id, timestamp, amount, formattedAmount) {
        override fun getTitle() =
            LocaleController.getString("Unstaked")

        @DrawableRes
        override fun getIcon() = R.drawable.ic_unstaked

        override fun getGradientColors() = ("#72D5FD" to "#2A9EF1")
    }

    data class UnstakeRequest(
        override val id: String,
        override val timestamp: Long,
        override val amount: BigInteger,
        override val formattedAmount: String,
    ) : EarnItem(id, timestamp, amount, formattedAmount) {
        override fun getTitle() =
            LocaleController.getString("Unstake Request")

        @DrawableRes
        override fun getIcon() = R.drawable.ic_unstaked

        override fun getGradientColors() = ("#72D5FD" to "#2A9EF1")
    }

    data class None(
        override val id: String,
        override val timestamp: Long,
        override val amount: BigInteger,
        override val formattedAmount: String,
    ) : EarnItem(id, timestamp, amount, formattedAmount) {
        override fun getTitle() = null
        override fun getIcon() = null
        override fun getGradientColors() = null
    }

}
