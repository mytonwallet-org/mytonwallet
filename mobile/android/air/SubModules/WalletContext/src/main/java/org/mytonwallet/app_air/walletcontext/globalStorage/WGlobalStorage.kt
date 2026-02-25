package org.mytonwallet.app_air.walletcontext.globalStorage

import org.json.JSONArray
import org.json.JSONObject
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.localization.WLanguage
import org.mytonwallet.app_air.walletbasecontext.theme.ThemeManager
import org.mytonwallet.app_air.walletbasecontext.utils.ApplicationContextHolder
import org.mytonwallet.app_air.walletcontext.WalletContextManager
import org.mytonwallet.app_air.walletcontext.cacheStorage.WCacheStorage
import org.mytonwallet.app_air.walletcontext.models.MAutoLockOption
import org.mytonwallet.app_air.walletcontext.models.MBlockchainNetwork
import org.mytonwallet.app_air.walletcontext.models.MCollectionTab
import org.mytonwallet.app_air.walletcontext.models.MWalletSettingsViewMode

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

    fun init(globalStorageProvider: IGlobalStorageProvider) {
        WGlobalStorage.globalStorageProvider = globalStorageProvider
        _isSensitiveDataProtectionOn =
            WGlobalStorage.globalStorageProvider.getBool(IS_SENSITIVE_DATA_HIDDEN) == true
        migrate()
        removeTemporaryAccounts()
    }

    @Volatile
    var temporaryAddedAccountIds: MutableList<String> = mutableListOf()
        private set

    private fun removeTemporaryAccounts() {
        temporaryAddedAccountIds =
            accountIds().filter { globalStorageProvider.getBool("accounts.byId.$it.isTemporary") == true }
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
        clearUiCacheData()
    }

    fun clearUiCacheData() {
        cachedLangCode = null
    }

    fun incDoNotSynchronize() {
        globalStorageProvider.doNotSynchronize += 1
        //Logger.d("---", "doNotSynchronize: ${globalStorageProvider.doNotSynchronize}")
    }

    fun decDoNotSynchronize() {
        globalStorageProvider.doNotSynchronize -= 1
        //Logger.d("---", "doNotSynchronize: ${globalStorageProvider.doNotSynchronize}")
    }

    private const val CURRENT_ACCOUNT_ID = "currentAccountId"
    private const val CURRENT_TEMPORARY_VIEW_ACCOUNT_ID = "currentTemporaryViewAccountId"
    private const val ACTIVE_THEME = "settings.theme"
    private const val ACTIVE_FONT = "settings.font"
    private const val ARE_ROUNDED_TOOLBARS_ACTIVE = "settings.roundedToolbars"
    private const val IS_TESTNET = "settings.isTestnet"
    private const val ARE_ANIMATIONS_ACTIVE = "settings.animationLevel"
    private const val ARE_SIDE_GUTTERS_ACTIVE = "settings.sideGutters"
    private const val ARE_ROUNDED_CORNERS_ACTIVE = "settings.roundedCorners"
    private const val IS_BLUR_ENABLED = "settings.blurEnabled"
    private const val ARE_SOUNDS_ACTIVE = "settings.canPlaySounds"
    private const val HIDE_TINY_TRANSFERS = "settings.areTinyTransfersHidden"
    private const val HIDE_NO_COST_TOKENS = "settings.areTokensWithNoCostHidden"
    private const val BASE_CURRENCY = "settings.baseCurrency"
    private const val ASSETS_AND_ACTIVITY = "settings.byAccountId"
    private const val BIOMETRIC_KIND = "settings.authConfig.kind"
    private const val LANG_CODE = "settings.langCode"
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

    fun save(accountId: String, accountName: String?, persist: Boolean = true) {
        // Save null names as empty string in the cache to return it without accessing storage
        cachedAccountNames[accountId] = accountName ?: ""
        globalStorageProvider.set(
            "accounts.byId.$accountId.title",
            accountName,
            if (persist) IGlobalStorageProvider.PERSIST_INSTANT else IGlobalStorageProvider.PERSIST_NO
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

    fun accountExists(accountId: String): Boolean {
        return globalStorageProvider.getDict("accounts.byId.$accountId") != null
    }

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

    fun getAccount(accountId: String): JSONObject? {
        return globalStorageProvider.getDict("accounts.byId.$accountId")
    }

    fun saveAccount(accountId: String, jsonObject: JSONObject?) {
        return globalStorageProvider.set(
            "accounts.byId.$accountId",
            jsonObject,
            IGlobalStorageProvider.PERSIST_INSTANT
        )
    }

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
        isTemporary: Boolean = false,
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
        if (importedAt != null)
            globalStorageProvider.set(
                "accounts.byId.$accountId.importedAt",
                value = importedAt,
                persistInstantly = IGlobalStorageProvider.PERSIST_NO
            )
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
            if (globalStorageProvider.getString("accounts.byId.$accountId.type") == "mnemonic")
                return true
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
                "settings.byAccountId.$accountId",
            ), persistInstantly = IGlobalStorageProvider.PERSIST_INSTANT
        )
        cachedAccountIds = null
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
            ), persistInstantly = IGlobalStorageProvider.PERSIST_INSTANT
        )
    }

    // Active account id is the permanent default account id (not pushed temporary screens)
    fun getActiveAccountId(): String? {
        return globalStorageProvider.getString(CURRENT_ACCOUNT_ID)
    }

    fun setActiveAccountId(id: String?, persistInstantly: Boolean) {
        setIsTestnet(
            id?.let { MBlockchainNetwork.ofAccountId(id) != MBlockchainNetwork.MAINNET } ?: false
        )
        globalStorageProvider.set(
            CURRENT_ACCOUNT_ID,
            id,
            if (persistInstantly) IGlobalStorageProvider.PERSIST_INSTANT else IGlobalStorageProvider.PERSIST_NORMAL
        )
    }

    fun setTemporaryAccountId(id: String?, persistInstantly: Boolean) {
        globalStorageProvider.set(
            CURRENT_TEMPORARY_VIEW_ACCOUNT_ID,
            id,
            if (persistInstantly) IGlobalStorageProvider.PERSIST_INSTANT else IGlobalStorageProvider.PERSIST_NORMAL
        )
    }

    fun getAssetsAndActivityData(accountId: String): JSONObject? {
        return globalStorageProvider.getDict("$ASSETS_AND_ACTIVITY.$accountId")
    }

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
    }

    fun setIsBiometricActivated(isBiometricActivated: Boolean) {
        globalStorageProvider.set(
            BIOMETRIC_KIND,
            if (isBiometricActivated) "native-biometrics" else "password",
            IGlobalStorageProvider.PERSIST_INSTANT
        )
    }

    fun isBiometricActivated(): Boolean {
        return globalStorageProvider.getString(BIOMETRIC_KIND) == "native-biometrics"
    }

    fun getActiveTheme(): String {
        return globalStorageProvider.getString(ACTIVE_THEME) ?: ThemeManager.THEME_SYSTEM
    }

    fun setActiveTheme(theme: String) {
        globalStorageProvider.set(ACTIVE_THEME, theme, IGlobalStorageProvider.PERSIST_INSTANT)
    }

    fun getActiveFont(): String {
        return globalStorageProvider.getString(ACTIVE_FONT) ?: "misans"
    }

    fun setActiveFont(font: String) {
        globalStorageProvider.set(ACTIVE_FONT, font, IGlobalStorageProvider.PERSIST_INSTANT)
    }

    fun setAreRoundedToolbarsActive(active: Boolean) {
        globalStorageProvider.set(
            ARE_ROUNDED_TOOLBARS_ACTIVE,
            active,
            IGlobalStorageProvider.PERSIST_INSTANT
        )
    }

    fun getAreRoundedToolbarsActive(): Boolean {
        return globalStorageProvider.getBool(ARE_ROUNDED_TOOLBARS_ACTIVE) ?: true
    }

    private fun setIsTestnet(isTestnet: Boolean) {
        globalStorageProvider.set(
            IS_TESTNET,
            isTestnet,
            IGlobalStorageProvider.PERSIST_NO
        )
    }

    fun getAreAnimationsActive(): Boolean {
        return (globalStorageProvider.getInt(ARE_ANIMATIONS_ACTIVE) ?: 2) > 0
    }

    fun setAreAnimationsActive(active: Boolean) {
        globalStorageProvider.set(
            ARE_ANIMATIONS_ACTIVE,
            if (active) 2 else 0,
            IGlobalStorageProvider.PERSIST_INSTANT
        )
    }

    fun getAreSideGuttersActive(): Boolean {
        return globalStorageProvider.getBool(ARE_SIDE_GUTTERS_ACTIVE)
            ?: !ApplicationContextHolder.isSmallScreen
    }

    fun setAreSideGuttersActive(active: Boolean) {
        globalStorageProvider.set(
            ARE_SIDE_GUTTERS_ACTIVE,
            active,
            IGlobalStorageProvider.PERSIST_INSTANT
        )
    }

    fun getAreRoundedCornersActive(): Boolean {
        return globalStorageProvider.getBool(ARE_ROUNDED_CORNERS_ACTIVE) ?: true
    }

    fun setAreRoundedCornersActive(active: Boolean) {
        globalStorageProvider.set(
            ARE_ROUNDED_CORNERS_ACTIVE,
            active,
            IGlobalStorageProvider.PERSIST_INSTANT
        )
    }

    fun isBlurEnabled(): Boolean {
        return globalStorageProvider.getBool(IS_BLUR_ENABLED) ?: true
    }

    fun setBlurEnabled(enabled: Boolean) {
        globalStorageProvider.set(
            IS_BLUR_ENABLED,
            enabled,
            IGlobalStorageProvider.PERSIST_INSTANT
        )
    }

    fun getAreSoundsActive(): Boolean {
        return globalStorageProvider.getBool(ARE_SOUNDS_ACTIVE) ?: true
    }

    fun setAreSoundsActive(active: Boolean) {
        globalStorageProvider.set(ARE_SOUNDS_ACTIVE, active, IGlobalStorageProvider.PERSIST_INSTANT)
    }

    fun getAreTinyTransfersHidden(): Boolean {
        return globalStorageProvider.getBool(HIDE_TINY_TRANSFERS) != false
    }

    fun setAreTinyTransfersHidden(hidden: Boolean) {
        globalStorageProvider.set(
            HIDE_TINY_TRANSFERS,
            hidden,
            IGlobalStorageProvider.PERSIST_INSTANT
        )
    }

    fun getAreNoCostTokensHidden(): Boolean {
        return globalStorageProvider.getBool(HIDE_NO_COST_TOKENS) != false
    }

    fun setAreNoCostTokensHidden(hidden: Boolean) {
        globalStorageProvider.set(
            HIDE_NO_COST_TOKENS,
            hidden,
            IGlobalStorageProvider.PERSIST_INSTANT
        )
    }

    fun getBaseCurrency(): String {
        return globalStorageProvider.getString(BASE_CURRENCY) ?: "USD"
    }

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

    private fun cachedActivitiesKey(accountId: String, slug: String?): String {
        return if (slug == null) {
            "byAccountId.$accountId.activities.idsMain"
        } else {
            "byAccountId.$accountId.activities.idsBySlug.$slug"
        }
    }

    fun hasCachedActivities(accountId: String, slug: String?): Boolean {
        return globalStorageProvider.contains(cachedActivitiesKey(accountId, slug))
    }

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

    fun getActivitiesDict(accountId: String): JSONObject? {
        return globalStorageProvider.getDict("byAccountId.$accountId.activities.byId")
    }

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
            globalStorageProvider.getDict("byAccountId.$accountId.activities.newestActivitiesBySlug")
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

    fun getBalancesDict(accountId: String): JSONObject? {
        return globalStorageProvider.getDict("byAccountId.$accountId.balances.bySlug")
    }

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

    fun currentTokenPeriod(accountId: String): String {
        return globalStorageProvider.getString("byAccountId.$accountId.currentTokenPeriod") ?: "1D"
    }

    fun setCurrentTokenPeriod(accountId: String, period: String) {
        globalStorageProvider.set(
            "byAccountId.$accountId.currentTokenPeriod",
            value = period,
            IGlobalStorageProvider.PERSIST_NORMAL
        )
    }

    fun getCardBackgroundNft(accountId: String): JSONObject? {
        return globalStorageProvider.getDict("settings.byAccountId.$accountId.cardBackgroundNft")
    }

    fun getCardBackgroundNftAddress(accountId: String): String? {
        return globalStorageProvider.getString("settings.byAccountId.$accountId.cardBackgroundNft.address")
    }

    fun setCardBackgroundNft(accountId: String, nft: JSONObject?) {
        return globalStorageProvider.set(
            "settings.byAccountId.$accountId.cardBackgroundNft",
            nft,
            IGlobalStorageProvider.PERSIST_INSTANT
        )
    }

    fun getAccentColorNft(accountId: String): JSONObject? {
        return globalStorageProvider.getDict("settings.byAccountId.$accountId.accentColorNft")
    }

    fun getNftAccentColorIndex(accountId: String): Int? {
        return globalStorageProvider.getInt("settings.byAccountId.$accountId.accentColorIndex")
    }

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
            key = "${PRICE_HISTORY}.${tokenSlug}.${period}",
            value = if (data != null) JSONArray().apply {
                data.forEach { innerArray ->
                    put(JSONArray(innerArray))
                }
            } else null,
            persistInstantly = IGlobalStorageProvider.PERSIST_NORMAL
        )
    }

    fun getPriceHistory(tokenSlug: String, period: String): Array<Array<Double>>? {
        val jsonArray = globalStorageProvider.getArray(
            "${PRICE_HISTORY}.${tokenSlug}.${period}"
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
        if (timeValue != MAutoLockOption.NEVER)
            globalStorageProvider.set(
                IS_APP_LOCK_ENABLED,
                true,
                IGlobalStorageProvider.PERSIST_NO
            )
        globalStorageProvider.set(
            AUTO_LOCK_VALUE,
            timeValue.value,
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
        WalletContextManager.delegate?.protectedModeChanged()
    }

    fun getIsSensitiveDataProtectionOn(): Boolean {
        return _isSensitiveDataProtectionOn
    }

    fun setPushNotificationsToken(userToken: String) {
        return globalStorageProvider.set(
            mapOf(
                PUSH_NOTIFICATIONS_TOKEN to userToken,
                "pushNotifications.platform" to "android"
            ),
            IGlobalStorageProvider.PERSIST_INSTANT
        )
    }

    fun setPushNotificationAccounts(enabledAccounts: List<String>) {
        return globalStorageProvider.set(
            PUSH_NOTIFICATIONS_ENABLED_ACCOUNTS,
            JSONArray(enabledAccounts),
            IGlobalStorageProvider.PERSIST_INSTANT
        )
    }

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

    fun getPushNotificationsToken(): String? {
        return globalStorageProvider.getString(PUSH_NOTIFICATIONS_TOKEN)
    }

    fun getPushNotificationsEnabledAccounts(): List<String>? {
        val arr = globalStorageProvider.getArray(PUSH_NOTIFICATIONS_ENABLED_ACCOUNTS)
            ?: return null
        return ArrayList(List(arr.length()) { i ->
            arr.getString(i)
        })
    }

    fun getBlacklistedNftAddresses(accountId: String): ArrayList<String> {
        val arr = globalStorageProvider.getArray("byAccountId.$accountId.blacklistedNftAddresses")
            ?: return ArrayList()
        return ArrayList(List(arr.length()) { i ->
            arr.getString(i)
        })
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
        return ArrayList(List(arr.length()) { i ->
            arr.getString(i)
        })
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
                    put(JSONObject().apply {
                        put("address", tab.address)
                        put("chain", tab.chain)
                    })
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
                val obj = arr.getJSONObject(i)
                add(MCollectionTab(obj.getString("chain"), obj.getString("address")))
            }
        }
    }

    fun setWasTelegramGiftsAutoAdded(accountId: String, value: Boolean) {
        globalStorageProvider.set(
            "byAccountId.$accountId.nfts.wasTelegramGiftsAutoAdded",
            value,
            IGlobalStorageProvider.PERSIST_NORMAL
        )
    }

    fun getWasTelegramGiftsAutoAdded(accountId: String): Boolean {
        return globalStorageProvider.getBool("byAccountId.$accountId.nfts.wasTelegramGiftsAutoAdded") == true
    }

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

    fun getAccountAddresses(accountId: String): JSONArray? {
        return globalStorageProvider.getArray("byAccountId.$accountId.savedAddresses")
    }

    fun setLangCode(langCode: String) {
        globalStorageProvider.set(
            LANG_CODE,
            langCode,
            IGlobalStorageProvider.PERSIST_INSTANT
        )
    }

    fun getLangCode(): String {
        val resolved = globalStorageProvider.getString(LANG_CODE)
            ?: cachedLangCode
            ?: resolveSystemLanguageCode()
            ?: WLanguage.ENGLISH.langCode
        cachedLangCode = resolved
        return resolved
    }

    private fun resolveSystemLanguageCode(): String? {
        val context = try {
            ApplicationContextHolder.applicationContext
        } catch (_: Throwable) {
            return null
        }
        return LocaleController.resolveSystemLanguageCode(context)
    }

    fun getCardsInfo(accountId: String): JSONObject? {
        return globalStorageProvider.getDict("byAccountId.$accountId.config.cardsInfo")
    }

    fun isCardMinting(accountId: String): Boolean {
        return globalStorageProvider.getBool("byAccountId.$accountId.isCardMinting") == true
    }

    fun isMultichain(accountId: String): Boolean {
        return globalStorageProvider.keysIn("accounts.byId.$accountId.byChain").size > 1
    }

    fun setCurrencyRates(rates: Map<String, Double>) {
        return globalStorageProvider.set(
            "currencyRates",
            JSONObject(rates),
            IGlobalStorageProvider.PERSIST_NORMAL
        )
    }

    fun getCurrencyRates(): JSONObject? {
        return globalStorageProvider.getDict("currencyRates")
    }

    fun setAccountSelectorViewMode(mode: MWalletSettingsViewMode) {
        return globalStorageProvider.set(
            "accountSelectorViewMode",
            mode.value,
            IGlobalStorageProvider.PERSIST_NORMAL
        )
    }

    fun getAccountSelectorViewMode(): MWalletSettingsViewMode? {
        return MWalletSettingsViewMode.fromValue(globalStorageProvider.getString("accountSelectorViewMode"))
    }

    fun getPreferredExplorer(chain: String): String? {
        return globalStorageProvider.getString("$EXPLORER.$chain")
    }

    fun setPreferredExplorer(chain: String, explorerIdentifier: String) {
        globalStorageProvider.set(
            "$EXPLORER.$chain",
            explorerIdentifier,
            IGlobalStorageProvider.PERSIST_NORMAL
        )
    }

    fun getIsSeasonalThemingDisabled(): Boolean {
        return globalStorageProvider.getBool(IS_SEASONAL_THEMING_DISABLED) == true
    }

    fun setIsSeasonalThemingDisabled(disabled: Boolean) {
        globalStorageProvider.set(
            IS_SEASONAL_THEMING_DISABLED,
            disabled,
            IGlobalStorageProvider.PERSIST_INSTANT
        )
    }

    private const val LAST_STATE: Int = 53

    fun migrate() {
        // Lock the storage
        incDoNotSynchronize()
        val currentState = globalStorageProvider.getInt(STATE_VERSION) ?: run {
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

        if (currentState < 32)
            throw Exception() // Not supported!

        if (currentState < 36) {
            clearActivities()
        }

        if (currentState < 37) {
            accountIds().forEach { accountId ->
                val account = getAccount(accountId)
                val updatedType =
                    if (account?.getBoolean("isHardware") == true ||
                        account?.getString("type") == "hardware"
                    )
                        "hardware" else "mnemonic"
                account?.put("type", updatedType)
                account?.remove("isHardware")
                saveAccount(accountId, account)
            }
        }

        if (currentState <= 37) {
            fun migrateObject(tokenObj: JSONObject) {
                if (!tokenObj.has("price"))
                    tokenObj.put("price", 0)
                if (!tokenObj.has("percentChange24h"))
                    tokenObj.put("percentChange24h", 0)
                if (!tokenObj.has("priceUsd"))
                    tokenObj.put("priceUsd", 0)
                if (tokenObj.has("quote"))
                    tokenObj.remove("quote")
            }
            // Update Cache
            WCacheStorage.getTokens()?.let { tokensString ->
                val tokensJsonArray = JSONArray(tokensString)
                for (i in 0..<tokensJsonArray.length()) {
                    migrateObject(tokensJsonArray.get(i) as JSONObject)
                }
                WCacheStorage.setTokens(tokensJsonArray.toString())
            }
            // Update Tokens
            val tokensArray = globalStorageProvider.getArray("tokenInfo.bySlug") ?: JSONArray()
            for (i in 0..<tokensArray.length()) {
                migrateObject(tokensArray.get(i) as JSONObject)
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
                    if (account.optJSONObject("byChain") != null)
                        continue // Already migrated
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
                if (account.optString("type") != "hardware")
                    continue
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
                if (globalStorageProvider.getArray("$ASSETS_AND_ACTIVITY.$accountId.pinnedSlugs") == null) {
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
                } catch (_: Throwable) {
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
                        migrated.put(JSONObject().apply {
                            put("address", element)
                            put("chain", "ton")
                        })
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

        // Update and unlock the storage
        globalStorageProvider.set(STATE_VERSION, LAST_STATE, IGlobalStorageProvider.PERSIST_INSTANT)
        decDoNotSynchronize()
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

    fun getSuggestedName(network: MBlockchainNetwork, type: String): String {
        val baseNameKey = when (type) {
            "mnemonic" -> "My Wallet"
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
        val prefix = if (network == MBlockchainNetwork.MAINNET) "" else "Testnet "
        if (accountIds(network = network).isEmpty()) {
            return "$prefix${LocaleController.getString("MyTonWallet")}"
        }
        val count = countAccountsByType(network = network, type = type)
        return "$prefix$baseNameKey ${count + 1}"
    }

    private fun countAccountsByType(network: MBlockchainNetwork, type: String): Int =
        accountIds(network = network).count { accountId -> getAccount(accountId)?.optString("type") == type }
}
