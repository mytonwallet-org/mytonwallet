@file:Suppress("ktlint:standard:filename")

package org.mytonwallet.app_air.walletcore.api

import androidx.fragment.app.FragmentActivity
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import org.json.JSONArray
import org.json.JSONObject
import org.mytonwallet.app_air.native_enclave.DeviceLockedException
import org.mytonwallet.app_air.native_enclave.EnclaveManager
import org.mytonwallet.app_air.native_enclave.auth.AuthType
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.logger.Logger
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletbasecontext.utils.toJSONString
import org.mytonwallet.app_air.walletcontext.WalletContextManager
import org.mytonwallet.app_air.walletcontext.cacheStorage.WCacheStorage
import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage
import org.mytonwallet.app_air.walletcontext.models.MBlockchainNetwork
import org.mytonwallet.app_air.walletcontext.sdkStorage.WSdkStorage
import org.mytonwallet.app_air.walletcontext.secureStorage.WSecureStorage
import org.mytonwallet.app_air.walletcore.POPULAR_WALLET_VERSIONS
import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.WalletEvent
import org.mytonwallet.app_air.walletcore.helpers.LegacyMigration
import org.mytonwallet.app_air.walletcore.helpers.PoisoningCacheHelper
import org.mytonwallet.app_air.walletcore.models.MAccount
import org.mytonwallet.app_air.walletcore.models.MBridgeError
import org.mytonwallet.app_air.walletcore.pushNotifications.AirPushNotifications
import org.mytonwallet.app_air.walletcore.stores.AccountStore
import org.mytonwallet.app_air.walletcore.stores.ActivityStore

fun WalletCore.importWallet(
    network: MBlockchainNetwork,
    words: Array<String>,
    isNew: Boolean,
    callback: (List<MAccount>?, MBridgeError?) -> Unit
) {
    val quotedNetwork = JSONArray().apply {
        put(network.value)
    }.toString()

    bridge?.callApi(
        "importMnemonic",
        "[$quotedNetwork, ${words.toJSONString}]"
    ) { result, error ->
        if (error != null || result == null) {
            // A missing result with no error reaches the caller as "nothing happened", and the import
            // screen has no way to tell that apart from a success it should react to
            callback(
                null,
                error ?: MBridgeError.Type.UNKNOWN.withCustomMessage(
                    LocaleController.getString("Unexpected error. Please let the support know.")
                )
            )
        } else {
            val resultArray = JSONArray(result)
            if (resultArray.length() == 0) {
                callback(
                    null,
                    MBridgeError.Type.UNKNOWN.withCustomMessage(
                        LocaleController.getString("Unexpected error. Please let the support know.")
                    )
                )
                return@callApi
            }
            val importedAt = if (isNew) null else System.currentTimeMillis()
            val accounts = (0 until resultArray.length()).map { i ->
                val account = resultArray.getJSONObject(i)
                MAccount(
                    account.optString("accountId", ""),
                    MAccount.parseByChain(account.optJSONObject("byChain")),
                    name = "",
                    accountType = MAccount.AccountType.MNEMONIC,
                    importedAt = importedAt,
                    isTemporary = false
                )
            }
            callback(accounts, null)
        }
    }
}

fun WalletCore.importPrivateKey(
    network: MBlockchainNetwork,
    privateKey: String,
    callback: (MAccount?, MBridgeError?) -> Unit
) {
    val quotedChain = JSONObject.quote("ton")
    val quotedNetworks = JSONArray().apply { put(network.value) }.toString()
    val quotedPrivateKey = JSONObject.quote(privateKey)

    bridge?.callApi(
        "importPrivateKey",
        "[$quotedChain, $quotedNetworks, $quotedPrivateKey]"
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
                ),
                null
            )
        }
    }
}

fun WalletCore.importNewWalletVersion(
    prevAccount: MAccount,
    version: String,
    callback: (MAccount?, MBridgeError?) -> Unit
) {
    importNewWalletVersionInternal(
        prevAccount = prevAccount,
        version = version,
        allowRetry = true,
        callback = callback
    )
}

