package org.mytonwallet.app_air.walletcontext.globalStorage

import org.json.JSONArray
import org.json.JSONException
import org.json.JSONObject
import org.mytonwallet.app_air.walletbasecontext.R as BaseR
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.localization.WLanguage
import org.mytonwallet.app_air.walletbasecontext.logger.Logger
import org.mytonwallet.app_air.walletbasecontext.theme.ThemeManager
import org.mytonwallet.app_air.walletbasecontext.utils.ApplicationContextHolder
import org.mytonwallet.app_air.walletcontext.WalletContextManager
import org.mytonwallet.app_air.walletcontext.cacheStorage.WCacheStorage
import org.mytonwallet.app_air.walletcontext.helpers.DevicePerformanceClassifier
import org.mytonwallet.app_air.walletcontext.models.MAutoLockOption
import org.mytonwallet.app_air.walletcontext.models.MBlockchainNetwork
import org.mytonwallet.app_air.walletcontext.models.MCollectionTab
import org.mytonwallet.app_air.walletcontext.models.MWalletSettingsViewMode
import org.mytonwallet.app_air.walletcontext.secureStorage.WSecureStorage

object WGlobalStorage {
    val isInitialized: Boolean
        get() {
            return ::globalStorageProvider.isInitialized
        }

    private lateinit var globalStorageProvider: IGlobalStorageProvider

    private val cachedAccountNames = mutableMapOf<String, String>()
    private val cachedAccountTonAddresses = mutableMapOf<String, String>()

    @Volatile
    private var cachedAccountIds: Array<String>? = null

    @Volatile
    private var cachedLangCode: String? = null
    private var _isSensitiveDataProtectionOn: Boolean = false

    @Volatile
    private var _useLocalizedTokenNames: Boolean = true

    fun init(globalStorageProvider: IGlobalStorageProvider) {
        WGlobalStorage.globalStorageProvider = globalStorageProvider
        _isSensitiveDataProtectionOn =
            WGlobalStorage.globalStorageProvider.getBool(IS_SENSITIVE_DATA_HIDDEN) == true
        _useLocalizedTokenNames =
            WGlobalStorage.globalStorageProvider.getBool(USE_LOCALIZED_TOKEN_NAMES) != false
        migrate()
        removeTemporaryAccounts()
    }

    @Volatile
    var temporaryAddedAccountIds: MutableList<String> = mutableListOf()
        private set

    private fun removeTemporaryAccounts() {
        temporaryAddedAccountIds =
            accountIds().filter {
                globalStorageProvider.getBool("accounts.byId.$it.isTemporary") ==
                    true
            }
                .toMutableList()
        temporaryAddedAccountIds.toList().forEach {
            removeAccount(it)
        }
        setTemporaryAccountId(null, true)
    }

    fun clearCachedData() {
        cachedAccountNames.clear()
        cachedAccountTonAddresses.clear()
        cachedAccountIds = null
        _isSensitiveDataProtectionOn =
            globalStorageProvider.getBool(IS_SENSITIVE_DATA_HIDDEN) == true
        _useLocalizedTokenNames =
            globalStorageProvider.getBool(USE_LOCALIZED_TOKEN_NAMES) != false
        clearUiCacheData()
    }

    fun clearUiCacheData() {
        cachedLangCode = null
    }

    fun incDoNotSynchronize() {
        globalStorageProvider.incrementDoNotSynchronize()
        // Logger.d("---", "doNotSynchronize: ${globalStorageProvider.doNotSynchronize}")
    }

    fun decDoNotSynchronize() {
        globalStorageProvider.decrementDoNotSynchronize()
        // Logger.d("---", "doNotSynchronize: ${globalStorageProvider.doNotSynchronize}")
    }

    private const val AUTH_TYPES = "authTypes"
    private const val CURRENT_ACCOUNT_ID = "currentAccountId"
    private const val CURRENT_TEMPORARY_VIEW_ACCOUNT_ID = "currentTemporaryViewAccountId"
    private const val ACTIVE_THEME = "settings.theme"
    private const val ACTIVE_FONT = "settings.font"
    private const val IS_ROUNDED_BALANCE_FONT_ACTIVE = "settings.roundedBalanceFont"
    private const val ARE_ROUNDED_TOOLBARS_ACTIVE = "settings.roundedToolbars"
    private const val IS_TESTNET = "settings.isTestnet"
    private const val ARE_ANIMATIONS_ACTIVE = "settings.animationLevel"
    private const val ARE_SIDE_GUTTERS_ACTIVE = "settings.sideGutters"
    private const val ARE_ROUNDED_CORNERS_ACTIVE = "settings.roundedCorners"
    private const val IS_GRADIENT_NAVIGATION_BAR_ACTIVE = "settings.gradientNavigationBar"
    private const val IS_BLUR_ENABLED = "settings.blurEnabled"
    private const val ARE_SOUNDS_ACTIVE = "settings.canPlaySounds"
    private const val HIDE_TINY_TRANSFERS = "settings.areTinyTransfersHidden"
    private const val HIDE_UNVERIFIED_NFTS = "settings.areUnverifiedNftsHidden"
    private const val HIDE_NO_COST_TOKENS = "settings.areTokensWithNoCostHidden"
    private const val USE_LOCALIZED_TOKEN_NAMES = "settings.useLocalizedTokenNames"
    private const val BASE_CURRENCY = "settings.baseCurrency"
    private const val ASSETS_AND_ACTIVITY = "settings.byAccountId"
    private const val LANG_CODE = "settings.langCode"
    private const val LANG_SOURCE = "settings.langSource"
    const val LANG_SOURCE_USER = "user"
    private const val PRICE_HISTORY = "tokenPriceHistory.bySlug"
    private const val AUTO_LOCK_VALUE = "settings.autolockValue"
    private const val IS_APP_LOCK_ENABLED = "settings.isAppLockEnabled"
    private const val IS_SENSITIVE_DATA_HIDDEN = "settings.isSensitiveDataHidden"
    private const val STATE_VERSION = "stateVersion"
    private const val PUSH_NOTIFICATIONS_TOKEN = "pushNotifications.userToken"
    private const val PUSH_NOTIFICATIONS_ENABLED_ACCOUNTS = "pushNotifications.enabledAccounts"
    private const val ORDERED_ACCOUNT_IDS = "settings.orderedAccountIds"
    private const val IS_SEASONAL_THEMING_DISABLED = "settings.isSeasonalThemingDisabled"
    private const val EXPLORER = "settings.selectedExplorerIds"
    private const val IS_SCREEN_RECORD_WARNING_DISABLED = "settings.isScreenRecordWarningDisabled"
    private const val LEGACY_BIOMETRIC_KIND = "settings.authConfig.kind"
    private const val IS_SHAKE_TO_DEBUG_ENABLED = "settings.isShakeToDebugEnabled"
    private const val ARE_EXPERIMENTAL_FEATURES_ENABLED = "settings.areExperimentalFeaturesEnabled"
    private const val IS_TOKEN_CHART_EXPANDED = "settings.isTokenChartExpanded"
    private const val IS_TOKEN_INFO_EXPANDED = "settings.isTokenInfoExpanded"
    private const val TOKEN_INFO_DEBUG_SOURCE = "debug.tokenInfoSource"
    private const val TABLET_PANEL_WIDTH = "settings.tabletPanelWidth"
    private const val APP_TAB_ORDER = "settings.appTabOrder"

    private const val LEGACY_MAIN_ACCOUNT_ID = "0"
    private const val MAIN_ACCOUNT_ID = "0-ton-mainnet"

    fun save(accountId: String, accountName: String?, persist: Boolean = true) {
        // Save null names as empty string in the cache to return it without accessing storage
        cachedAccountNames[accountId] = accountName ?: ""
        globalStorageProvider.set(
            "accounts.byId.$accountId.title",
            accountName,
            if (persist) {
                IGlobalStorageProvider.PERSIST_INSTANT
            } else {
                IGlobalStorageProvider.PERSIST_NO
            }
        )
    }

    fun getAccountName(accountId: String): String? {
        if (cachedAccountNames[accountId] == null) {
            globalStorageProvider.getString("accounts.byId.$accountId.title")?.let {
                cachedAccountNames[accountId] = it
            }
        }
        return cachedAccountNames[accountId]
    }

    fun accountExists(accountId: String): Boolean =
        globalStorageProvider.getDict("accounts.byId.$accountId") != null

    fun getAccountTonAddress(accountId: String): String? {
        globalStorageProvider.getDict("accounts.byId.$accountId.byChain.ton")
            ?.optString("address")?.let {
                if (it.isNotEmpty()) {
                    cachedAccountTonAddresses[accountId] = it
                    return it
                }
            }
        return cachedAccountTonAddresses[accountId]
    }

    fun getAccount(accountId: String): JSONObject? =
        globalStorageProvider.getDict("accounts.byId.$accountId")

