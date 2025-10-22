package org.mytonwallet.app_air.walletcore.stores

import org.mytonwallet.app_air.walletcontext.secureStorage.WSecureStorage
import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.api.verifyPassword

class AuthCooldownError(val cooldownDate: Long) : Exception()

object AuthStore : IStore {
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

    fun getCooldownDate(): Long {
        return lastFailedAttempt + cooldownForNumberOfFailedAttempts(failedLoginAttempts)
    }

    fun verifyPassword(password: String, callback: (Boolean, Long?) -> Unit) {
        val now = System.currentTimeMillis()
        val cooldownDate = getCooldownDate()
        val waitFor = cooldownDate - now

        if (waitFor > 0) {
            throw AuthCooldownError(cooldownDate)
        }

        val performVerification = {
            WalletCore.verifyPassword(password) { res, err ->
                if (res == true) {
                    submitSuccessfulLogin()
                } else {
                    submitFailedLogin()
                }
                val success = res == true
                callback(
                    success,
                    if (!success) getCooldownDate() else null
                )
            }
        }

        if (shouldDelayVerification) {
            android.os.Handler(android.os.Looper.getMainLooper()).postDelayed({
                performVerification()
            }, 1000)
        } else {
            performVerification()
        }
    }

    private fun cooldownForNumberOfFailedAttempts(attempts: Int): Long {
        return when (attempts) {
            in 0..4 -> 0
            5 -> 60_000
            6 -> 300_000
            7 -> 900_000
            else -> 3600_000
        }
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
    }

    override fun clearCache() {
    }
}