private fun WalletCore.importNewWalletVersionInternal(
    prevAccount: MAccount,
    version: String,
    allowRetry: Boolean,
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
                val accountJson = WGlobalStorage.getAccount(accountId)
                if (accountJson == null) {
                    if (!allowRetry) {
                        callback(null, MBridgeError.Type.UNKNOWN)
                        return@callApi
                    }
                    removeAccount(
                        accountId = accountId,
                        nextAccountId = null,
                        isNextAccountPushedTemporary = null
                    ) { _, removeErr ->
                        if (removeErr != null) {
                            callback(null, removeErr)
                            return@removeAccount
                        }
                        importNewWalletVersionInternal(
                            prevAccount = prevAccount,
                            version = version,
                            allowRetry = false,
                            callback = callback
                        )
                    }
                    return@callApi
                }
                callback(MAccount(accountId, accountJson), null)
                return@callApi
            }
            val regex = "\\b(${POPULAR_WALLET_VERSIONS.joinToString("|")})\\b".toRegex()
            val prevName = prevAccount.name.replace(regex, "").trim()
            callback(
                MAccount(
                    accountId,
                    MAccount.parseByChain(accountObj.optJSONObject("byChain")),
                    name = "$prevName $version",
                    accountType = prevAccount.accountType,
                    importedAt = System.currentTimeMillis(),
                    isTemporary = false
                ),
                null
            )
        }
    }
}

