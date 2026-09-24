package org.mytonwallet.app_air.walletcore.stores

import androidx.fragment.app.FragmentActivity
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import org.mytonwallet.app_air.native_enclave.EnclaveManager
import org.mytonwallet.app_air.native_enclave.auth.AuthType
import org.mytonwallet.app_air.walletbasecontext.logger.Logger
import org.mytonwallet.app_air.walletcontext.WalletContextManager
import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage
import org.mytonwallet.app_air.walletcontext.secureStorage.WSecureStorage
import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.api.cleanupLegacyAuthAfterMigration
import org.mytonwallet.app_air.walletcore.api.cleanupLegacyBiometricAuthIfMigrated
import org.mytonwallet.app_air.walletcore.api.enclaveAuthorize
import org.mytonwallet.app_air.walletcore.api.enclaveMigrateAuth
import org.mytonwallet.app_air.walletcore.api.enclaveMigrateFromLegacy
import org.mytonwallet.app_air.walletcore.api.resetAccounts
import org.mytonwallet.app_air.walletcore.helpers.LegacyMigration
import org.mytonwallet.app_air.walletcore.helpers.MultichainAccountUpgradeDetector
import org.mytonwallet.app_air.walletcore.models.MBridgeError
import org.mytonwallet.app_air.walletcore.moshi.api.ApiMethod

class AuthCooldownError(val cooldownDate: Long) : Exception()

object AuthStore : IStore {
    @Volatile
    private var cachedMultichainUpgradeAccountIds: List<String>? = null

    private var failedLoginAttempts: Int
        get() {
            return WSecureStorage.getFailedLoginAttempts() ?: 0
        }
        set(value) {
            WSecureStorage.setFailedLoginAttempts(value)
        }

    private var lastFailedAttempt: Long
        get() {
            return WSecureStorage.getLastFailedAttempt() ?: 0
        }
        set(value) {
            WSecureStorage.setLastFailedAttempt(value)
        }

    private val shouldDelayVerification: Boolean
        get() {
            return failedLoginAttempts >= 5
        }

    fun getCooldownDate(): Long =
        lastFailedAttempt + cooldownForNumberOfFailedAttempts(failedLoginAttempts)

    private var longSessionToken: String? = null
    private var longSessionValidUntil = 0L

    private val isRememberPasscodeEnabled: Boolean
        get() = WGlobalStorage.getIsAutoConfirmEnabled()

    fun getAutoConfirmToken(): String? {
        if (!isRememberPasscodeEnabled) return null
        val token = longSessionToken ?: return null
        if (System.currentTimeMillis() >= longSessionValidUntil) {
            clearLongSession()
            return null
        }
        return token
    }

    fun getAutoConfirmValidUntil(): Long? =
        if (getAutoConfirmToken() != null) longSessionValidUntil else null

    fun clearLongSession() {
        longSessionToken = null
        longSessionValidUntil = 0L
    }

    /**
     * Authorizes via the enclave using passcode.
     * Returns the enclave session token on success, not the passcode itself.
     *
     * If the user is upgrading from the old Capacitor app (has accounts but no authTypes),
     * routes through legacy migration: decrypts old mnemonics with the passcode and
     * re-encrypts them under the new enclave auth system.
     */
    fun authorize(
        activity: FragmentActivity,
        passcode: String,
        extraUsages: Int = 0,
        forceLongSession: Boolean = false,
        callback: (
            success: Boolean,
            enclaveToken: String?,
            cooldownDate: Long?,
            error: MBridgeError?
        ) -> Unit
    ) {
        val now = System.currentTimeMillis()
        val cooldownDate = getCooldownDate()
        val waitFor = cooldownDate - now

        if (waitFor > 0) {
            throw AuthCooldownError(cooldownDate)
        }

        fun performAuth() {
            WalletCore.scope.launch {
                val upgradeAccountIds = pendingMultichainUpgradeAccountIds()
                val usageCount = 1 + extraUsages + upgradeAccountIds.size

                val needsLegacyMigration = LegacyMigration.needsMigration()
                if (needsLegacyMigration) {
                    withContext(Dispatchers.Main) {
                        performLegacyMigration(
                            activity,
                            passcode,
                            usageCount,
                            upgradeAccountIds,
                            callback
                        )
                    }
                } else {
                    val shouldCreateLongSession = isRememberPasscodeEnabled || forceLongSession
                    WalletCore.enclaveAuthorize(
                        activity,
                        AuthType.PASSCODE,
                        shouldCreateLongSession,
                        passcode,
                        usageCount
                    ) { token, validUntil, error ->
                        WalletCore.scope.launch(Dispatchers.Main) {
                            if (token != null) {
                                if (shouldCreateLongSession && validUntil > 0) {
                                    longSessionToken = token
                                    longSessionValidUntil = validUntil
                                }
                                submitSuccessfulLogin()
                                startMultichainUpgradeIfNeeded(token, upgradeAccountIds)
                                callback(true, token, null, null)
                            } else if (error != null) {
                                callback(false, null, null, error)
                            } else {
                                submitFailedLogin()
                                callback(false, null, getCooldownDate(), null)
                            }
                        }
                    }
                }
            }
        }

        if (shouldDelayVerification) {
            android.os.Handler(android.os.Looper.getMainLooper()).postDelayed({
                performAuth()
            }, 1000)
        } else {
            performAuth()
        }
    }

