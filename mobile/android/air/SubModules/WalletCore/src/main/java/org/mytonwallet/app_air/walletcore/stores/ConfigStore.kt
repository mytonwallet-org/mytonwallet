package org.mytonwallet.app_air.walletcore.stores

import org.mytonwallet.app_air.walletbasecontext.models.MBaseCurrency
import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.WalletEvent
import org.mytonwallet.app_air.walletcore.moshi.api.ApiUpdate

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

    fun init(config: ApiUpdate.ApiUpdateConfig) {
        isCopyStorageEnabled = config.isCopyStorageEnabled
        supportAccountsCount = config.supportAccountsCount
        isLimited = config.isLimited
        countryCode = config.countryCode
        isAppUpdateRequired = config.isAppUpdateRequired
        swapVersion = config.swapVersion
        // Resolved to currencies at ingest rather than kept as strings, so no later comparison can
        // disagree on case or spelling. Anything that is not a known currency code drops out
        allowedOnOffRampCurrencies =
            config.allowedOnOffRampCurrencies
                ?.mapNotNull { code ->
                    val currencyCode = code.uppercase()
                    MBaseCurrency.entries.firstOrNull { it.currencyCode == currencyCode }
                }
                ?.distinct()

        // Seasonal Theme
        val oldEffectiveSeasonalTheme = getEffectiveSeasonalTheme()
        seasonalTheme = SeasonalTheme.fromString(config.seasonalTheme)
        if (getEffectiveSeasonalTheme() != oldEffectiveSeasonalTheme) {
            WalletCore.notifyEvent(WalletEvent.SeasonalThemeChanged)
        }
    }

    override fun wipeData() {
    }

    override fun clearCache() {
    }
}
