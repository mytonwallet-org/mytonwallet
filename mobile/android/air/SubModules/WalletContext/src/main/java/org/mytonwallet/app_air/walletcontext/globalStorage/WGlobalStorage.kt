package org.mytonwallet.app_air.walletcontext.globalStorage

import org.json.JSONArray
import org.json.JSONObject
import org.mytonwallet.app_air.walletcontext.WalletContextManager
import org.mytonwallet.app_air.walletcontext.cacheStorage.WCacheStorage
import org.mytonwallet.app_air.walletcontext.helpers.LocaleController
import org.mytonwallet.app_air.walletcontext.models.MAutoLockOption
import org.mytonwallet.app_air.walletcontext.theme.ThemeManager
import org.mytonwallet.app_air.walletcontext.theme.ThemeManager.UIMode

object WGlobalStorage {
    val isInitialized: Boolean
        get() {
            return ::globalStorageProvider.isInitialized
        }

    private lateinit var globalStorageProvider: IGlobalStorageProvider
    private val cachedAccountNames = mutableMapOf<String, String>()
    private val cachedAccountTonAddresses = mutableMapOf<String, String>()
    private var _isSensitiveDataProtectionOn: Boolean = false

    fun init(globalStorageProvider: IGlobalStorageProvider) {
        WGlobalStorage.globalStorageProvider = globalStorageProvider
        _isSensitiveDataProtectionOn =
            WGlobalStorage.globalStorageProvider.getBool(IS_SENSITIVE_DATA_HIDDEN) == true
        migrate()
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
    private const val ACCENT_COLOR_ID = "settings.themeColor"
    private const val ACTIVE_THEME = "settings.theme"
    private const val ACTIVE_FONT = "settings.font"
    private const val ACTIVE_UI_MODE = "settings.uiMode"
    private const val ARE_ANIMATIONS_ACTIVE = "settings.animationLevel"
    private const val ARE_SIDE_GUTTERS_ACTIVE = "settings.sideGutters"
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

    fun getAccountTonAddress(accountId: String): String? {
        if (cachedAccountTonAddresses[accountId] == null) {
            globalStorageProvider.getString("accounts.byId.$accountId.addressByChain.ton")?.let {
                cachedAccountTonAddresses[accountId] = it
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

    fun accountIds(): Array<String> {
        return globalStorageProvider.keysIn("byAccountId")
    }

    fun addAccount(
        accountId: String,
        accountType: String,
        address: String?,
        tronAddress: String?,
        ledgerWallet: JSONObject? = null,
        name: String? = null,
        importedAt: Long?,
    ) {
        val accountIds = accountIds()
        val suggestedName =
            name
                ?: (if (accountIds.isEmpty()) LocaleController.getString("My Wallet") else "${
                    LocaleController.getString(
                        "My Wallet"
                    )
                } ${accountIds.size}")
        save(accountId = accountId, accountName = suggestedName, persist = false)
        if (address != null)
            globalStorageProvider.set(
                "accounts.byId.$accountId.addressByChain.ton",
                address,
                IGlobalStorageProvider.PERSIST_NO
            )
        if (!tronAddress.isNullOrEmpty())
            globalStorageProvider.set(
                "accounts.byId.$accountId.addressByChain.tron",
                tronAddress,
                IGlobalStorageProvider.PERSIST_NO
            )
        globalStorageProvider.set(
            "accounts.byId.$accountId.type",
            accountType,
            IGlobalStorageProvider.PERSIST_NO
        )
        ledgerWallet?.let {
            globalStorageProvider.set(
                "accounts.byId.$accountId.ledger",
                ledgerWallet,
                IGlobalStorageProvider.PERSIST_NO
            )
        }
        if (importedAt != null)
            globalStorageProvider.set(
                "accounts.byId.$accountId.importedAt",
                value = importedAt,
                persistInstantly = IGlobalStorageProvider.PERSIST_NO
            )
        globalStorageProvider.set(
            "byAccountId.$accountId.isBackupRequired",
            value = false,
            persistInstantly = IGlobalStorageProvider.PERSIST_INSTANT
        )
    }

    fun isPasscodeSet(): Boolean {
        for (accountId in accountIds()) {
            if (globalStorageProvider.getString("accounts.byId.$accountId.type") == "mnemonic")
                return true
        }
        return false
    }

    fun removeAccount(accountId: String) {
        globalStorageProvider.remove(
            keys = arrayOf(
                "accounts.byId.$accountId",
                "byAccountId.$accountId",
                "settings.byAccountId.$accountId",
            ), persistInstantly = IGlobalStorageProvider.PERSIST_INSTANT
        )
    }

    fun deleteAllWallets() {
        globalStorageProvider.remove(
            keys = arrayOf(
                "accounts.byId",
                "byAccountId",
                "settings.byAccountId"
            ), persistInstantly = IGlobalStorageProvider.PERSIST_INSTANT
        )
        setActiveAccountId(null)
    }

    fun getActiveAccountId(): String? {
        return globalStorageProvider.getString(CURRENT_ACCOUNT_ID)
    }

    fun setActiveAccountId(id: String?) {
        globalStorageProvider.set(CURRENT_ACCOUNT_ID, id, IGlobalStorageProvider.PERSIST_INSTANT)
    }

    fun getAssetsAndActivityData(accountId: String): JSONObject? {
        return globalStorageProvider.getDict("$ASSETS_AND_ACTIVITY.$accountId")
    }

    fun setAssetsAndActivityData(accountId: String, value: JSONObject) {
        for (key in arrayOf(
            "alwaysHiddenSlugs",
            "alwaysShownSlugs",
            "deletedSlugs",
            "importedSlugs"
        )) {
            globalStorageProvider.set(
                "$ASSETS_AND_ACTIVITY.$accountId.$key",
                value.getJSONArray(key),
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

    fun getAccentColorId(): Int {
        return globalStorageProvider.getInt(ACCENT_COLOR_ID) ?: 1
    }

    fun setAccentColorId(id: Int) {
        globalStorageProvider.set(ACCENT_COLOR_ID, id, IGlobalStorageProvider.PERSIST_INSTANT)
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

    fun setActiveUiMode(mode: UIMode) {
        globalStorageProvider.set(
            ACTIVE_UI_MODE,
            mode.value,
            IGlobalStorageProvider.PERSIST_INSTANT
        )
    }

    fun getActiveUiMode(): UIMode {
        val uiMode = globalStorageProvider.getString(ACTIVE_UI_MODE)
        return uiMode?.let {
            UIMode.fromValue(uiMode)!!
        } ?: UIMode.BIG_RADIUS
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
        return globalStorageProvider.getBool(ARE_SIDE_GUTTERS_ACTIVE) != false
    }

    fun setAreSideGuttersActive(active: Boolean) {
        globalStorageProvider.set(
            ARE_SIDE_GUTTERS_ACTIVE,
            active,
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

    fun getActivityIds(accountId: String, slug: String?): Array<String>? {
        val key = if (slug == null) {
            "byAccountId.$accountId.activities.idsMain"
        } else {
            "byAccountId.$accountId.activities.idsBySlug.$slug"
        }
        val ids = globalStorageProvider.getArray(key)
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

    fun getNewestActivitiesBySlug(accountId: String): JSONObject? {
        val newestActivitiesBySlug =
            globalStorageProvider.getDict("byAccountId.$accountId.activities.newestActivitiesBySlug")
        val newestActivitiesTimestampBySlug = JSONObject()
        newestActivitiesBySlug?.keys()?.let { keys ->
            for (key in keys) {
                val ts = newestActivitiesBySlug.optJSONObject(key)?.optLong("timestamp")
                newestActivitiesTimestampBySlug.put(key, ts)
            }
        }
        return newestActivitiesTimestampBySlug
    }

    /*fun setNewestActivityBySlug(accountId: String, slug: String, value: JSONObject?) {
        globalStorageProvider.set(
            "byAccountId.$accountId.activities.newestActivitiesBySlug.$slug",
            value,
            IGlobalStorageProvider.PERSIST_NORMAL
        )
    }*/

    fun setNewestActivitiesBySlug(
        accountId: String,
        activities: Map<String, JSONObject?>,
        persistInstantly: Int
    ) {
        globalStorageProvider.set(
            activities.mapKeys { key ->
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

    fun setPushNotificationAccounts(enabledAccounts: JSONObject) {
        return globalStorageProvider.set(
            PUSH_NOTIFICATIONS_ENABLED_ACCOUNTS,
            enabledAccounts,
            IGlobalStorageProvider.PERSIST_INSTANT
        )
    }

    fun setPushNotificationAccount(accountId: String, addressKey: JSONObject) {
        return globalStorageProvider.set(
            "$PUSH_NOTIFICATIONS_ENABLED_ACCOUNTS.$accountId",
            addressKey,
            IGlobalStorageProvider.PERSIST_INSTANT
        )
    }

    fun removePushNotificationAccount(accountId: String) {
        return globalStorageProvider.remove(
            "$PUSH_NOTIFICATIONS_ENABLED_ACCOUNTS.$accountId",
            IGlobalStorageProvider.PERSIST_INSTANT
        )
    }

    fun getPushNotificationsToken(): String? {
        return globalStorageProvider.getString(PUSH_NOTIFICATIONS_TOKEN)
    }

    fun getPushNotificationsEnabledAccounts(): List<String>? {
        return globalStorageProvider.getDict(PUSH_NOTIFICATIONS_ENABLED_ACCOUNTS)?.keys()
            ?.asSequence()?.toList()
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

    fun setHomeNftCollections(accountId: String, collections: List<String>) {
        globalStorageProvider.set(
            "byAccountId.$accountId.nfts.collectionTabs",
            JSONArray(collections),
            IGlobalStorageProvider.PERSIST_INSTANT
        )
    }

    fun getHomeNftCollections(accountId: String): ArrayList<String> {
        val arr = globalStorageProvider.getArray("byAccountId.$accountId.nfts.collectionTabs")
            ?: return ArrayList()
        return ArrayList(List(arr.length()) { i ->
            arr.getString(i)
        })
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

    fun setLangCode(langCode: String) {
        globalStorageProvider.set(
            LANG_CODE,
            langCode,
            IGlobalStorageProvider.PERSIST_INSTANT
        )
    }

    fun getLangCode(): String {
        return globalStorageProvider.getString(LANG_CODE) ?: "en"
    }

    fun getCardsInfo(accountId: String): JSONObject? {
        return globalStorageProvider.getDict("byAccountId.$accountId.config.cardsInfo")
    }

    fun isCardMinting(accountId: String): Boolean {
        return globalStorageProvider.getBool("byAccountId.$accountId.isCardMinting") == true
    }

    private const val LAST_STATE: Int = 44
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

        if (currentState == LAST_STATE) {
            decDoNotSynchronize()
            return
        }

        if (currentState < 32)
            throw Exception() // Not supported!

        if (currentState <= 35) {
            clearActivities()
        }

        if (currentState <= 36) {
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

        if (currentState <= 44) {
            clearActivities()
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
}