fun WalletCore.validateMnemonic(words: Array<String>, callback: (Boolean, MBridgeError?) -> Unit) {
    val sanitizedWords = words.map { word ->
        val trimmed = word.trim().lowercase()
        if (trimmed.isEmpty() || !trimmed.matches(Regex("^[a-z]+$")) || trimmed.length > 20) {
            callback(false, MBridgeError.Type.INVALID_MNEMONIC)
            return
        }
        trimmed
    }.toTypedArray()

    bridge?.callApi(
        "validateMnemonic",
        "[${sanitizedWords.toJSONString}]"
    ) { result, error ->
        if (error != null || result != "true") {
            callback(false, error ?: MBridgeError.Type.INVALID_MNEMONIC)
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
    if (willPopTemporaryPushedWallets) AccountStore.isPushedTemporary = false
    if (nextAccountId == accountId && !force) return
    val prevNextAccountId = nextAccountId
    nextAccountId = accountId
    nextAccountIsPushedTemporary = isPushedTemporary

    fun failBridgeInterruption(reason: String) {
        val isCurrentActivation = nextAccountId == accountId
        Logger.e(
            Logger.LogTag.ACCOUNT,
            "activateAccount: bridge interrupted reason=$reason " +
                "isCurrentActivation=$isCurrentActivation bridgeReady=$isBridgeReady"
        )
        if (!isCurrentActivation) return
        nextAccountId = null
        nextAccountIsPushedTemporary = null
        callback(null, MBridgeError.Type.BRIDGE_INTERRUPTED)
    }

    fun fetch() {
        fetchAccount(accountId) { account, err ->
            if (nextAccountId != accountId) return@fetchAccount
            if (account == null || err != null) {
                nextAccountId = null
                nextAccountIsPushedTemporary = null
                callback(null, err)
            } else {
                AccountStore.isPushedTemporary = isPushedTemporary
                notifyAccountChanged(account, fromHome)
                callback(account, null)
                scope.launch {
                    WCacheStorage.setInitialScreen(
                        if (WGlobalStorage.isPasscodeSet()) {
                            WCacheStorage.InitialScreen.LOCK
                        } else {
                            WCacheStorage.InitialScreen.HOME
                        }
                    )
                }
            }
        }
    }

    val prevAccentColor = WColor.Tint.color
    updateAccentColor(accountId = accountId)
    if (WColor.Tint.color != prevAccentColor) {
        WalletContextManager.delegate?.get()?.themeChanged(animated = false)
    }
    if (force ||
        (
            AccountStore.activeAccountId != null &&
                (prevNextAccountId ?: AccountStore.activeAccountId) != accountId
            )
    ) {
        WalletCore.notifyEvent(WalletEvent.AccountWillChange(fromHome))
    }
    if (notifySDK) {
        scope.launch {
            val newestActivitiesTimestampBySlug =
                ActivityStore.getNewestActivityTimestamps(accountId) ?: JSONObject()
            withContext(Dispatchers.Main) {
                val activeBridge = bridge
                if (activeBridge == null || !isBridgeReady) {
                    failBridgeInterruption("bridge-unavailable-before-call")
                    return@withContext
                }
                activeBridge.callApi(
                    "activateAccount",
                    "[${JSONObject.quote(accountId)}, $newestActivitiesTimestampBySlug]"
                ) { result, error ->
                    if (error?.type == MBridgeError.Type.BRIDGE_INTERRUPTED) {
                        failBridgeInterruption("pending-call-interrupted")
                    } else if (error != null || result == null) {
                        if (nextAccountId != accountId) return@callApi
                        nextAccountId = null
                        nextAccountIsPushedTemporary = null
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

fun WalletCore.fetchAccount(accountId: String, callback: (MAccount?, MBridgeError?) -> Unit) {
    if (accountId != AccountStore.activeAccount?.accountId) AccountStore.activeAccount = null
    try {
        val globalAccountData = WGlobalStorage.getAccount(accountId) ?: throw Exception()
        val account = MAccount(
            accountId = accountId,
            globalJSON = globalAccountData
        )

        AccountStore.activeAccount = account
        callback(account, null)
    } catch (e: Exception) {
        callback(
            null,
            MBridgeError.Type.UNKNOWN.withCustomMessage(
                LocaleController.getString("Unexpected error. Please let the support know.")
            )
        )
    }
}

fun WalletCore.resetAccounts(callback: (Boolean?, MBridgeError?) -> Unit) {
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
            WSdkStorage.clearStorage()
            WalletCore.enclaveReset()
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
        nextAccountId?.let {
            ActivityStore.getNewestActivityTimestamps(nextAccountId) ?: JSONObject()
        }

    bridge?.callApi(
        "removeAccount",
        nextAccountId?.let {
            "[$quotedAccountId, $quotedNextAccountId, $newestActivitiesTimestampBySlug]"
        }
            ?: "[$quotedAccountId]"
    ) { result, error ->
        if (error != null || result == null) {
            callback(null, error)
        } else {
            nextAccountId?.let {
                if (WalletCore.nextAccountId != nextAccountId) return@let
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
                    }
                )
            } ?: run {
                callback(true, null)
            }
        }
    }
}

/**
 * Authorizes with an Enclave auth method and returns a session token. Called by AuthStore for
 * passcode or biometric unlocks and for sessions required by protected actions.
 */
fun WalletCore.enclaveAuthorize(
    activity: FragmentActivity,
    authType: AuthType,
    isLong: Boolean,
    passcode: String?,
    usageCount: Int = 1,
    callback: (token: String?, MBridgeError?) -> Unit
) {
    EnclaveManager.sharedInstance.authorize(
        authType,
        isLong,
        usageCount,
        passcode,
        activity,
        object : EnclaveManager.SessionCallback {
            override fun onSuccess(token: String?, validUntil: Long) {
                callback(token, null)
            }

            override fun onError(error: String?) {
                callback(null, enclaveError(error))
            }
        }
    )
}

/**
 * Initializes passcode authentication for the first mnemonic wallet. If a previous first-wallet
 * setup was interrupted before account persistence, its orphaned Enclave state is replaced.
 */
fun WalletCore.enclaveSetupAuth(
    activity: FragmentActivity,
    authType: AuthType,
    passcode: String?,
    callback: (token: String?, MBridgeError?) -> Unit
) {
    if (authType != AuthType.PASSCODE) throw Exception("authType not allowed")

    val manager = EnclaveManager.sharedInstance
    if (!WGlobalStorage.isPasscodeSet() && manager.isPasscodeAuthConfigured) {
        Logger.i(Logger.LogTag.ENCLAVE, "Replacing interrupted initial passcode setup")
        manager.reset()
    }

    manager.setupAuth(
        authType,
        passcode,
        activity,
        object : EnclaveManager.SessionCallback {
            override fun onSuccess(token: String?, validUntil: Long) {
                WGlobalStorage.setAuthTypes(listOf(authType.key))
                callback(token, null)
            }

            override fun onError(error: String?) {
                callback(null, enclaveError(error))
            }
        }
    )
}

/**
 * Adds or replaces an Enclave auth method using an authorized session. Called by security and
 * passcode flows, and by legacy migration when enabling native biometric authentication.
 */
fun WalletCore.enclaveMigrateAuth(
    activity: FragmentActivity,
    currentToken: String,
    newAuthType: AuthType,
    passcode: String?,
    shouldReplace: Boolean,
    usageCount: Int = 1,
    callback: (token: String?, MBridgeError?) -> Unit
) {
    EnclaveManager.sharedInstance.migrateAuth(
        currentToken,
        newAuthType,
        passcode,
        shouldReplace,
        usageCount,
        activity,
        object : EnclaveManager.SessionCallback {
            override fun onSuccess(token: String?, validUntil: Long) {
                val prevAuthType = EnclaveManager.parseAuthTypeFromToken(currentToken)
                if (newAuthType != prevAuthType) {
                    val authTypes = WGlobalStorage.getAuthTypes() ?: emptyArray()
                    val updatedAuthTypes =
                        if (shouldReplace) {
                            authTypes.filter { it != prevAuthType.key }
                        } else {
                            authTypes.toList()
                        } + newAuthType.key
                    // Keeping the previous type means the new one can already be in the list, and the
                    // list is persisted, so a repeated migration would grow it on every run
                    WGlobalStorage.setAuthTypes(updatedAuthTypes.distinct())
                }
                callback(token, null)
            }

            override fun onError(error: String?) {
                callback(null, enclaveError(error))
            }
        }
    )
}

/**
 * Imports a mnemonic into Enclave storage and associates it with all supplied account IDs. Called
 * after wallet creation or import once the SDK has returned the related accounts.
 */
fun WalletCore.enclaveImportSecrets(
    accountIds: List<String>,
    secret: String,
    token: String
): MBridgeError? = try {
    val manager = EnclaveManager.sharedInstance
    val uniqueAccountIds = accountIds.toSet()
    require(accountIds.isNotEmpty() && uniqueAccountIds.size == accountIds.size)
    val primaryAccountId = accountIds.first()
    manager.importSecret(primaryAccountId, secret, token)
    accountIds.drop(1).forEach { accountId ->
        manager.duplicateSecret(primaryAccountId, accountId)
    }
    null
} catch (e: Exception) {
    enclaveError(e)
}

/**
 * Associates an existing mnemonic account's Enclave secret with additional account IDs. Called
 * when creating subwallets, adding derived accounts, or importing wallet versions.
 */
fun WalletCore.enclaveDuplicateSecrets(
    sourceAccount: MAccount,
    targetAccountIds: List<String>
): MBridgeError? {
    if (sourceAccount.accountType != MAccount.AccountType.MNEMONIC ||
        targetAccountIds.isEmpty()
    ) {
        return null
    }

    return try {
        val manager = EnclaveManager.sharedInstance
        val uniqueTargetAccountIds = targetAccountIds.toSet()
        require(
            uniqueTargetAccountIds.size == targetAccountIds.size &&
                sourceAccount.accountId !in uniqueTargetAccountIds
        )
        targetAccountIds.forEach { accountId ->
            manager.duplicateSecret(sourceAccount.accountId, accountId)
        }
        null
    } catch (e: Exception) {
        MBridgeError.Type.UNKNOWN.withCustomMessage(
            LocaleController.getString("Unexpected error. Please let the support know.")
        )
    }
}

/**
 * Migrates legacy passcode authentication and required mnemonic accounts into Enclave storage.
 * Called by AuthStore during passcode unlock and by the legacy biometric-first migration flow.
 */
fun WalletCore.enclaveMigrateFromLegacy(
    activity: FragmentActivity,
    password: String,
    usageCount: Int = 1,
    callback: (token: String?, error: MBridgeError?) -> Unit
) {
    val requiredAccountIds = LegacyMigration.requiredLegacyAccountIds()
    val storedAccounts = fetchNativeLegacyAccounts()
    Logger.i(
        Logger.LogTag.ENCLAVE,
        "Legacy migration: preparing requiredAccounts=${requiredAccountIds.size} " +
            "storedAccounts=${storedAccounts.size} sessionUsages=$usageCount"
    )

    val legacyAccounts = LegacyMigration.selectRequiredAccounts(
        storedAccounts,
        requiredAccountIds
    )
    if (legacyAccounts.isNullOrEmpty()) {
        Logger.e(
            Logger.LogTag.ENCLAVE,
            "Legacy migration: required account data is missing " +
                "requiredAccounts=${requiredAccountIds.size} storedAccounts=${storedAccounts.size}"
        )
        callback(
            null,
            MBridgeError.Type.UNKNOWN.withCustomMessage(
                LocaleController.getString("Unexpected error. Please let the support know.")
            )
        )
        return
    }

    Logger.i(
        Logger.LogTag.ENCLAVE,
        "Legacy migration: migrating secrets accountCount=${legacyAccounts.size}"
    )
    LegacyMigration.migrateToEnclave(
        activity,
        legacyAccounts,
        password,
        usageCount,
        onSuccessCallback = { token ->
            Logger.i(
                Logger.LogTag.ENCLAVE,
                "Legacy migration: secrets migrated; cleanup pending"
            )
            callback(token, null)
        },
        onErrorCallback = { error ->
            val reason = when {
                error == "Invalid password" -> "invalid_passcode_or_legacy_data"
                DeviceLockedException.matches(error) -> "device_locked"
                else -> "enclave_error"
            }
            Logger.e(
                Logger.LogTag.ENCLAVE,
                "Legacy migration: secret migration failed reason=$reason"
            )
            callback(
                null,
                if (error == "Invalid password") null else enclaveError(error)
            )
        }
    )
}

/**
 * Finalizes a committed legacy account migration by recording passcode auth, removing legacy
 * mnemonics, and clearing the pending-cleanup marker. Called after a successful legacy migration
 * and by startup recovery when that marker remains set. An account whose blob did not decrypt keeps
 * its legacy ciphertext so a later recovery attempt stays possible.
 */
fun WalletCore.cleanupLegacyAuthAfterMigration() {
    Logger.i(Logger.LogTag.ENCLAVE, "Legacy migration: cleaning legacy authentication data")
    val authTypes = WGlobalStorage.getAuthTypes()?.toList().orEmpty()
    if (AuthType.PASSCODE.key !in authTypes) {
        WGlobalStorage.setAuthTypes(authTypes + AuthType.PASSCODE.key)
    }
    // Which accounts stayed behind is known only to the migration that ran, and startup recovery
    // runs after that knowledge died with the process. The enclave outlives both, so ask it.
    WSecureStorage.removeLegacyMnemonics { EnclaveManager.sharedInstance.hasSecret(it) }
    EnclaveManager.sharedInstance.completeLegacyCleanup()
    Logger.i(Logger.LogTag.ENCLAVE, "Legacy migration: cleanup completed")
}

/**
 * Resumes any cleanup left incomplete by an interrupted migration. Called by MainWindow during
 * startup after EnclaveManager and global storage are initialized.
 */
fun WalletCore.cleanupPendingLegacyAuth() {
    if (EnclaveManager.sharedInstance.isLegacyCleanupPending) {
        Logger.i(Logger.LogTag.ENCLAVE, "Legacy migration: resuming pending cleanup")
        cleanupLegacyAuthAfterMigration()
    }
    cleanupLegacyBiometricAuthIfMigrated()
}

/**
 * Removes the legacy biometric-wrapped passcode once native biometric auth is configured. Called
 * after successful biometric enrollment and by startup recovery if enrollment completed before
 * legacy cleanup.
 */
fun WalletCore.cleanupLegacyBiometricAuthIfMigrated() {
    if (!WGlobalStorage.isLegacyBiometricActivated() ||
        !EnclaveManager.sharedInstance.isBiometricAuthConfigured
    ) {
        return
    }

    if (!WSecureStorage.deleteLegacyBiometricPasscode()) {
        Logger.e(
            Logger.LogTag.ENCLAVE,
            "Legacy biometric migration: failed to clear legacy credential"
        )
        return
    }

    WGlobalStorage.removeIsLegacyBiometricActivated()
    Logger.i(Logger.LogTag.ENCLAVE, "Legacy biometric migration: cleanup completed")
}

/**
 * Removes an Enclave auth method and updates the persisted auth-method list. Called when disabling
 * biometrics or clearing biometric auth during passcode setup.
 */
fun WalletCore.enclaveRemoveAuth(authType: AuthType) {
    val authTypes = WGlobalStorage.getAuthTypes()
    if (authTypes != null) WGlobalStorage.setAuthTypes(authTypes.filter { it != authType.key })
    EnclaveManager.sharedInstance.removeAuth(authType)
}

/**
 * Clears all Enclave credentials, secrets, and persisted auth-method metadata. Called when
 * resetting every account or removing the final mnemonic account.
 */
fun WalletCore.enclaveReset() {
    WGlobalStorage.setAuthTypes(null)
    EnclaveManager.sharedInstance.reset()
}

private fun fetchNativeLegacyAccounts(): List<Pair<String, String>> {
    val accountsJson = WSecureStorage.getSecValue("accounts")
    if (accountsJson.isEmpty()) return emptyList()

    return try {
        val accounts = JSONObject(accountsJson)
        val result = mutableListOf<Pair<String, String>>()
        for (accountId in accounts.keys()) {
            val account = accounts.optJSONObject(accountId) ?: continue
            val mnemonicEncrypted = account.optString("mnemonicEncrypted", "")
            if (mnemonicEncrypted.isNotEmpty()) {
                result.add(accountId to mnemonicEncrypted)
            }
        }
        result
    } catch (e: Exception) {
        Logger.e(
            Logger.LogTag.ENCLAVE,
            "Legacy migration: failed to parse stored accounts reason=${e.javaClass.simpleName}"
        )
        emptyList()
    }
}

private fun enclaveError(error: String?): MBridgeError = if (DeviceLockedException.matches(error)) {
    MBridgeError.Type.DEVICE_LOCKED
} else {
    // Plain UNKNOWN localizes as a connectivity error - misleading for local enclave failures.
    MBridgeError.Type.UNKNOWN.withCustomMessage(
        LocaleController.getString("Unexpected error. Please let the support know.")
    )
}

private fun enclaveError(error: Throwable): MBridgeError {
    var current: Throwable? = error
    while (current != null) {
        if (current is DeviceLockedException) {
            return MBridgeError.Type.DEVICE_LOCKED
        }
        current = current.cause
    }
    // Plain UNKNOWN localizes as a connectivity error - misleading for local enclave failures.
    return MBridgeError.Type.UNKNOWN.withCustomMessage(
        LocaleController.getString("Unexpected error. Please let the support know.")
    )
}