    fun saveAccount(accountId: String, jsonObject: JSONObject?) = globalStorageProvider.set(
        "accounts.byId.$accountId",
        jsonObject,
        IGlobalStorageProvider.PERSIST_INSTANT
    )

    fun accountIds(network: MBlockchainNetwork? = null): Array<String> {
        cachedAccountIds?.let {
            return it
        }
        val allIds = globalStorageProvider.keysIn("accounts.byId").filter {
            !temporaryAddedAccountIds.contains(it) &&
                (network == null || MBlockchainNetwork.ofAccountId(it) == network)
        }.toTypedArray()
        val orderedIds = globalStorageProvider.getArray(ORDERED_ACCOUNT_IDS)
            ?.let { array ->
                (0 until array.length())
                    .mapNotNull { array.getString(it) }
            }
            ?.filter { it in allIds }
            ?.takeIf { it.isNotEmpty() }
            ?: return allIds
        val missing = allIds.filterNot { it in orderedIds }
        val arr = (orderedIds + missing).toTypedArray()
        cachedAccountIds = arr
        return arr
    }

    fun addAccount(
        accountId: String,
        accountType: String,
        byChain: JSONObject,
        name: String? = null,
        importedAt: Long?,
        isTemporary: Boolean = false
    ) {
        val suggestedName = name ?: when {
            isTemporary -> LocaleController.getString("Wallet")
            else -> getSuggestedName(MBlockchainNetwork.ofAccountId(accountId), accountType)
        }
        save(accountId = accountId, accountName = suggestedName, persist = false)

        if (byChain.length() > 0) {
            globalStorageProvider.set(
                "accounts.byId.$accountId.byChain",
                byChain,
                IGlobalStorageProvider.PERSIST_NO
            )
        }

        globalStorageProvider.set(
            "accounts.byId.$accountId.type",
            accountType,
            IGlobalStorageProvider.PERSIST_NO
        )
        if (importedAt != null) {
            globalStorageProvider.set(
                "accounts.byId.$accountId.importedAt",
                value = importedAt,
                persistInstantly = IGlobalStorageProvider.PERSIST_NO
            )
        }
        if (isTemporary) {
            globalStorageProvider.set(
                "accounts.byId.$accountId.isTemporary",
                value = true,
                persistInstantly = IGlobalStorageProvider.PERSIST_NO
            )
            temporaryAddedAccountIds.add(accountId)
        }
        globalStorageProvider.set(
            "byAccountId.$accountId.isBackupRequired",
            value = false,
            persistInstantly = IGlobalStorageProvider.PERSIST_INSTANT
        )
        cachedAccountIds = null
    }

    fun saveAccountByChain(accountId: String, byChain: JSONObject) {
        if (byChain.length() > 0) {
            globalStorageProvider.set(
                "accounts.byId.$accountId.byChain",
                byChain,
                IGlobalStorageProvider.PERSIST_NORMAL
            )
        }
    }

    fun saveTemporaryAccount(accountId: String) {
        temporaryAddedAccountIds.remove(accountId)
        setActiveAccountId(accountId, false)
        setTemporaryAccountId(null, false)
        globalStorageProvider.remove(
            "accounts.byId.$accountId.isTemporary",
            persistInstantly = IGlobalStorageProvider.PERSIST_INSTANT
        )
        cachedAccountIds = null
    }

    fun setOrderedAccountIds(accountIds: JSONArray) {
        globalStorageProvider.set(
            ORDERED_ACCOUNT_IDS,
            accountIds,
            IGlobalStorageProvider.PERSIST_INSTANT
        )
        cachedAccountIds = null
    }

    fun isPasscodeSet(): Boolean {
        for (accountId in accountIds()) {
            if (globalStorageProvider.getString("accounts.byId.$accountId.type") == "mnemonic") {
                return true
            }
        }
        return false
    }

    fun removeAccount(accountId: String) {
        cachedAccountNames.remove(accountId)
        cachedAccountTonAddresses.remove(accountId)
        globalStorageProvider.remove(
            keys = arrayOf(
                "accounts.byId.$accountId",
                "byAccountId.$accountId",
                "settings.byAccountId.$accountId"
            ),
            persistInstantly = IGlobalStorageProvider.PERSIST_INSTANT
        )
        cachedAccountIds = null
        if (!isPasscodeSet()) {
            removeLegacyAuthData()
        }
    }

    fun deleteAllWallets() {
        setTemporaryAccountId(null, false)
        setActiveAccountId(null, false)
        cachedAccountIds = null
        globalStorageProvider.remove(
            keys = arrayOf(
                "accounts.byId",
                "byAccountId",
                "settings.byAccountId"
            ),
            persistInstantly = IGlobalStorageProvider.PERSIST_INSTANT
        )
    }

    // Active account id is the permanent default account id (not pushed temporary screens)
    fun getActiveAccountId(): String? = globalStorageProvider.getString(CURRENT_ACCOUNT_ID)

    fun setActiveAccountId(id: String?, persistInstantly: Boolean) {
        setIsTestnet(
            id?.let { MBlockchainNetwork.ofAccountId(id).isTestnet } ?: false
        )
        globalStorageProvider.set(
            CURRENT_ACCOUNT_ID,
            id,
            if (persistInstantly) {
                IGlobalStorageProvider.PERSIST_INSTANT
            } else {
                IGlobalStorageProvider.PERSIST_NORMAL
            }
        )
    }

    fun setTemporaryAccountId(id: String?, persistInstantly: Boolean) {
        globalStorageProvider.set(
            CURRENT_TEMPORARY_VIEW_ACCOUNT_ID,
            id,
            if (persistInstantly) {
                IGlobalStorageProvider.PERSIST_INSTANT
            } else {
                IGlobalStorageProvider.PERSIST_NORMAL
            }
        )
    }

    fun getAssetsAndActivityData(accountId: String): JSONObject? =
        globalStorageProvider.getDict("$ASSETS_AND_ACTIVITY.$accountId")

    fun setAssetsAndActivityData(accountId: String, value: JSONObject) {
        for (key in arrayOf(
            "alwaysHiddenSlugs",
            "alwaysShownSlugs",
            "deletedSlugs",
            "importedSlugs",
            "pinnedSlugs"
        )) {
            val array = value.optJSONArray(key) ?: JSONArray()
            globalStorageProvider.set(
                "$ASSETS_AND_ACTIVITY.$accountId.$key",
                array,
                IGlobalStorageProvider.PERSIST_INSTANT
            )
        }
        val chainDisplayConfigurationKey =
            "$ASSETS_AND_ACTIVITY.$accountId.chainDisplayConfiguration"
        value.optJSONObject("chainDisplayConfiguration")?.let { chainDisplayConfiguration ->
            globalStorageProvider.set(
                chainDisplayConfigurationKey,
                chainDisplayConfiguration,
                IGlobalStorageProvider.PERSIST_INSTANT
            )
        } ?: run {
            globalStorageProvider.remove(
                chainDisplayConfigurationKey,
                IGlobalStorageProvider.PERSIST_INSTANT
            )
        }
    }

    // `LEGACY_BIOMETRIC_KIND` is no longer used in the new Enclave auth system.
    fun removeIsLegacyBiometricActivated() {
        globalStorageProvider.remove(
            LEGACY_BIOMETRIC_KIND,
            IGlobalStorageProvider.PERSIST_INSTANT
        )
    }

    fun isLegacyBiometricActivated(): Boolean =
        globalStorageProvider.getString(LEGACY_BIOMETRIC_KIND) == "native-biometrics"

    fun getAuthTypes(): Array<String>? {
        val jsonArray = globalStorageProvider.getArray(
            AUTH_TYPES
        ) ?: return null
        return Array(jsonArray.length()) { i ->
            jsonArray.getString(i)
        }
    }

    fun setAuthTypes(authTypes: List<String>?) {
        globalStorageProvider.set(
            AUTH_TYPES,
            JSONArray(authTypes),
            IGlobalStorageProvider.PERSIST_INSTANT
        )
    }

    fun getIsEnclaveBiometricActivated(): Boolean = getAuthTypes()?.contains("biometric") == true

    fun isAnyBiometricActivated(): Boolean =
        getIsEnclaveBiometricActivated() || isLegacyBiometricActivated()

    fun getActiveTheme(): String =
        globalStorageProvider.getString(ACTIVE_THEME) ?: ThemeManager.THEME_SYSTEM

    fun setActiveTheme(theme: String) {
        globalStorageProvider.set(ACTIVE_THEME, theme, IGlobalStorageProvider.PERSIST_INSTANT)
    }

    fun getActiveFont(): String? = globalStorageProvider.getString(ACTIVE_FONT)

    fun setActiveFont(font: String) {
        globalStorageProvider.set(ACTIVE_FONT, font, IGlobalStorageProvider.PERSIST_INSTANT)
    }

