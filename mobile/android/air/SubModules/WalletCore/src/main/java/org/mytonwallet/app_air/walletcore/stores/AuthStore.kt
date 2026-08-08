package org.mytonwallet.app_air.walletcore.stores

import androidx.fragment.app.FragmentActivity
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import org.mytonwallet.app_air.native_enclave.EnclaveManager
import org.mytonwallet.app_air.native_enclave.auth.AuthType
import org.mytonwallet.app_air.walletbasecontext.logger.Logger
import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage
import org.mytonwallet.app_air.walletcontext.secureStorage.WSecureStorage
import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.api.cleanupLegacyAuthAfterMigration
import org.mytonwallet.app_air.walletcore.api.cleanupLegacyBiometricAuthIfMigrated
import org.mytonwallet.app_air.walletcore.api.enclaveAuthorize
import org.mytonwallet.app_air.walletcore.api.enclaveMigrateAuth
import org.mytonwallet.app_air.walletcore.api.enclaveMigrateFromLegacy
import org.mytonwallet.app_air.walletcore.helpers.LegacyMigration
import org.mytonwallet.app_air.walletcore.helpers.MultichainAccountUpgradeDetector
import org.mytonwallet.app_air.walletcore.models.MBridgeError
import org.mytonwallet.app_air.walletcore.moshi.api.ApiMethod

class AuthCooldownError(val cooldownDate: Long) : Exception()

object AuthStore : IStore {
    @Volatile
    private var cachedMultichainUpgradeUsageCount: Int? = null

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
                val upgradeUsageCount = pendingMultichainUpgradeUsageCount()
                val usageCount = 1 + upgradeUsageCount

                val needsLegacyMigration = LegacyMigration.needsMigration()
                if (needsLegacyMigration) {
                    withContext(Dispatchers.Main) {
                        performLegacyMigration(
                            activity,
                            passcode,
                            usageCount,
                            upgradeUsageCount,
                            callback
                        )
                    }
                } else {
                    WalletCore.enclaveAuthorize(
                        activity,
                        AuthType.PASSCODE,
                        false,
                        passcode,
                        usageCount
                    ) { token, error ->
                        WalletCore.scope.launch(Dispatchers.Main) {
                            if (token != null) {
                                submitSuccessfulLogin()
                                startMultichainUpgradeIfNeeded(token, upgradeUsageCount)
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
        callback: (enclaveToken: String?) -> Unit
    ) {
        if (!WGlobalStorage.isLegacyBiometricActivated()) {
            authorizeWithNativeBiometrics(activity, onAuthenticated, callback)
            return
        }

        WalletCore.doOnBridgeReady {
            WalletCore.scope.launch {
                val upgradeUsageCount = pendingMultichainUpgradeUsageCount()
                val usageCount = 1 + upgradeUsageCount

                withContext(Dispatchers.Main) {
                    onBridgeReady()
                    val onAuthorized: (String?) -> Unit = { token ->
                        if (token != null) {
                            startMultichainUpgradeIfNeeded(token, upgradeUsageCount)
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
                        ) { token, _ ->
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
        callback: (enclaveToken: String?) -> Unit
    ) {
        var upgradeUsageCount = 0
        EnclaveManager.sharedInstance.authorizeWithBiometrics(
            activity,
            { createSession ->
                onAuthenticated()
                WalletCore.doOnBridgeReady {
                    WalletCore.scope.launch {
                        upgradeUsageCount = pendingMultichainUpgradeUsageCount()
                        withContext(Dispatchers.Main) {
                            createSession.accept(1 + upgradeUsageCount)
                        }
                    }
                }
            },
            object : EnclaveManager.SessionCallback {
                override fun onSuccess(token: String?, validUntil: Long) {
                    if (token != null) {
                        startMultichainUpgradeIfNeeded(token, upgradeUsageCount)
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
        upgradeUsageCount: Int,
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
                    startMultichainUpgradeIfNeeded(authorizedToken, upgradeUsageCount)
                    callback(true, authorizedToken, null, null)
                }
            } else {
                startMultichainUpgradeIfNeeded(token, upgradeUsageCount)
                callback(true, token, null, null)
            }
        }
    }

    private suspend fun pendingMultichainUpgradeUsageCount(): Int {
        cachedMultichainUpgradeUsageCount?.let {
            return it
        }

        val needsSDKPreparation = MultichainAccountUpgradeDetector.needsSDKPreparation()
        if (!needsSDKPreparation) {
            cachedMultichainUpgradeUsageCount = 0
            return 0
        }

        return try {
            WalletCore.call(ApiMethod.Auth.WaitDataPreload())
            WalletCore.call(ApiMethod.Auth.RepairInvalidBip39TonAuthTokens())
            WalletCore.call(ApiMethod.Auth.GetMultichainUpgradeCandidateIds()).size.also {
                cachedMultichainUpgradeUsageCount = it
            }
        } catch (t: Throwable) {
            Logger.e(
                Logger.LogTag.WALLET_CORE,
                "Failed to prepare multichain account upgrade: $t"
            )
            0
        }
    }

    private fun startMultichainUpgradeIfNeeded(enclaveToken: String, usageCount: Int) {
        if (usageCount == 0) {
            return
        }

        cachedMultichainUpgradeUsageCount = 0
        WalletCore.scope.launch {
            try {
                WalletCore.call(ApiMethod.Auth.UpgradeMultichainAccounts(enclaveToken))
                cachedMultichainUpgradeUsageCount = null
                Logger.i(
                    Logger.LogTag.WALLET_CORE,
                    "Upgraded $usageCount multichain accounts"
                )
            } catch (t: Throwable) {
                cachedMultichainUpgradeUsageCount = null
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
    }

    override fun wipeData() {
        cachedMultichainUpgradeUsageCount = null
    }

    override fun clearCache() {
        cachedMultichainUpgradeUsageCount = null
    }
}