    fun authorizeWithBiometrics(
        activity: FragmentActivity,
        onBridgeReady: () -> Unit,
        onAuthenticated: () -> Unit,
        extraUsages: Int = 0,
        callback: (enclaveToken: String?) -> Unit
    ) {
        if (!WGlobalStorage.isLegacyBiometricActivated()) {
            authorizeWithNativeBiometrics(activity, onAuthenticated, extraUsages, callback)
            return
        }

        WalletCore.doOnBridgeReady {
            WalletCore.scope.launch {
                val upgradeAccountIds = pendingMultichainUpgradeAccountIds()
                val usageCount = 1 + extraUsages + upgradeAccountIds.size

                withContext(Dispatchers.Main) {
                    onBridgeReady()
                    val onAuthorized: (String?) -> Unit = { token ->
                        if (token != null) {
                            startMultichainUpgradeIfNeeded(token, upgradeAccountIds)
                        }
                        callback(token)
                    }

                    if (WGlobalStorage.isLegacyBiometricActivated()) {
                        LegacyMigration.migrateBiometricsToEnclave(
                            activity,
                            usageCount,
                            onAuthorized
                        )
                    } else {
                        WalletCore.enclaveAuthorize(
                            activity,
                            AuthType.BIOMETRIC,
                            false,
                            null,
                            usageCount
                        ) { token, _, _ ->
                            onAuthorized(token)
                        }
                    }
                }
            }
        }
    }

    private fun authorizeWithNativeBiometrics(
        activity: FragmentActivity,
        onAuthenticated: () -> Unit,
        extraUsages: Int,
        callback: (enclaveToken: String?) -> Unit
    ) {
        var upgradeAccountIds: List<String> = emptyList()
        EnclaveManager.sharedInstance.authorizeWithBiometrics(
            activity,
            { createSession ->
                onAuthenticated()
                WalletCore.doOnBridgeReady {
                    WalletCore.scope.launch {
                        upgradeAccountIds = pendingMultichainUpgradeAccountIds()
                        withContext(Dispatchers.Main) {
                            createSession.accept(1 + extraUsages + upgradeAccountIds.size)
                        }
                    }
                }
            },
            object : EnclaveManager.SessionCallback {
                override fun onSuccess(token: String?, validUntil: Long) {
                    if (token != null) {
                        startMultichainUpgradeIfNeeded(token, upgradeAccountIds)
                    }
                    callback(token)
                }

                override fun onError(error: String?) {
                    callback(null)
                }
            }
        )
    }

    private fun performLegacyMigration(
        activity: FragmentActivity,
        passcode: String,
        usageCount: Int,
        upgradeAccountIds: List<String>,
        callback: (
            success: Boolean,
            enclaveToken: String?,
            cooldownDate: Long?,
            error: MBridgeError?
        ) -> Unit
    ) {
        WalletCore.enclaveMigrateFromLegacy(
            activity,
            passcode,
            usageCount
        ) { token, error ->
            if (token == null) {
                if (error != null) {
                    callback(false, null, null, error)
                } else {
                    submitFailedLogin()
                    callback(false, null, getCooldownDate(), null)
                }
                return@enclaveMigrateFromLegacy
            }

            submitSuccessfulLogin()

            WalletCore.cleanupLegacyAuthAfterMigration()

            if (WGlobalStorage.isLegacyBiometricActivated()) {
                Logger.i(
                    Logger.LogTag.ENCLAVE,
                    "Legacy biometric migration: migrating authentication after passcode unlock"
                )
                WalletCore.enclaveMigrateAuth(
                    activity,
                    token,
                    AuthType.BIOMETRIC,
                    null,
                    false,
                    usageCount
                ) { newToken, error ->
                    if (newToken != null) {
                        WalletCore.cleanupLegacyBiometricAuthIfMigrated()
                        Logger.i(
                            Logger.LogTag.ENCLAVE,
                            "Legacy biometric migration: authentication migrated"
                        )
                    } else {
                        Logger.e(
                            Logger.LogTag.ENCLAVE,
                            "Legacy biometric migration: authentication migration failed " +
                                "reason=${error?.type?.name ?: "missing_token"}; " +
                                "continuing with passcode session"
                        )
                    }
                    val authorizedToken = newToken ?: token
                    startMultichainUpgradeIfNeeded(authorizedToken, upgradeAccountIds)
                    callback(true, authorizedToken, null, null)
                }
            } else {
                startMultichainUpgradeIfNeeded(token, upgradeAccountIds)
                callback(true, token, null, null)
            }
        }
    }