    fun isRoundedBalanceFontActive(): Boolean =
        globalStorageProvider.getBool(IS_ROUNDED_BALANCE_FONT_ACTIVE) ?: true

    fun setIsRoundedBalanceFontActive(active: Boolean) {
        globalStorageProvider.set(
            IS_ROUNDED_BALANCE_FONT_ACTIVE,
            active,
            IGlobalStorageProvider.PERSIST_INSTANT
        )
    }

    fun setAreRoundedToolbarsActive(active: Boolean) {
        globalStorageProvider.set(
            ARE_ROUNDED_TOOLBARS_ACTIVE,
            active,
            IGlobalStorageProvider.PERSIST_INSTANT
        )
    }

    fun getAreRoundedToolbarsActive(): Boolean =
        globalStorageProvider.getBool(ARE_ROUNDED_TOOLBARS_ACTIVE) ?: true

    private fun setIsTestnet(isTestnet: Boolean) {
        globalStorageProvider.set(
            IS_TESTNET,
            isTestnet,
            IGlobalStorageProvider.PERSIST_NO
        )
    }

    fun getAreAnimationsActive(): Boolean =
        (globalStorageProvider.getInt(ARE_ANIMATIONS_ACTIVE) ?: 2) > 0

    fun setAreAnimationsActive(active: Boolean) {
        globalStorageProvider.set(
            ARE_ANIMATIONS_ACTIVE,
            if (active) 2 else 0,
            IGlobalStorageProvider.PERSIST_INSTANT
        )
    }

    fun getAreSideGuttersActive(): Boolean = globalStorageProvider.getBool(ARE_SIDE_GUTTERS_ACTIVE)
        ?: !ApplicationContextHolder.isSmallScreen

    fun setAreSideGuttersActive(active: Boolean) {
        globalStorageProvider.set(
            ARE_SIDE_GUTTERS_ACTIVE,
            active,
            IGlobalStorageProvider.PERSIST_INSTANT
        )
    }

    fun isGradientNavigationBarActive(): Boolean =
        globalStorageProvider.getBool(IS_GRADIENT_NAVIGATION_BAR_ACTIVE) ?: true

    fun setIsGradientNavigationBarActive(active: Boolean) {
        globalStorageProvider.set(
            IS_GRADIENT_NAVIGATION_BAR_ACTIVE,
            active,
            IGlobalStorageProvider.PERSIST_INSTANT
        )
    }

    fun getAreRoundedCornersActive(): Boolean =
        globalStorageProvider.getBool(ARE_ROUNDED_CORNERS_ACTIVE) ?: true

    fun setAreRoundedCornersActive(active: Boolean) {
        globalStorageProvider.set(
            ARE_ROUNDED_CORNERS_ACTIVE,
            active,
            IGlobalStorageProvider.PERSIST_INSTANT
        )
    }

    fun isBlurEnabled(): Boolean = globalStorageProvider.getBool(IS_BLUR_ENABLED)
        ?: DevicePerformanceClassifier.isHighClass

    fun setBlurEnabled(enabled: Boolean) {
        globalStorageProvider.set(
            IS_BLUR_ENABLED,
            enabled,
            IGlobalStorageProvider.PERSIST_INSTANT
        )
    }

    fun getAreSoundsActive(): Boolean = globalStorageProvider.getBool(ARE_SOUNDS_ACTIVE) ?: true

    fun setAreSoundsActive(active: Boolean) {
        globalStorageProvider.set(ARE_SOUNDS_ACTIVE, active, IGlobalStorageProvider.PERSIST_INSTANT)
    }

    fun getAreTinyTransfersHidden(): Boolean =
        globalStorageProvider.getBool(HIDE_TINY_TRANSFERS) != false

    fun setAreTinyTransfersHidden(hidden: Boolean) {
        globalStorageProvider.set(
            HIDE_TINY_TRANSFERS,
            hidden,
            IGlobalStorageProvider.PERSIST_INSTANT
        )
    }

    fun getAreUnverifiedNftsHidden(): Boolean =
        globalStorageProvider.getBool(HIDE_UNVERIFIED_NFTS) != false

    fun setAreUnverifiedNftsHidden(hidden: Boolean) {
        globalStorageProvider.set(
            HIDE_UNVERIFIED_NFTS,
            hidden,
            IGlobalStorageProvider.PERSIST_INSTANT
        )
    }

    fun getAreNoCostTokensHidden(): Boolean =
        globalStorageProvider.getBool(HIDE_NO_COST_TOKENS) != false

    fun setAreNoCostTokensHidden(hidden: Boolean) {
        globalStorageProvider.set(
            HIDE_NO_COST_TOKENS,
            hidden,
            IGlobalStorageProvider.PERSIST_INSTANT
        )
    }

    fun getUseLocalizedTokenNames(): Boolean = _useLocalizedTokenNames

    fun setUseLocalizedTokenNames(use: Boolean) {
        _useLocalizedTokenNames = use
        globalStorageProvider.set(
            USE_LOCALIZED_TOKEN_NAMES,
            use,
            IGlobalStorageProvider.PERSIST_INSTANT
        )
    }

    fun getBaseCurrency(): String = globalStorageProvider.getString(BASE_CURRENCY) ?: "USD"

    fun setBaseCurrency(baseCurrency: String) {
        globalStorageProvider.setEmptyObject(
            "tokenPriceHistory.bySlug",
            IGlobalStorageProvider.PERSIST_NO
        )
        globalStorageProvider.set(
            BASE_CURRENCY,
            baseCurrency,
            IGlobalStorageProvider.PERSIST_INSTANT
        )
    }

    private fun cachedActivitiesKey(accountId: String, slug: String?): String = if (slug == null) {
        "byAccountId.$accountId.activities.idsMain"
    } else {
        "byAccountId.$accountId.activities.idsBySlug.$slug"
    }

    fun hasCachedActivities(accountId: String, slug: String?): Boolean =
        globalStorageProvider.contains(cachedActivitiesKey(accountId, slug))

    fun getActivityIds(accountId: String, slug: String?): Array<String>? {
        val ids = globalStorageProvider.getArray(cachedActivitiesKey(accountId, slug))
        return ids?.let {
            return Array(it.length()) { index -> it.getString(index) }
        }
    }

    fun isHistoryEndReached(accountId: String, tokenSlug: String?): Boolean {
        val key = if (tokenSlug == null) {
            "byAccountId.$accountId.activities.isMainHistoryEndReached"
        } else {
            "byAccountId.$accountId.activities.isHistoryEndReachedBySlug.$tokenSlug"
        }
        return globalStorageProvider.getBool(key) ?: false
    }

    fun setIsHistoryEndReached(accountId: String, tokenSlug: String?, value: Boolean) {
        val key = if (tokenSlug == null) {
            "byAccountId.$accountId.activities.isMainHistoryEndReached"
        } else {
            "byAccountId.$accountId.activities.isHistoryEndReachedBySlug.$tokenSlug"
        }
        return globalStorageProvider.set(key, value, IGlobalStorageProvider.PERSIST_NORMAL)
    }

    fun getActivitiesDict(accountId: String): JSONObject? =
        globalStorageProvider.getDict("byAccountId.$accountId.activities.byId")

    fun setActivitiesDict(accountId: String, dict: JSONObject) {
        globalStorageProvider.set(
            "byAccountId.$accountId.activities.byId",
            value = dict,
            IGlobalStorageProvider.PERSIST_NO
        )
    }

    fun getNewestActivitiesBySlug(accountId: String): Map<String, JSONObject>? {
        val map = mutableMapOf<String, JSONObject>()
        val jsonObject =
            globalStorageProvider.getDict(
                "byAccountId.$accountId.activities.newestActivitiesBySlug"
            )
                ?: return null
        val keys = jsonObject.keys()
        while (keys.hasNext()) {
            val key = keys.next()
            jsonObject.optJSONObject(key)?.let { value ->
                map[key] = value
            }
        }
        return map
    }

    fun setNewestActivitiesBySlug(
        accountId: String,
        activities: Map<String, JSONObject?>?,
        persistInstantly: Int
    ) {
        val activities = activities ?: run {
            globalStorageProvider.remove(
                "byAccountId.$accountId.activities.newestActivitiesBySlug",
                persistInstantly
            )
            return
        }
        globalStorageProvider.set(
            activities.mapKeys { (key, _) ->
                "byAccountId.$accountId.activities.newestActivitiesBySlug.$key"
            },
            persistInstantly
        )
    }

    fun getBalancesDict(accountId: String): JSONObject? =
        globalStorageProvider.getDict("byAccountId.$accountId.balances.bySlug")

    fun setBalancesDict(accountId: String, dict: JSONObject) {
        globalStorageProvider.set(
            "byAccountId.$accountId.balances.bySlug",
            value = dict,
            IGlobalStorageProvider.PERSIST_NORMAL
        )
    }

