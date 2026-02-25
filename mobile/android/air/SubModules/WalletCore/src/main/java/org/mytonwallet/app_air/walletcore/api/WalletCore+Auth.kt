package org.mytonwallet.app_air.walletcore.api

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import org.json.JSONArray
import org.json.JSONObject
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletbasecontext.utils.toJSONString
import org.mytonwallet.app_air.walletcontext.WalletContextManager
import org.mytonwallet.app_air.walletcontext.cacheStorage.WCacheStorage
import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage
import org.mytonwallet.app_air.walletcontext.models.MBlockchainNetwork
import org.mytonwallet.app_air.walletcore.POPULAR_WALLET_VERSIONS
import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.WalletEvent
import org.mytonwallet.app_air.walletcore.helpers.PoisoningCacheHelper
import org.mytonwallet.app_air.walletcore.models.MAccount
import org.mytonwallet.app_air.walletcore.models.MBridgeError
import org.mytonwallet.app_air.walletcore.pushNotifications.AirPushNotifications
import org.mytonwallet.app_air.walletcore.stores.AccountStore
import org.mytonwallet.app_air.walletcore.stores.ActivityStore

fun WalletCore.importWallet(
    network: MBlockchainNetwork,
    words: Array<String>,
    passcode: String,
    isNew: Boolean,
    callback: (MAccount?, MBridgeError?) -> Unit
) {
    // Safely quote network and passcode to prevent injection
    val quotedNetwork = JSONArray().apply {
        put(network.value)
    }.toString()
    val quotedPasscode = JSONObject.quote(passcode)

    bridge?.callApi(
        "importMnemonic",
        "[$quotedNetwork, ${words.toJSONString}, $quotedPasscode]"
    ) { result, error ->
        if (error != null || result == null) {
            callback(null, error)
        } else {
            val account = JSONArray(result).getJSONObject(0)
            callback(
                MAccount(
                    account.optString("accountId", ""),
                    MAccount.parseByChain(account.optJSONObject("byChain")),
                    name = "",
                    accountType = MAccount.AccountType.MNEMONIC,
                    importedAt = if (isNew) null else System.currentTimeMillis(),
                    isTemporary = false
                ), null
            )
        }
    }
}

fun WalletCore.importPrivateKey(
    network: MBlockchainNetwork,
    privateKey: String,
    passcode: String,
    callback: (MAccount?, MBridgeError?) -> Unit
) {
    val quotedChain = JSONObject.quote("ton")
    val quotedNetworks = JSONArray().apply { put(network.value) }.toString()
    val quotedPrivateKey = JSONObject.quote(privateKey)
    val quotedPasscode = JSONObject.quote(passcode)

    bridge?.callApi(
        "importPrivateKey",
        "[$quotedChain, $quotedNetworks, $quotedPrivateKey, $quotedPasscode]"
    ) { result, error ->
        if (error != null || result == null) {
            callback(null, error)
        } else {
            val account = JSONArray(result).getJSONObject(0)
            callback(
                MAccount(
                    account.optString("accountId", ""),
                    MAccount.parseByChain(account.optJSONObject("byChain")),
                    name = "",
                    accountType = MAccount.AccountType.MNEMONIC,
                    importedAt = System.currentTimeMillis(),
                    isTemporary = false
                ), null
            )
        }
    }
}

fun WalletCore.importNewWalletVersion(
    prevAccount: MAccount,
    version: String,
    callback: (MAccount?, MBridgeError?) -> Unit
) {
    val quotedAccountId = JSONObject.quote(prevAccount.accountId)
    val quotedVersion = JSONObject.quote(version)

    bridge?.callApi(
        "importNewWalletVersion",
        "[$quotedAccountId, $quotedVersion]"
    ) { result, error ->
        if (error != null || result == null) {
            callback(null, error)
        } else {
            val accountObj = JSONObject(result)
            val accountId = accountObj.getString("accountId")
            val isNew = accountObj.getBoolean("isNew")
            if (!isNew) {
                callback(MAccount(accountId, WGlobalStorage.getAccount(accountId)!!), null)
                return@callApi
            }
            val regex = "\\b(${POPULAR_WALLET_VERSIONS.joinToString("|")})\\b".toRegex()
            val prevName = prevAccount.name.replace(regex, "").trim()
            callback(
                MAccount(
                    accountId,
                    mapOf(
                        "ton" to MAccount.AccountChain(
                            address = accountObj.getString("address")
                        )
                    ),
                    name = "$prevName $version",
                    accountType = prevAccount.accountType,
                    importedAt = System.currentTimeMillis(),
                    isTemporary = false
                ), null
            )
        }
    }
}

fun WalletCore.validateMnemonic(
    words: Array<String>,
    callback: (Boolean, MBridgeError?) -> Unit
) {
    val sanitizedWords = words.map { word ->
        val trimmed = word.trim().lowercase()
        if (trimmed.isEmpty() || !trimmed.matches(Regex("^[a-z]+$")) || trimmed.length > 20) {
            callback(false, MBridgeError.INVALID_MNEMONIC)
            return
        }
        trimmed
    }.toTypedArray()

    bridge?.callApi(
        "validateMnemonic",
        "[${sanitizedWords.toJSONString}]"
    ) { result, error ->
        if (error != null || result != "true") {
            callback(false, error ?: MBridgeError.INVALID_MNEMONIC)
        } else {
            callback(true, null)
        }
    }
}

