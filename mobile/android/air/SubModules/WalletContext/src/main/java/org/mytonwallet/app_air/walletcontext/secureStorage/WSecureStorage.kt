package org.mytonwallet.app_air.walletcontext.secureStorage

import android.app.Activity
import android.content.Context
import org.json.JSONObject
import org.mytonwallet.app_air.walletcontext.helpers.credentialsHelper.NativeBiometric
import java.util.concurrent.ConcurrentHashMap

object WSecureStorage {
    private var secureStorage: WSecureStorageProvider? = null
    private const val STATE_VERSION_KEY = "stateVersion"
    private const val STATE_VERSION_VAL = 20

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

    fun isFreshInstall(): Boolean {
        val storage = secureStorage
            ?: throw IllegalStateException("WSecureStorage not initialized.")
        return storage.keys().size == 0
    }

    private const val ACCOUNTS = "accounts"

    //private const val PASSCODE_LENGTH = "passcodeLength"
    private const val FAILED_LOGIN_ATTEMPTS = "failedLoginAttempts"
    private const val LAST_FAILED_ATTEMPT = "lastFailedAttempt"

    private val _cachedValues = ConcurrentHashMap<String, String>()

    fun allAccounts(): String {
        return getSecValue(ACCOUNTS)
    }

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

    fun getBiometricPasscode(activity: Activity): String? {
        return NativeBiometric(activity).getPasscode()
    }

    fun setBiometricPasscode(activity: Activity, passcode: String): Boolean {
        return NativeBiometric(activity).setCredentials("MyTonWallet", passcode)
    }

    fun deleteBiometricPasscode(activity: Activity): Boolean {
        return NativeBiometric(activity).deleteCredentials()
    }

    fun setFailedLoginAttempts(failedAttempts: Int) {
        return setSecValue(FAILED_LOGIN_ATTEMPTS, "$failedAttempts")
    }

    fun getFailedLoginAttempts(): Int? {
        return getSecValue(FAILED_LOGIN_ATTEMPTS).toIntOrNull()
    }

    fun setLastFailedAttempt(dt: Long) {
        return setSecValue(LAST_FAILED_ATTEMPT, "$dt")
    }

    fun getLastFailedAttempt(): Long? {
        return getSecValue(LAST_FAILED_ATTEMPT).toLongOrNull()
    }

    private val storageLock = Any()
    fun deleteAllWalletValues() {
        synchronized(storageLock) {
            val walletKeys = secureStorage!!.keys()
            for (key in walletKeys) {
                _cachedValues.remove(key)
                secureStorage!!.remove(key)
            }
            setSecValue(STATE_VERSION_KEY, STATE_VERSION_VAL.toString())
        }
    }

    fun setSecValue(key: String, value: String) {
        _cachedValues[key] = value
        synchronized(storageLock) {
            secureStorage!!.setData(key, value)
        }
    }

    fun getSecValue(key: String): String {
        return _cachedValues.getOrPut(key) {
            synchronized(storageLock) {
                secureStorage!!.getStringData(key)
            }
        }
    }

    fun getKeys(): Array<String> {
        return secureStorage!!.keys()
    }

    fun clearCache() {
        _cachedValues.clear()
    }
}