    fun setActivityIds(accountId: String, tokenSlug: String?, ids: Array<String>) {
        val key = if (tokenSlug == null) {
            "byAccountId.$accountId.activities.idsMain"
        } else {
            "byAccountId.$accountId.activities.idsBySlug.$tokenSlug"
        }
        globalStorageProvider.set(
            key,
            value = JSONArray(ids),
            IGlobalStorageProvider.PERSIST_NORMAL
        )
    }

    fun currentTokenPeriod(accountId: String): String =
        globalStorageProvider.getString("byAccountId.$accountId.currentTokenPeriod") ?: "1D"

    fun setCurrentTokenPeriod(accountId: String, period: String) {
        globalStorageProvider.set(
            "byAccountId.$accountId.currentTokenPeriod",
            value = period,
            IGlobalStorageProvider.PERSIST_NORMAL
        )
    }

    fun getIsTokenChartExpanded(): Boolean =
        globalStorageProvider.getBool(IS_TOKEN_CHART_EXPANDED) ?: false

    fun setIsTokenChartExpanded(isExpanded: Boolean) {
        globalStorageProvider.set(
            IS_TOKEN_CHART_EXPANDED,
            isExpanded,
            IGlobalStorageProvider.PERSIST_INSTANT
        )
    }

    fun getIsTokenInfoExpanded(): Boolean =
        globalStorageProvider.getBool(IS_TOKEN_INFO_EXPANDED) ?: true

    fun setIsTokenInfoExpanded(isExpanded: Boolean) {
        globalStorageProvider.set(
            IS_TOKEN_INFO_EXPANDED,
            isExpanded,
            IGlobalStorageProvider.PERSIST_INSTANT
        )
    }

    fun currentPortfolioPeriod(accountId: String): String? =
        globalStorageProvider.getString("byAccountId.$accountId.currentPortfolioPeriod")

    fun setCurrentPortfolioPeriod(accountId: String, period: String) {
        globalStorageProvider.set(
            "byAccountId.$accountId.currentPortfolioPeriod",
            value = period,
            IGlobalStorageProvider.PERSIST_NORMAL
        )
    }

    fun getCardBackgroundNft(accountId: String): JSONObject? =
        globalStorageProvider.getDict("settings.byAccountId.$accountId.cardBackgroundNft")

    fun getCardBackgroundNftAddress(accountId: String): String? =
        globalStorageProvider.getString("settings.byAccountId.$accountId.cardBackgroundNft.address")

    fun setCardBackgroundNft(accountId: String, nft: JSONObject?) = globalStorageProvider.set(
        "settings.byAccountId.$accountId.cardBackgroundNft",
        nft,
        IGlobalStorageProvider.PERSIST_INSTANT
    )

    fun getIsAllowSuspiciousActions(accountId: String): Boolean = globalStorageProvider.getBool(
        "settings.byAccountId.$accountId.isAllowSuspiciousActions"
    ) == true

    fun setIsAllowSuspiciousActions(accountId: String, isEnabled: Boolean) {
        globalStorageProvider.set(
            "settings.byAccountId.$accountId.isAllowSuspiciousActions",
            if (isEnabled) true else null,
            IGlobalStorageProvider.PERSIST_NORMAL
        )
    }

    fun getOwnedMtwCardAddresses(accountId: String): Set<String> {
        val arr = globalStorageProvider.getArray(
            "byAccountId.$accountId.nfts.ownedMwCardAddresses"
        ) ?: return emptySet()
        val result = LinkedHashSet<String>(arr.length())
        for (i in 0 until arr.length()) {
            arr.optString(i, null)?.takeIf { it.isNotEmpty() }?.let(result::add)
        }
        return result
    }

    fun setOwnedMtwCardAddresses(accountId: String, addresses: Collection<String>) {
        val array = JSONArray()
        addresses.forEach { array.put(it) }
        globalStorageProvider.set(
            "byAccountId.$accountId.nfts.ownedMwCardAddresses",
            array,
            IGlobalStorageProvider.PERSIST_NORMAL
        )
    }

    fun getAccentColorNft(accountId: String): JSONObject? =
        globalStorageProvider.getDict("settings.byAccountId.$accountId.accentColorNft")

    fun getNftAccentColorIndex(accountId: String): Int? =
        globalStorageProvider.getInt("settings.byAccountId.$accountId.accentColorIndex")

    fun setNftAccentColor(accountId: String, accentColorIndex: Int?, nft: JSONObject?) {
        globalStorageProvider.set(
            "settings.byAccountId.$accountId.accentColorIndex",
            accentColorIndex,
            IGlobalStorageProvider.PERSIST_INSTANT
        )
        globalStorageProvider.set(
            "settings.byAccountId.$accountId.accentColorNft",
            nft,
            IGlobalStorageProvider.PERSIST_INSTANT
        )
    }

    fun setPriceHistory(tokenSlug: String, period: String, data: Array<Array<Double>>?) {
        globalStorageProvider.set(
            key = "${PRICE_HISTORY}.$tokenSlug.$period",
            value = if (data != null) {
                JSONArray().apply {
                    data.forEach { innerArray ->
                        put(JSONArray(innerArray))
                    }
                }
            } else {
                null
            },
            persistInstantly = IGlobalStorageProvider.PERSIST_NORMAL
        )
    }

    fun getPriceHistory(tokenSlug: String, period: String): Array<Array<Double>>? {
        val jsonArray = globalStorageProvider.getArray(
            "${PRICE_HISTORY}.$tokenSlug.$period"
        ) ?: return null
        return Array(jsonArray.length()) { i ->
            val innerArray = jsonArray.getJSONArray(i)
            Array(innerArray.length()) { j ->
                innerArray.getDouble(j)
            }
        }
    }

    fun clearPriceHistory() {
        globalStorageProvider.setEmptyObject(PRICE_HISTORY, IGlobalStorageProvider.PERSIST_INSTANT)
    }

    fun getAppLock(): MAutoLockOption {
        return MAutoLockOption.fromValue(
            globalStorageProvider.getString(AUTO_LOCK_VALUE)
        ) ?: MAutoLockOption.THIRTY_SECONDS // for unknown values!
    }

    fun setAutoLock(timeValue: MAutoLockOption) {
        if (timeValue != MAutoLockOption.NEVER) {
            globalStorageProvider.set(
                IS_APP_LOCK_ENABLED,
                true,
                IGlobalStorageProvider.PERSIST_NO
            )
        }
        globalStorageProvider.set(
            AUTO_LOCK_VALUE,
            timeValue.value,
            IGlobalStorageProvider.PERSIST_INSTANT
        )
    }

    fun isAppLockEnabled(): Boolean = globalStorageProvider.getBool(IS_APP_LOCK_ENABLED) != false

    fun setIsAppLockEnabled(value: Boolean) {
        globalStorageProvider.set(
            IS_APP_LOCK_ENABLED,
            value,
            IGlobalStorageProvider.PERSIST_INSTANT
        )
    }

    fun toggleSensitiveDataHidden() {
        _isSensitiveDataProtectionOn = !_isSensitiveDataProtectionOn
        globalStorageProvider.set(
            IS_SENSITIVE_DATA_HIDDEN,
            _isSensitiveDataProtectionOn,
            IGlobalStorageProvider.PERSIST_INSTANT
        )
        WalletContextManager.delegate?.get()?.protectedModeChanged()
    }

    fun getIsSensitiveDataProtectionOn(): Boolean = _isSensitiveDataProtectionOn

    fun setPushNotificationsToken(userToken: String) = globalStorageProvider.set(
        mapOf(
            PUSH_NOTIFICATIONS_TOKEN to userToken,
            "pushNotifications.platform" to "android"
        ),
        IGlobalStorageProvider.PERSIST_INSTANT
    )

    fun setPushNotificationAccounts(enabledAccounts: List<String>) = globalStorageProvider.set(
        PUSH_NOTIFICATIONS_ENABLED_ACCOUNTS,
        JSONArray(enabledAccounts),
        IGlobalStorageProvider.PERSIST_INSTANT
    )

    fun setPushNotificationAccount(accountId: String) {
        val currentAccounts =
            getPushNotificationsEnabledAccounts()?.toMutableList() ?: mutableListOf()
        if (!currentAccounts.contains(accountId)) {
            currentAccounts.add(accountId)
        }
        globalStorageProvider.set(
            PUSH_NOTIFICATIONS_ENABLED_ACCOUNTS,
            JSONArray(currentAccounts),
            IGlobalStorageProvider.PERSIST_INSTANT
        )
    }

    fun removePushNotificationAccount(accountId: String) {
        val currentAccounts = getPushNotificationsEnabledAccounts() ?: return
        globalStorageProvider.set(
            PUSH_NOTIFICATIONS_ENABLED_ACCOUNTS,
            JSONArray(currentAccounts.filter { it != accountId }),
            IGlobalStorageProvider.PERSIST_INSTANT
        )
    }

    fun getPushNotificationsToken(): String? =
        globalStorageProvider.getString(PUSH_NOTIFICATIONS_TOKEN)