fun WalletCore.activateAccount(
    accountId: String,
    notifySDK: Boolean,
    fromHome: Boolean = false,
    isPushedTemporary: Boolean = false,
    willPopTemporaryPushedWallets: Boolean = false,
    force: Boolean = false,
    callback: (MAccount?, MBridgeError?) -> Unit
) {
    if (willPopTemporaryPushedWallets)
        AccountStore.isPushedTemporary = false
    if (nextAccountId == accountId && !force)
        return
    val prevNextAccountId = nextAccountId
    nextAccountId = accountId
    nextAccountIsPushedTemporary = isPushedTemporary

    fun fetch() {
        fetchAccount(accountId) { account, err ->
            if (nextAccountId != accountId)
                return@fetchAccount
            if (account == null || err != null) {
                callback(null, err)
            } else {
                AccountStore.isPushedTemporary = isPushedTemporary
                notifyAccountChanged(account, fromHome)
                callback(account, null)
                scope.launch {
                    WCacheStorage.setInitialScreen(
                        if (WGlobalStorage.isPasscodeSet())
                            WCacheStorage.InitialScreen.LOCK
                        else
                            WCacheStorage.InitialScreen.HOME
                    )
                }
            }
        }
    }

    val prevAccentColor = WColor.Tint.color
    updateAccentColor(accountId = accountId)
    if (WColor.Tint.color != prevAccentColor) {
        WalletContextManager.delegate?.themeChanged(animated = false)
    }
    if (force ||
        (AccountStore.activeAccountId != null &&
            (prevNextAccountId ?: AccountStore.activeAccountId) != accountId)
    ) {
        WalletCore.notifyEvent(WalletEvent.AccountWillChange(fromHome))
    }
    if (notifySDK) {
        scope.launch {
            val newestActivitiesTimestampBySlug =
                ActivityStore.getNewestActivityTimestamps(accountId) ?: JSONObject()
            withContext(Dispatchers.Main) {
                bridge?.callApi(
                    "activateAccount",
                    "[${JSONObject.quote(accountId)}, ${newestActivitiesTimestampBySlug}]"
                ) { result, error ->
                    if (error != null || result == null) {
                        callback(null, error)
                    } else {
                        fetch()
                    }
                }
            }
        }
    } else {
        fetch()
    }
}

fun WalletCore.fetchAccount(
    accountId: String,
    callback: (MAccount?, MBridgeError?) -> Unit
) {
    if (accountId != AccountStore.activeAccount?.accountId)
        AccountStore.activeAccount = null
    try {
        val globalAccountData = WGlobalStorage.getAccount(accountId) ?: throw Exception()
        val account = MAccount(
            accountId = accountId,
            globalJSON = globalAccountData
        )

        AccountStore.activeAccount = account
        callback(account, null)

    } catch (e: Exception) {
        callback(null, MBridgeError.UNKNOWN)
    }
}

fun WalletCore.resetAccounts(
    callback: (Boolean?, MBridgeError?) -> Unit
) {
    val accountIds = WGlobalStorage.accountIds()
    AccountStore.updateActiveAccount(null)
    bridge?.callApi(
        "resetAccounts",
        "[]"
    ) { result, error ->
        if (error != null || result == null) {
            callback(null, error)
        } else {
            AirPushNotifications.unsubscribeAll()
            WalletCore.stores.forEach { it.wipeData() }
            PoisoningCacheHelper.clearCache()
            WCacheStorage.clean(accountIds)
            WCacheStorage.setInitialScreen(WCacheStorage.InitialScreen.INTRO)
            callback(true, null)
        }
    }
}

fun WalletCore.removeAccount(
    accountId: String,
    nextAccountId: String?,
    isNextAccountPushedTemporary: Boolean?,
    callback: (Boolean?, MBridgeError?) -> Unit
) {
    if (nextAccountId != null) {
        AccountStore.updateActiveAccount(null)
        WalletCore.nextAccountId = nextAccountId
    }
    val quotedAccountId = JSONObject.quote(accountId)
    val quotedNextAccountId = nextAccountId?.let { JSONObject.quote(nextAccountId) }
    val newestActivitiesTimestampBySlug =
        nextAccountId?.let { ActivityStore.getNewestActivityTimestamps(nextAccountId) ?: JSONObject() }

    bridge?.callApi(
        "removeAccount",
        nextAccountId?.let { "[$quotedAccountId, $quotedNextAccountId, $newestActivitiesTimestampBySlug]" }
            ?: "[$quotedAccountId]"
    ) { result, error ->
        if (error != null || result == null) {
            callback(null, error)
        } else {
            nextAccountId?.let {
                if (WalletCore.nextAccountId != nextAccountId)
                    return@let
                activateAccount(
                    nextAccountId,
                    false,
                    isPushedTemporary = isNextAccountPushedTemporary ?: false,
                    force = true,
                    callback = { account, error ->
                        if (error != null || account == null) {
                            throw Error()
                        }
                        callback(true, null)
                    })
            } ?: run {
                callback(true, null)
            }
        }
    }
}

fun WalletCore.verifyPassword(
    password: String,
    callback: (Boolean?, MBridgeError?) -> Unit
) {
    val quotedPassword = JSONObject.quote(password)

    bridge?.callApi(
        "verifyPassword",
        "[$quotedPassword]"
    ) { result, error ->
        callback(result == "true", error)
    }
}