    private suspend fun pendingMultichainUpgradeAccountIds(): List<String> {
        cachedMultichainUpgradeAccountIds?.let {
            return it
        }

        val needsSDKPreparation = MultichainAccountUpgradeDetector.needsSDKPreparation()
        if (!needsSDKPreparation) {
            cachedMultichainUpgradeAccountIds = emptyList()
            return emptyList()
        }

        return try {
            WalletCore.call(ApiMethod.Auth.RepairInvalidBip39TonAuthTokens())
            val encryptedAccountIds = MultichainAccountUpgradeDetector.encryptedAccountIds()
            WalletCore.call(ApiMethod.Auth.GetMultichainUpgradeCandidateIds(encryptedAccountIds))
                .toList()
                .also { cachedMultichainUpgradeAccountIds = it }
        } catch (t: Throwable) {
            Logger.e(
                Logger.LogTag.WALLET_CORE,
                "Failed to prepare multichain account upgrade: $t"
            )
            emptyList()
        }
    }

    private fun startMultichainUpgradeIfNeeded(enclaveToken: String, accountIds: List<String>) {
        if (accountIds.isEmpty()) {
            return
        }

        val upgradableAccountIds = accountIds.filter(EnclaveManager.sharedInstance::hasSecret)
        EnclaveManager.sharedInstance.releaseSessionUsages(
            enclaveToken,
            accountIds.size - upgradableAccountIds.size
        )
        if (upgradableAccountIds.isEmpty()) {
            cachedMultichainUpgradeAccountIds = null
            return
        }

        cachedMultichainUpgradeAccountIds = emptyList()
        WalletCore.scope.launch {
            try {
                WalletCore.call(
                    ApiMethod.Auth.UpgradeMultichainAccounts(enclaveToken, upgradableAccountIds)
                )
                cachedMultichainUpgradeAccountIds = null
                Logger.i(
                    Logger.LogTag.WALLET_CORE,
                    "Upgraded ${upgradableAccountIds.size} multichain accounts"
                )
            } catch (t: Throwable) {
                cachedMultichainUpgradeAccountIds = null
                Logger.e(
                    Logger.LogTag.WALLET_CORE,
                    "Failed to upgrade multichain accounts: $t"
                )
            }
        }
    }

    private fun cooldownForNumberOfFailedAttempts(attempts: Int): Long = when (attempts) {
        in 0..4 -> 0
        5 -> 60_000
        6 -> 300_000
        7 -> 900_000
        else -> 3600_000
    }

    private fun submitSuccessfulLogin() {
        failedLoginAttempts = 0
        lastFailedAttempt = 0L
    }

    private fun submitFailedLogin() {
        failedLoginAttempts += 1
        lastFailedAttempt = System.currentTimeMillis()
        val autoExitAttempts = WGlobalStorage.getAutoExit().failedAttempts ?: return
        if (failedLoginAttempts >= autoExitAttempts) autoExit()
    }

    private fun autoExit() {
        Logger.i(
            Logger.LogTag.WALLET_CORE,
            "Auto-exit: removing all wallets after $failedLoginAttempts failed attempts"
        )
        WalletCore.resetAccounts { _, _ ->
            WGlobalStorage.deleteAllWallets()
            WSecureStorage.deleteAllWalletValues()
            WalletContextManager.delegate?.get()?.restartApp()
        }
    }

    override fun wipeData() {
        cachedMultichainUpgradeAccountIds = null
        clearLongSession()
    }

    override fun clearCache() {
        cachedMultichainUpgradeAccountIds = null
    }
}