    fun getPushNotificationsEnabledAccounts(): List<String>? {
        val arr = globalStorageProvider.getArray(PUSH_NOTIFICATIONS_ENABLED_ACCOUNTS)
            ?: return null
        return ArrayList(
            List(arr.length()) { i ->
                arr.getString(i)
            }
        )
    }

    fun getBlacklistedNftAddresses(accountId: String): ArrayList<String> {
        val arr = globalStorageProvider.getArray("byAccountId.$accountId.blacklistedNftAddresses")
            ?: return ArrayList()
        return ArrayList(
            List(arr.length()) { i ->
                arr.getString(i)
            }
        )
    }

    fun setBlacklistedNftAddresses(accountId: String, array: List<String>) {
        globalStorageProvider.set(
            "byAccountId.$accountId.blacklistedNftAddresses",
            JSONArray(array),
            IGlobalStorageProvider.PERSIST_NORMAL
        )
    }

    fun getWhitelistedNftAddresses(accountId: String): ArrayList<String> {
        val arr = globalStorageProvider.getArray("byAccountId.$accountId.whitelistedNftAddresses")
            ?: return ArrayList()
        return ArrayList(
            List(arr.length()) { i ->
                arr.getString(i)
            }
        )
    }

    fun setWhitelistedNftAddresses(accountId: String, array: List<String>) {
        globalStorageProvider.set(
            "byAccountId.$accountId.whitelistedNftAddresses",
            JSONArray(array),
            IGlobalStorageProvider.PERSIST_NORMAL
        )
    }

    fun setHomeNftCollections(accountId: String, collections: List<MCollectionTab>) {
        globalStorageProvider.set(
            "byAccountId.$accountId.nfts.collectionTabs",
            JSONArray().apply {
                collections.forEach { tab ->
                    put(
                        JSONObject().apply {
                            put("address", tab.address)
                            put("chain", tab.chain)
                        }
                    )
                }
            },
            IGlobalStorageProvider.PERSIST_INSTANT
        )
    }

    fun getHomeNftCollections(accountId: String): ArrayList<MCollectionTab> {
        val arr = globalStorageProvider.getArray("byAccountId.$accountId.nfts.collectionTabs")
            ?: return ArrayList()
        return ArrayList<MCollectionTab>(arr.length()).apply {
            for (i in 0 until arr.length()) {
                val obj = arr.optJSONObject(i) ?: continue
                val chain = obj.optString("chain").takeIf { it.isNotEmpty() } ?: continue
                val address = obj.optString("address").takeIf { it.isNotEmpty() } ?: continue
                add(MCollectionTab(chain, address))
            }
        }
    }

    private val HOME_ASSETS_LIMIT_ALLOWED = setOf(5, 10, 30)
    private const val HOME_ASSETS_LIMIT_DEFAULT = 5
    fun setHomeAssetsTopLimit(accountId: String, limit: Int) {
        val safeLimit =
            if (HOME_ASSETS_LIMIT_ALLOWED.contains(limit)) limit else HOME_ASSETS_LIMIT_DEFAULT
        globalStorageProvider.set(
            "byAccountId.$accountId.tokens.homeTopLimit",
            safeLimit,
            IGlobalStorageProvider.PERSIST_INSTANT
        )
    }

    fun getHomeAssetsTopLimit(accountId: String): Int {
        val current = globalStorageProvider.getInt("byAccountId.$accountId.tokens.homeTopLimit")
            ?: return HOME_ASSETS_LIMIT_DEFAULT
        return if (HOME_ASSETS_LIMIT_ALLOWED.contains(
                current
            )
        ) {
            current
        } else {
            HOME_ASSETS_LIMIT_DEFAULT
        }
    }

    fun setWasTelegramGiftsAutoAdded(accountId: String, value: Boolean) {
        globalStorageProvider.set(
            "byAccountId.$accountId.nfts.wasTelegramGiftsAutoAdded",
            value,
            IGlobalStorageProvider.PERSIST_NORMAL
        )
    }

    fun getWasTelegramGiftsAutoAdded(accountId: String): Boolean =
        globalStorageProvider.getBool("byAccountId.$accountId.nfts.wasTelegramGiftsAutoAdded") ==
            true

    fun setAccountConfig(accountId: String, config: JSONObject) {
        globalStorageProvider.set(
            "byAccountId.$accountId.config",
            config,
            IGlobalStorageProvider.PERSIST_NORMAL
        )
    }

    fun removeAccountImportedAt(accountId: String) {
        globalStorageProvider.remove(
            "accounts.byId.$accountId.importedAt",
            IGlobalStorageProvider.PERSIST_NORMAL
        )
    }

    fun setAccountAddresses(accountId: String, addressArray: JSONArray) {
        globalStorageProvider.set(
            "byAccountId.$accountId.savedAddresses",
            addressArray,
            IGlobalStorageProvider.PERSIST_NORMAL
        )
    }

    fun getAccountAddresses(accountId: String): JSONArray? =
        globalStorageProvider.getArray("byAccountId.$accountId.savedAddresses")

    fun setLangCode(langCode: String) {
        globalStorageProvider.set(
            LANG_CODE,
            langCode,
            IGlobalStorageProvider.PERSIST_NO
        )
        cachedLangCode = langCode
    }

    fun setLangSource(langSource: String) {
        globalStorageProvider.set(
            LANG_SOURCE,
            langSource,
            IGlobalStorageProvider.PERSIST_INSTANT
        )
    }

    fun getLangCode(): String {
        val storedLangCode = globalStorageProvider.getString(LANG_CODE)

        val resolved = cachedLangCode
            // `appSpecificLanguageCode` is the language user selected for the app from App Settings or OS Settings
            // It's guaranteed to have correct value at this stage, unless user didn't set language at all
            ?: LocaleController.appSpecificLanguageCode()
            // Fallback to OS Language if supported
            ?: LocaleController.resolveSystemLanguageCode(
                ApplicationContextHolder.applicationContext
            )
            // This should not happen usually, unless user has a system language which MTW doesn't support
            ?: storedLangCode
            ?: WLanguage.ENGLISH.langCode
        cachedLangCode = resolved
        return resolved
    }

    fun getCardsInfo(accountId: String): JSONObject? =
        globalStorageProvider.getDict("byAccountId.$accountId.config.cardsInfo")

    fun getActivePromotion(accountId: String): JSONObject? =
        globalStorageProvider.getDict("byAccountId.$accountId.config.activePromotion")

    fun getAccountConfigIsMfaEnabled(accountId: String): Boolean =
        globalStorageProvider.getBool("byAccountId.$accountId.config.isMfaEnabled") == true

    fun isMultichain(accountId: String): Boolean =
        globalStorageProvider.keysIn("accounts.byId.$accountId.byChain").size > 1

    fun setCurrencyRates(rates: Map<String, Double>?) = globalStorageProvider.set(
        "currencyRates",
        rates?.let { JSONObject(it) },
        IGlobalStorageProvider.PERSIST_NORMAL
    )

    fun getCurrencyRates(): JSONObject? = globalStorageProvider.getDict("currencyRates")

    fun setAccountSelectorViewMode(mode: MWalletSettingsViewMode) = globalStorageProvider.set(
        "accountSelectorViewMode",
        mode.value,
        IGlobalStorageProvider.PERSIST_NORMAL
    )

    fun getAccountSelectorViewMode(): MWalletSettingsViewMode? = MWalletSettingsViewMode.fromValue(
        globalStorageProvider.getString("accountSelectorViewMode")
    )

    fun setTabletPanelWidth(widthDp: Int) {
        globalStorageProvider.set(
            TABLET_PANEL_WIDTH,
            widthDp,
            IGlobalStorageProvider.PERSIST_NORMAL
        )
    }

    fun getTabletPanelWidth(): Int? = globalStorageProvider.getInt(TABLET_PANEL_WIDTH)

    fun setWalletTabOrder(order: List<String>) {
        globalStorageProvider.set(
            "settings.walletTabOrder",
            JSONArray(order),
            IGlobalStorageProvider.PERSIST_NORMAL
        )
    }

    fun getWalletTabOrder(): List<String>? {
        val arr = globalStorageProvider.getArray("settings.walletTabOrder") ?: return null
        return (0 until arr.length()).map { arr.getString(it) }
    }

    fun setAppTabOrder(order: List<String>) {
        globalStorageProvider.set(
            APP_TAB_ORDER,
            JSONArray(order),
            IGlobalStorageProvider.PERSIST_INSTANT
        )
    }

    fun getAppTabOrder(): List<String>? {
        val arr = globalStorageProvider.getArray(APP_TAB_ORDER) ?: return null
        return (0 until arr.length()).map { arr.getString(it) }
    }

    fun getPreferredExplorer(chain: String): String? =
        globalStorageProvider.getString("$EXPLORER.$chain")

