package org.mytonwallet.app_air.walletcore.moshi

import com.squareup.moshi.JsonClass
import org.mytonwallet.app_air.walletbasecontext.models.MBaseCurrency

@JsonClass(generateAdapter = true)
data class WcPayMerchant(
    val name: String,
    val iconUrl: String? = null
)

@JsonClass(generateAdapter = true)
data class WcPayAmountDisplay(
    val assetSymbol: String,
    val assetName: String,
    val decimals: Int,
    val iconUrl: String? = null,
    val networkName: String? = null
)

@JsonClass(generateAdapter = true)
data class WcPayAmount(
    val value: String,
    val display: WcPayAmountDisplay,
    val unit: String? = null
) {
    val fiatCurrency: MBaseCurrency?
        get() = resolveFiatFromUnit(unit) ?: resolveFiatFromDisplay(display)

    companion object {
        private const val ISO4217_UNIT_PREFIX = "iso4217/"
        private val FIAT_CURRENCIES = listOf(MBaseCurrency.USD, MBaseCurrency.EUR)

        private fun normalizeFiatCode(value: String): MBaseCurrency? {
            val normalized = value.trim().uppercase()
            return FIAT_CURRENCIES.firstOrNull { it.currencyCode == normalized }
        }

        private fun resolveFiatFromUnit(unit: String?): MBaseCurrency? {
            if (unit == null) return null
            val prefixIndex = unit.lowercase().indexOf(ISO4217_UNIT_PREFIX)
            if (prefixIndex == -1) return null
            return normalizeFiatCode(unit.substring(prefixIndex + ISO4217_UNIT_PREFIX.length))
        }

        private fun resolveFiatFromDisplay(display: WcPayAmountDisplay): MBaseCurrency? {
            normalizeFiatCode(display.assetSymbol)?.let { return it }
            val assetName = display.assetName.trim().lowercase()
            return FIAT_CURRENCIES.firstOrNull {
                it.currencyName.trim().lowercase() == assetName
            }
        }
    }
}

@JsonClass(generateAdapter = true)
data class WcPayPaymentInfo(
    val expiresAt: Long,
    val amount: WcPayAmount? = null
)

@JsonClass(generateAdapter = true)
data class WcPayPaymentOption(
    val id: String,
    val account: String,
    val amountValue: String,
    val slug: String? = null,
    val display: WcPayAmountDisplay,
    val etaS: Long? = null,
    val expiresAt: Long? = null
)
