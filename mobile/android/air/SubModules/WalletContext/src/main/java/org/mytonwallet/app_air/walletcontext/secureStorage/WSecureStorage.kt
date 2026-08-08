package org.mytonwallet.app_air.walletcontext.secureStorage

import android.app.Activity
import android.content.Context
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.Executors
import org.json.JSONObject
import org.mytonwallet.app_air.walletbasecontext.utils.ApplicationContextHolder
import org.mytonwallet.app_air.walletcontext.helpers.credentialsHelper.LegacyNativeBiometric

object WSecureStorage {
    private var secureStorage: WSecureStorageProvider? = null
    private const val STATE_VERSION_KEY = "stateVersion"
    private const val STATE_VERSION_VAL = 23

    fun init(context: Context) {
        secureStorage =
            WSecureStorageProvider(
                context
            )
        clearCache()
        // Cache necessary values to reduce app start-up time after splash screen
        getLastFailedAttempt()
        getFailedLoginAttempts()
    }

    private val requiredStorage: WSecureStorageProvider
        get() = secureStorage
            ?: throw IllegalStateException("WSecureStorage not initialized.")

    fun isFreshInstall(): Boolean = requiredStorage.keys().size == 0

    private const val ACCOUNTS = "accounts"

    // private const val PASSCODE_LENGTH = "passcodeLength"
    private const val FAILED_LOGIN_ATTEMPTS = "failedLoginAttempts"
    private const val LAST_FAILED_ATTEMPT = "lastFailedAttempt"

    private val cachedValues = ConcurrentHashMap<String, String>()
    private val storageExecutor = Executors.newSingleThreadExecutor()

    // Keeps cache updates and task submission ordered with cleanup. Setters that arrive during
    // cleanup wait for it to finish, then their writes are included after the cleanup.
    private val storageOperationLock = Any()

    fun allAccounts(): String = getSecValue(ACCOUNTS)

    fun getAccounts(): JSONObject {
        val accountsData = getSecValue("accounts")
        return JSONObject(accountsData)
    }

    fun getPasscodeLength(): Int {
        return 4
        /*val passLength = getSecValue(PASSCODE_LENGTH)
        return if (passLength != "") passLength.toInt() else 4*/
    }

    /*fun setPasscodeLength(passcodeLength: Int) {
        setSecValue(PASSCODE_LENGTH, passcodeLength.toString())
    }*/

    fun getBiometricPasscode(activity: Activity): String? =
        LegacyNativeBiometric(activity).getPasscode()

    fun deleteLegacyBiometricPasscode(): Boolean =
        LegacyNativeBiometric.deleteCredentials(ApplicationContextHolder.applicationContext)

    /**
     * Drops the legacy ciphertext of every account [hasMigratedSecret] vouches for. There is no
     * default: erasing a mnemonic must be an answered question, and the answer has to come from
     * whoever holds the new copy.
     */
    fun removeLegacyMnemonics(hasMigratedSecret: (accountId: String) -> Boolean) {
        val accountsData = getSecValue(ACCOUNTS)
        if (accountsData.isEmpty()) return

        val accounts = try {
            JSONObject(accountsData)
        } catch (_: Exception) {
            return
        }
        var changed = false
        for (accountId in accounts.keys()) {
            if (!hasMigratedSecret(accountId)) continue
            val account = accounts.optJSONObject(accountId) ?: continue
            if (account.has("mnemonicEncrypted")) {
                account.remove("mnemonicEncrypted")
                changed = true
            }
        }
        if (changed) {
            setSecValue(ACCOUNTS, accounts.toString())
        }
    }

    fun setFailedLoginAttempts(failedAttempts: Int) =
        setSecValueAsync(FAILED_LOGIN_ATTEMPTS, "$failedAttempts")

    fun getFailedLoginAttempts(): Int? = getSecValue(FAILED_LOGIN_ATTEMPTS).toIntOrNull()

    fun setLastFailedAttempt(dt: Long) = setSecValueAsync(LAST_FAILED_ATTEMPT, "$dt")

    fun getLastFailedAttempt(): Long? = getSecValue(LAST_FAILED_ATTEMPT).toLongOrNull()

    private val storageLock = Any()
    fun deleteAllWalletValues() {
        synchronized(storageOperationLock) {
            storageExecutor.submit {
                synchronized(storageLock) {
                    deleteLegacyBiometricPasscode()
                    val storage = requiredStorage
                    val walletKeys = storage.keys()
                    for (key in walletKeys) {
                        cachedValues.remove(key)
                        storage.remove(key)
                    }
                    setSecValue(STATE_VERSION_KEY, STATE_VERSION_VAL.toString())
                }
            }.get()
        }
    }

    fun setSecValue(key: String, value: String) {
        synchronized(storageLock) {
            cachedValues[key] = value
            requiredStorage.setData(key, value)
        }
    }

    private fun setSecValueAsync(key: String, value: String) {
        // Login throttling reads the new value from memory immediately while secure-storage I/O
        // runs in the background, avoiding a disk-backed write on the UI/startup path.
        synchronized(storageOperationLock) {
            cachedValues[key] = value
            storageExecutor.execute {
                synchronized(storageLock) {
                    requiredStorage.setData(key, value)
                }
            }
        }
    }

    fun getSecValue(key: String): String = synchronized(storageLock) {
        cachedValues[key] ?: run {
            val value = requiredStorage.getStringData(key)
            cachedValues[key] = value
            value
        }
    }

    fun removeSecValue(key: String) {
        synchronized(storageLock) {
            cachedValues.remove(key)
            requiredStorage.remove(key)
        }
    }

    fun getKeys(): Array<String> = requiredStorage.keys()

    fun clearStorage() {
        synchronized(storageOperationLock) {
            storageExecutor.submit {
                synchronized(storageLock) {
                    secureStorage!!.clear()
                    cachedValues.clear()
                }
            }.get()
        }
    }

    fun clearCache() {
        cachedValues.clear()
    }
}