    fun setPreferredExplorer(chain: String, explorerIdentifier: String) {
        globalStorageProvider.set(
            "$EXPLORER.$chain",
            explorerIdentifier,
            IGlobalStorageProvider.PERSIST_NORMAL
        )
    }

    fun getIsSeasonalThemingDisabled(): Boolean =
        globalStorageProvider.getBool(IS_SEASONAL_THEMING_DISABLED) == true

    fun setIsSeasonalThemingDisabled(disabled: Boolean) {
        globalStorageProvider.set(
            IS_SEASONAL_THEMING_DISABLED,
            disabled,
            IGlobalStorageProvider.PERSIST_INSTANT
        )
    }

    fun getIsScreenRecordWarningDisabled(): Boolean =
        globalStorageProvider.getBool(IS_SCREEN_RECORD_WARNING_DISABLED) == true

    fun setIsScreenRecordWarningDisabled(disabled: Boolean) {
        globalStorageProvider.set(
            IS_SCREEN_RECORD_WARNING_DISABLED,
            disabled,
            IGlobalStorageProvider.PERSIST_NORMAL
        )
    }

    fun getTokenInfoDebugSource(): String? =
        globalStorageProvider.getString(TOKEN_INFO_DEBUG_SOURCE)

    fun setTokenInfoDebugSource(source: String) {
        globalStorageProvider.set(
            TOKEN_INFO_DEBUG_SOURCE,
            source,
            IGlobalStorageProvider.PERSIST_NORMAL
        )
    }

    fun getIsShakeToDebugEnabled(): Boolean =
        globalStorageProvider.getBool(IS_SHAKE_TO_DEBUG_ENABLED)
            ?: org.mytonwallet.app_air.walletbasecontext.DEBUG_MODE

    fun setIsShakeToDebugEnabled(enabled: Boolean) {
        globalStorageProvider.set(
            IS_SHAKE_TO_DEBUG_ENABLED,
            enabled,
            IGlobalStorageProvider.PERSIST_NORMAL
        )
    }

    fun getAreExperimentalFeaturesEnabled(): Boolean =
        globalStorageProvider.getBool(ARE_EXPERIMENTAL_FEATURES_ENABLED) ?: false

    fun setAreExperimentalFeaturesEnabled(enabled: Boolean) {
        globalStorageProvider.set(
            ARE_EXPERIMENTAL_FEATURES_ENABLED,
            enabled,
            IGlobalStorageProvider.PERSIST_NORMAL
        )
    }

    private const val LAST_STATE: Int = 60

