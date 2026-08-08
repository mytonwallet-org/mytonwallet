package org.mytonwallet.app_air.walletcore.stores

import org.mytonwallet.app_air.walletbasecontext.models.MBaseCurrency
import org.mytonwallet.app_air.walletcontext.WalletContextManager
import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.WalletEvent

object ConfigStore : IStore {
    enum class SeasonalTheme(val value: String) {
        NEW_YEAR("newYear"),
        VALENTINE("valentine");

        companion object {
            fun fromString(value: String?): SeasonalTheme? =
                entries.firstOrNull { it.value == value }
        }
    }

    var isCopyStorageEnabled: Boolean? = null
        private set
    var supportAccountsCount: Double? = null
        private set
    var isLimited: Boolean? = null
        private set
    var countryCode: String? = null
        private set
    var isAppUpdateRequired: Boolean? = null
        private set
    var swapVersion: Int? = null
        private set
    var seasonalTheme: SeasonalTheme? = null
        private set
    var allowedOnOffRampCurrencies: List<MBaseCurrency>? = null
        private set

    @Volatile
    var seasonalThemeOverride: SeasonalTheme? = null

    fun getEffectiveSeasonalTheme(): SeasonalTheme? = seasonalThemeOverride ?: seasonalTheme

    fun init(configMap: Map<String, Any>?) {
        if (configMap == null) return
        isCopyStorageEnabled = configMap["isCopyStorageEnabled"] as? Boolean
        supportAccountsCount = configMap["supportAccountsCount"] as? Double
        isLimited = configMap["isLimited"] as? Boolean
        countryCode = configMap["countryCode"] as? String
        isAppUpdateRequired = configMap["isAppUpdateRequired"] as? Boolean
        swapVersion = (configMap["swapVersion"] as? Number)?.toInt()
        // Resolved to currencies at ingest rather than kept as strings, so no later comparison can
        // disagree on case or spelling. Shape is validated at runtime: a non-list reads as an absent
        // field, and anything that is not a known currency code drops out
        allowedOnOffRampCurrencies =
            (configMap["allowedOnOffRampCurrencies"] as? List<*>)
                ?.filterIsInstance<String>()
                ?.mapNotNull { code ->
                    val currencyCode = code.uppercase()
                    MBaseCurrency.entries.firstOrNull { it.currencyCode == currencyCode }
                }
                ?.distinct()

        // Seasonal Theme
        val oldEffectiveSeasonalTheme = getEffectiveSeasonalTheme()
        seasonalTheme = SeasonalTheme.fromString(configMap["seasonalTheme"] as? String)
        if (getEffectiveSeasonalTheme() != oldEffectiveSeasonalTheme) {
            WalletCore.notifyEvent(WalletEvent.SeasonalThemeChanged)
        }
    }

    override fun wipeData() {
    }

    override fun clearCache() {
    }
}