    fun migrate() {
        // Lock the storage
        incDoNotSynchronize()

        var currentState = globalStorageProvider.getInt(STATE_VERSION)
        if (currentState == null || currentState == 0) {
            normalizeLegacySingleAccountStateIfNeeded()
            val hasAccounts = globalStorageProvider.keysIn("accounts.byId").isNotEmpty()
            if (hasAccounts) {
                ensureValidCurrentAccountId()
                currentState = 1
            }
        }

        if (currentState == null) {
            globalStorageProvider.set(
                STATE_VERSION,
                LAST_STATE,
                IGlobalStorageProvider.PERSIST_INSTANT
            )
            decDoNotSynchronize()
            return
        }

        if (currentState >= LAST_STATE) {
            decDoNotSynchronize()
            return
        }

        // State 1→2: keep only TON token info
        if (currentState < 2) {
            globalStorageProvider.getDict("tokenInfo.bySlug.toncoin")?.let { toncoin ->
                globalStorageProvider.set(
                    "tokenInfo.bySlug",
                    JSONObject().apply { put("toncoin", toncoin) },
                    IGlobalStorageProvider.PERSIST_NO
                )
            }
        }

        // State 2→3: normalize the main account ID and add matching testnet accounts
        if (currentState < 3) {
            normalizeLegacyAccountIdsAndAddTestnetAccounts()
        }

        // States 1→2, 3→4, and 5→7: remove legacy transactions
        if (currentState < 7) {
            removeAccountStateField("transactions")
        }

        // State 4→5: initialize the legacy staking state
        if (currentState < 5) {
            globalStorageProvider.set(
                "staking",
                JSONObject().apply { put("state", "none") },
                IGlobalStorageProvider.PERSIST_NO
            )
        }

        // State 7→8: remove legacy backup data
        if (currentState < 8) {
            removeAccountStateField("backupWallet")
        }

        // States 9→10 and 11→13: clear incompatible activity caches
        if (currentState < 13) {
            removeAccountStateField("activities")
        }

        // State 10→11: default the legacy zero-balance token filter to hidden
        if (currentState < 11 &&
            !globalStorageProvider.contains("settings.areTokensWithNoBalanceHidden")
        ) {
            globalStorageProvider.set(
                "settings.areTokensWithNoBalanceHidden",
                true,
                IGlobalStorageProvider.PERSIST_NO
            )
        }

        // States 13→14: set areTokensWithNoCostHidden from legacy flags
        if (currentState < 14) {
            val areTokensWithNoPriceHidden =
                globalStorageProvider.getBool("settings.areTokensWithNoPriceHidden") ?: false
            val areTokensWithNoBalanceHidden =
                globalStorageProvider.getBool("settings.areTokensWithNoBalanceHidden") ?: false
            globalStorageProvider.set(
                HIDE_NO_COST_TOKENS,
                areTokensWithNoPriceHidden || areTokensWithNoBalanceHidden,
                IGlobalStorageProvider.PERSIST_NO
            )
        }

        // State 24→25: account.address → account.addressByChain = { ton: address }
        if (currentState < 25) {
            for (accountId in accountIds(network = null)) {
                val account = getAccount(accountId) ?: continue
                val address = account.optString("address").takeIf { it.isNotEmpty() } ?: continue
                account.put("addressByChain", JSONObject().apply { put("ton", address) })
                account.remove("address")
                saveAccount(accountId, account)
            }
        }

        // State 25→26: savedAddresses {address: name} map → [{name, address, chain:'ton'}] array
        if (currentState < 26) {
            for (accountId in accountIds(network = null)) {
                val savedKey = "byAccountId.$accountId.savedAddresses"
                val savedObj = globalStorageProvider.getDict(savedKey) ?: continue
                val migrated = JSONArray()
                savedObj.keys().forEach { address ->
                    val name = savedObj.optString(address)
                    migrated.put(
                        JSONObject().apply {
                            put("name", name)
                            put("address", address)
                            put("chain", "ton")
                        }
                    )
                }
                globalStorageProvider.set(savedKey, migrated, IGlobalStorageProvider.PERSIST_NO)
            }
        }

        // States 26→29: delete settings.dapps;
        // migrate exceptionSlugs → alwaysShownSlugs / alwaysHiddenSlugs
        if (currentState < 29) {
            globalStorageProvider.remove("settings.dapps", IGlobalStorageProvider.PERSIST_NO)
            val areNoCostHidden = globalStorageProvider.getBool(HIDE_NO_COST_TOKENS) ?: false
            for (accountId in accountIds(network = null)) {
                val exceptionSlugsKey = "$ASSETS_AND_ACTIVITY.$accountId.exceptionSlugs"
                val exceptionSlugs = globalStorageProvider.getArray(exceptionSlugsKey) ?: continue
                val targetKey = if (areNoCostHidden) {
                    "$ASSETS_AND_ACTIVITY.$accountId.alwaysShownSlugs"
                } else {
                    "$ASSETS_AND_ACTIVITY.$accountId.alwaysHiddenSlugs"
                }
                globalStorageProvider.set(
                    targetKey,
                    exceptionSlugs,
                    IGlobalStorageProvider.PERSIST_NO
                )
                globalStorageProvider.remove(exceptionSlugsKey, IGlobalStorageProvider.PERSIST_NO)
            }
        }

        // States 29→32: set isAppLockEnabled if autolockValue is set
        if (currentState < 32) {
            val autolockValue = globalStorageProvider.getString("settings.autolockValue")
            if (autolockValue != null && autolockValue != "never") {
                globalStorageProvider.set(
                    "settings.isAppLockEnabled",
                    true,
                    IGlobalStorageProvider.PERSIST_NO
                )
            }
        }

        if (currentState < 36) {
            clearActivities()
        }

        if (currentState < 37) {
            accountIds().forEach { accountId ->
                val account = getAccount(accountId)
                val updatedType =
                    if (account?.optBoolean("isHardware") == true ||
                        account?.optString("type") == "hardware"
                    ) {
                        "hardware"
                    } else {
                        "mnemonic"
                    }
                account?.put("type", updatedType)
                account?.remove("isHardware")
                saveAccount(accountId, account)
            }
        }

        if (currentState <= 37) {
            fun migrateObject(tokenObj: JSONObject) {
                if (!tokenObj.has("price")) tokenObj.put("price", 0)
                if (!tokenObj.has("percentChange24h")) tokenObj.put("percentChange24h", 0)
                if (!tokenObj.has("priceUsd")) tokenObj.put("priceUsd", 0)
                if (tokenObj.has("quote")) tokenObj.remove("quote")
            }
            // Update Cache
            WCacheStorage.getTokens()?.let { tokensString ->
                val tokensJsonArray = JSONArray(tokensString)
                for (i in 0..<tokensJsonArray.length()) {
                    migrateObject(tokensJsonArray.optJSONObject(i) ?: continue)
                }
                WCacheStorage.setTokens(tokensJsonArray.toString())
            }
            // Update Tokens
            val tokensArray = globalStorageProvider.getArray("tokenInfo.bySlug") ?: JSONArray()
            for (i in 0..<tokensArray.length()) {
                migrateObject(tokensArray.optJSONObject(i) ?: continue)
            }
            globalStorageProvider.set(
                "tokenInfo.bySlug",
                tokensArray,
                IGlobalStorageProvider.PERSIST_NO
            )
        }

        if (currentState < 46) {
            clearActivities()

            val accountIds = accountIds()
            for (accountId in accountIds) {
                val account = getAccount(accountId)
                if (account != null) {
                    if (account.optJSONObject("byChain") != null) continue // Already migrated
                    val addressByChain = account.optJSONObject("addressByChain")
                    val domainByChain = account.optJSONObject("domainByChain")
                    val isMultisigByChain = account.optJSONObject("isMultisigByChain")

                    if (addressByChain != null) {
                        val byChain = JSONObject()
                        addressByChain.keys().forEach { chain ->
                            val chainData = JSONObject()
                            chainData.put("address", addressByChain.getString(chain))
                            domainByChain?.optString(chain)?.let { domain ->
                                if (domain.isNotEmpty()) {
                                    chainData.put("domain", domain)
                                }
                            }
                            isMultisigByChain?.optBoolean(chain)?.let { isMultisig ->
                                if (isMultisig) {
                                    chainData.put("isMultisig", true)
                                }
                            }
                            byChain.put(chain, chainData)
                        }
                        account.put("byChain", byChain)
                        account.remove("addressByChain")
                        account.remove("domainByChain")
                        account.remove("isMultisigByChain")
                        saveAccount(accountId, account)
                    }
                }
            }
        }

        if (currentState < 47) {
            val accountIds = accountIds(network = null)
            for (accountId in accountIds) {
                val account = getAccount(accountId) ?: continue
                if (account.optString("type") != "hardware") continue
                val byChain = account.optJSONObject("byChain") ?: continue
                val tonObj = byChain.optJSONObject("ton") ?: continue
                val ledgerObj = account.optJSONObject("ledger") ?: continue // Already migrated
                tonObj.put("ledgerIndex", ledgerObj.optInt("index"))
                account.remove("ledger")
                saveAccount(accountId, account)
            }
        }

        if (currentState < 48) {
            val enabledAccounts = globalStorageProvider.getDict(PUSH_NOTIFICATIONS_ENABLED_ACCOUNTS)
            if (enabledAccounts != null) {
                val accountIds = JSONArray()
                enabledAccounts.keys().forEach { key ->
                    accountIds.put(key)
                }
                globalStorageProvider.set(
                    PUSH_NOTIFICATIONS_ENABLED_ACCOUNTS,
                    accountIds,
                    IGlobalStorageProvider.PERSIST_NO
                )
            }
        }

        if (currentState < 49) {
            val accountIds = accountIds(network = null)
            for (accountId in accountIds) {
                setNewestActivitiesBySlug(accountId, null, IGlobalStorageProvider.PERSIST_NO)
            }
        }

        if (currentState < 50) {
            val uiMode = globalStorageProvider.getString("settings.uiMode")
            if (uiMode != null) {
                globalStorageProvider.set(
                    ARE_ROUNDED_TOOLBARS_ACTIVE,
                    uiMode != "compound",
                    IGlobalStorageProvider.PERSIST_NO
                )
                globalStorageProvider.remove("settings.uiMode", IGlobalStorageProvider.PERSIST_NO)
            }

            val accountIds = accountIds(network = null)
            for (accountId in accountIds) {
                if (globalStorageProvider.getArray("$ASSETS_AND_ACTIVITY.$accountId.pinnedSlugs") ==
                    null
                ) {
                    globalStorageProvider.set(
                        "$ASSETS_AND_ACTIVITY.$accountId.pinnedSlugs",
                        JSONArray(),
                        IGlobalStorageProvider.PERSIST_NO
                    )
                }
            }
        }

        if (currentState < 51) {
            clearActivities()
        }

        if (currentState < 52) {
            for (accountId in accountIds()) {
                val stakingData = WCacheStorage.getStakingData(accountId) ?: continue
                val pinnedVirtualStakingSlugs = mutableListOf<String>()
                try {
                    val stakingDataArray = JSONArray(stakingData)
                    for (i in 0 until stakingDataArray.length()) {
                        val staking = stakingDataArray.optJSONObject(i) ?: continue
                        val stakingAccountId = staking.optString("accountId")
                        if (stakingAccountId.isNotBlank() && stakingAccountId != accountId) {
                            continue
                        }
                        val stakingStates = staking.optJSONArray("states") ?: continue
                        for (j in 0 until stakingStates.length()) {
                            val state = stakingStates.optJSONObject(j) ?: continue
                            val tokenSlug = state.optString("tokenSlug")
                            if (!tokenSlug.isNullOrBlank()) {
                                pinnedVirtualStakingSlugs.add("staking-$tokenSlug")
                            }
                        }
                    }
                } catch (e: JSONException) {
                    Logger.e(
                        Logger.LogTag.WALLET_CORE,
                        "Storage migration 52 skipped invalid staking data " +
                            "error=${e.javaClass.simpleName}"
                    )
                    continue
                }

                if (pinnedVirtualStakingSlugs.isEmpty()) {
                    continue
                }

                val pinnedPath = "$ASSETS_AND_ACTIVITY.$accountId.pinnedSlugs"
                globalStorageProvider.getArray(pinnedPath)?.let { existingPinnedArray ->
                    for (i in 0 until existingPinnedArray.length()) {
                        val pinnedVirtualStakingSlug = existingPinnedArray.optString(i)
                        if (!pinnedVirtualStakingSlug.isNullOrBlank()) {
                            pinnedVirtualStakingSlugs.add(pinnedVirtualStakingSlug)
                        }
                    }
                }
                globalStorageProvider.set(
                    pinnedPath,
                    JSONArray(pinnedVirtualStakingSlugs.distinct()),
                    IGlobalStorageProvider.PERSIST_NO
                )
            }
        }

        if (currentState < 53) {
            val accountIds = accountIds(network = null)
            for (accountId in accountIds) {
                val arr =
                    globalStorageProvider.getArray("byAccountId.$accountId.nfts.collectionTabs")
                        ?: continue
                val migrated = JSONArray()
                for (i in 0 until arr.length()) {
                    val element = arr.get(i)
                    if (element is String) {
                        migrated.put(
                            JSONObject().apply {
                                put("address", element)
                                put("chain", "ton")
                            }
                        )
                    } else {
                        migrated.put(element)
                    }
                }
                globalStorageProvider.set(
                    "byAccountId.$accountId.nfts.collectionTabs",
                    migrated,
                    IGlobalStorageProvider.PERSIST_NO
                )
            }
        }

        if (currentState < 54 && !globalStorageProvider.contains(LANG_SOURCE)) {
            globalStorageProvider.set(
                LANG_SOURCE,
                LANG_SOURCE_USER,
                IGlobalStorageProvider.PERSIST_NO
            )
            LocaleController.setApplicationLocale(
                globalStorageProvider.getString(LANG_CODE) ?: WLanguage.ENGLISH.langCode
            )
        }

        if (currentState < 55) {
            clearActivities()
        }

        // State 55→56: walletTokensLimit (numeric Top-N preset) replaced by overviewCellSize enum
        if (currentState < 56) {
            for (accountId in accountIds(network = null)) {
                val limitKey = "settings.byAccountId.$accountId.walletTokensLimit"
                val cellSizeKey = "settings.byAccountId.$accountId.overviewCellSize"
                val limit = globalStorageProvider.getInt(limitKey)
                if (limit != null && !globalStorageProvider.contains(cellSizeKey)) {
                    val cellSize = when {
                        limit <= 7 -> "small"
                        limit < 30 -> "medium"
                        else -> "big"
                    }
                    globalStorageProvider.set(
                        cellSizeKey,
                        cellSize,
                        IGlobalStorageProvider.PERSIST_NO
                    )
                }
                globalStorageProvider.remove(limitKey, IGlobalStorageProvider.PERSIST_NO)
            }
        }

        // State 56→57: nfts.ownedMtwCardAddresses renamed to ownedMwCardAddresses (MTW → MW rebrand)
        if (currentState < 57) {
            for (accountId in accountIds(network = null)) {
                val oldKey = "byAccountId.$accountId.nfts.ownedMtwCardAddresses"
                val newKey = "byAccountId.$accountId.nfts.ownedMwCardAddresses"
                val addresses = globalStorageProvider.getArray(oldKey) ?: continue
                globalStorageProvider.set(newKey, addresses, IGlobalStorageProvider.PERSIST_NO)
                globalStorageProvider.remove(oldKey, IGlobalStorageProvider.PERSIST_NO)
            }
        }

        // State 57→58: Net Change was replaced by PnL Change
        if (currentState < 58) {
            globalStorageProvider.remove(
                "portfolio.netChangeByAccountId",
                IGlobalStorageProvider.PERSIST_NO
            )
        }

        // State 58→59: clear cached activities
        if (currentState < 59) {
            clearActivities()
        }

        // State 59→60: drop legacy auth data unless it is still needed for the Enclave migration
        if (currentState < 60) {
            val hasPasscode = isPasscodeSet()
            if (!hasPasscode) {
                removeLegacyAuthData()
            }
            if (hasPasscode && !isLegacyBiometricActivated()) {
                // Ensure no unnecessary biometric passcodes are stored
                WSecureStorage.deleteLegacyBiometricPasscode()
                removeIsLegacyBiometricActivated()
            }
        }

        // Update and unlock the storage
        globalStorageProvider.set(STATE_VERSION, LAST_STATE, IGlobalStorageProvider.PERSIST_INSTANT)
        decDoNotSynchronize()
    }

    private fun normalizeLegacySingleAccountStateIfNeeded() {
        if (globalStorageProvider.contains("byAccountId")) {
            return
        }

        val addressesByAccountId = globalStorageProvider.getDict("addresses.byAccountId")
            ?: return
        val address = addressesByAccountId.optString(MAIN_ACCOUNT_ID).takeIf { it.isNotEmpty() }
            ?: addressesByAccountId.optString(LEGACY_MAIN_ACCOUNT_ID).takeIf { it.isNotEmpty() }
            ?: addressesByAccountId.keys().asSequence()
                .mapNotNull { key ->
                    addressesByAccountId.optString(key).takeIf { it.isNotEmpty() }
                }
                .firstOrNull()
            ?: return

        val account = JSONObject().apply {
            put("address", address)
            put("title", "Main Account")
        }
        val storedAccount = globalStorageProvider.getDict("accounts.byId.$MAIN_ACCOUNT_ID")
            ?: globalStorageProvider.getDict("accounts.byId.$LEGACY_MAIN_ACCOUNT_ID")
        storedAccount?.keys()?.forEach { key ->
            account.put(key, storedAccount.get(key))
        }

        val accountState = JSONObject().apply {
            put(
                "isBackupRequired",
                globalStorageProvider.getBool("isBackupRequired") == true
            )
            globalStorageProvider.getString("currentTokenSlug")?.let {
                put("currentTokenSlug", it)
            }
            globalStorageProvider.getString("currentTokenPeriod")?.let {
                put("currentTokenPeriod", it)
            }
            (
                globalStorageProvider.getDict("balances.byAccountId.$MAIN_ACCOUNT_ID")
                    ?: globalStorageProvider.getDict("balances.byAccountId.$LEGACY_MAIN_ACCOUNT_ID")
                )
                ?.let { put("balances", it) }
            globalStorageProvider.getDict("transactions")?.let { put("transactions", it) }
            globalStorageProvider.getDict("nfts")?.let { put("nfts", it) }
            globalStorageProvider.getDict("savedAddresses")?.let { put("savedAddresses", it) }
        }

        globalStorageProvider.set(
            mapOf(
                "accounts.byId" to JSONObject().apply { put(MAIN_ACCOUNT_ID, account) },
                "byAccountId" to JSONObject().apply { put(MAIN_ACCOUNT_ID, accountState) }
            ),
            IGlobalStorageProvider.PERSIST_NO
        )
        globalStorageProvider.remove(
            arrayOf(
                "addresses",
                "balances",
                "transactions",
                "nfts",
                "savedAddresses",
                "backupWallet"
            ),
            IGlobalStorageProvider.PERSIST_NO
        )
        cachedAccountIds = null
    }

    private fun ensureValidCurrentAccountId() {
        val accountIds = globalStorageProvider.keysIn("byAccountId")
        if (accountIds.isEmpty()) {
            return
        }

        val currentAccountId = globalStorageProvider.getString(CURRENT_ACCOUNT_ID)
        if (currentAccountId == null || currentAccountId !in accountIds) {
            globalStorageProvider.set(
                CURRENT_ACCOUNT_ID,
                accountIds.first(),
                IGlobalStorageProvider.PERSIST_NO
            )
        }
    }

    private fun normalizeLegacyAccountIdsAndAddTestnetAccounts() {
        val accounts = globalStorageProvider.getDict("accounts.byId") ?: return
        val accountStates = globalStorageProvider.getDict("byAccountId") ?: JSONObject()

        if (accounts.has(LEGACY_MAIN_ACCOUNT_ID)) {
            accounts.put(MAIN_ACCOUNT_ID, accounts.get(LEGACY_MAIN_ACCOUNT_ID))
            accounts.remove(LEGACY_MAIN_ACCOUNT_ID)

            if (accountStates.has(LEGACY_MAIN_ACCOUNT_ID)) {
                accountStates.put(MAIN_ACCOUNT_ID, accountStates.get(LEGACY_MAIN_ACCOUNT_ID))
                accountStates.remove(LEGACY_MAIN_ACCOUNT_ID)
            }

            if (globalStorageProvider.getString(CURRENT_ACCOUNT_ID) == LEGACY_MAIN_ACCOUNT_ID) {
                globalStorageProvider.set(
                    CURRENT_ACCOUNT_ID,
                    MAIN_ACCOUNT_ID,
                    IGlobalStorageProvider.PERSIST_NO
                )
            }
        }

        val accountIds = accounts.keys().asSequence().toList()
        for (accountId in accountIds) {
            val testnetAccountId = getLegacyTestnetAccountId(accountId)
            val account = accounts.optJSONObject(accountId) ?: continue
            accounts.put(testnetAccountId, JSONObject(account.toString()))
            accountStates.put(testnetAccountId, JSONObject())
        }

        globalStorageProvider.set(
            mapOf(
                "accounts.byId" to accounts,
                "byAccountId" to accountStates
            ),
            IGlobalStorageProvider.PERSIST_NO
        )
        cachedAccountIds = null
    }

    private fun getLegacyTestnetAccountId(accountId: String): String {
        val id = accountId.split('-').firstNotNullOfOrNull { it.toIntOrNull() } ?: 0
        return "$id-testnet"
    }

    private fun removeAccountStateField(field: String) {
        for (accountId in globalStorageProvider.keysIn("byAccountId")) {
            globalStorageProvider.remove(
                "byAccountId.$accountId.$field",
                IGlobalStorageProvider.PERSIST_NO
            )
        }
    }

    fun setTokenInfo(jsonObject: JSONObject) {
        globalStorageProvider.set(
            "tokenInfo.bySlug",
            jsonObject,
            IGlobalStorageProvider.PERSIST_INSTANT
        )
    }

    private fun clearActivities() {
        accountIds().forEach { accountId ->
            globalStorageProvider.remove(
                "byAccountId.$accountId.activities",
                IGlobalStorageProvider.PERSIST_NO
            )
            globalStorageProvider.remove(
                "byAccountId.$accountId.activities.newestActivitiesBySlug",
                IGlobalStorageProvider.PERSIST_NO
            )
        }
    }

    private fun removeLegacyAuthData() {
        WSecureStorage.removeLegacyMnemonics { true }
        WSecureStorage.deleteLegacyBiometricPasscode()
        removeIsLegacyBiometricActivated()
    }

    fun getSuggestedName(network: MBlockchainNetwork, type: String): String {
        val baseNameKey = when (type) {
            "mnemonic" -> if (ApplicationContextHolder.isGramApp) "Wallet" else "My Wallet"
            "hardware" -> "Ledger"
            else -> "Wallet"
        }
        return getSuggestedAccountName(network = network, type = type, baseNameKey = baseNameKey)
    }

    private fun getSuggestedAccountName(
        network: MBlockchainNetwork,
        type: String,
        baseNameKey: String
    ): String {
        val prefix = if (network.isMainnet) "" else "Testnet "
        if (accountIds(network = network).isEmpty()) {
            return "$prefix${
                LocaleController.getString(
                    ApplicationContextHolder.applicationContext.getString(
                        BaseR.string.app_locale_name_key
                    )
                )
            }"
        }
        val count = countAccountsByType(network = network, type = type)
        return "$prefix$baseNameKey ${count + 1}"
    }

    private fun countAccountsByType(network: MBlockchainNetwork, type: String): Int =
        accountIds(network = network).count { accountId ->
            getAccount(accountId)?.optString("type") ==
                type
        }
}
