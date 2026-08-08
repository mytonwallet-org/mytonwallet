package org.mytonwallet.app_air.walletcore.helpers

import android.util.Base64
import androidx.fragment.app.FragmentActivity
import java.security.MessageDigest
import javax.crypto.Cipher
import javax.crypto.SecretKeyFactory
import javax.crypto.spec.GCMParameterSpec
import javax.crypto.spec.PBEKeySpec
import javax.crypto.spec.SecretKeySpec
import org.mytonwallet.app_air.native_enclave.DeviceLockedException
import org.mytonwallet.app_air.native_enclave.EnclaveManager
import org.mytonwallet.app_air.native_enclave.auth.AuthType
import org.mytonwallet.app_air.walletbasecontext.logger.Logger
import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage
import org.mytonwallet.app_air.walletcontext.secureStorage.WSecureStorage
import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.api.cleanupLegacyAuthAfterMigration
import org.mytonwallet.app_air.walletcore.api.cleanupLegacyBiometricAuthIfMigrated
import org.mytonwallet.app_air.walletcore.api.enclaveMigrateAuth
import org.mytonwallet.app_air.walletcore.api.enclaveMigrateFromLegacy
import org.mytonwallet.app_air.walletcore.models.MAccount
import org.mytonwallet.app_air.walletcore.stores.AccountStore

private const val GCM_TAG_BITS = 128
private val LOG_TAG = Logger.LogTag.ENCLAVE

internal fun String.hexToBytes(): ByteArray {
    require(length % 2 == 0) { "Hex string must have even length" }
    return ByteArray(length / 2) { i ->
        ((this[i * 2].digitToInt(16) shl 4) or this[i * 2 + 1].digitToInt(16)).toByte()
    }
}

/**
 * Legacy mnemonic decryption and migration to the new native enclave.
 * Implements two old encryption formats matching `src/enclave/legacy/migration.ts`.
 */
object LegacyMigration {

    fun needsMigration(): Boolean = EnclaveManager.sharedInstance.isLegacyMigrationAllowed &&
        requiredLegacyAccountIds().isNotEmpty()

    internal fun requiredLegacyAccountIds(): Set<String> =
        WGlobalStorage.accountIds().mapNotNullTo(mutableSetOf()) { accountId ->
            AccountStore.accountById(accountId)
                ?.takeIf { it.accountType == MAccount.AccountType.MNEMONIC }
                ?.accountId
        }

    internal fun selectRequiredAccounts(
        legacyAccounts: List<Pair<String, String>>,
        requiredAccountIds: Set<String>
    ): List<Pair<String, String>>? {
        val accountsById = legacyAccounts.toMap()
        return requiredAccountIds.sorted().map { accountId ->
            accountId to (accountsById[accountId] ?: return null)
        }
    }

    /**
     * Decrypts a legacy-encrypted mnemonic.
     * Tries PBKDF2 format (has `:` separators) first, falls back to SHA-256 format.
     */
    fun decryptLegacyMnemonic(encrypted: String, password: String): List<String>? = try {
        if (encrypted.contains(':')) {
            decryptPbkdf2Format(encrypted, password)
        } else {
            decryptSha256Format(encrypted, password)
        }
    } catch (e: Exception) {
        Logger.d(
            LOG_TAG,
            "Legacy migration: decryption failed reason=${e.javaClass.simpleName}"
        )
        null
    }

    /**
     * Format 2 (PBKDF2): `{saltHex}:{ivHex}:{base64Ciphertext}`
     * Key = PBKDF2(password, salt, 100k iterations, SHA-256) → AES-GCM
     */
    private fun decryptPbkdf2Format(encrypted: String, password: String): List<String> {
        val parts = encrypted.split(':')
        require(parts.size == 3) { "Invalid PBKDF2 format" }
        val (saltHex, ivHex, ciphertextBase64) = parts

        val salt = saltHex.hexToBytes()
        val iv = ivHex.hexToBytes()
        val ciphertext = Base64.decode(ciphertextBase64, Base64.NO_WRAP)

        val spec = PBEKeySpec(password.toCharArray(), salt, 100_000, 256)
        val rawKey = SecretKeyFactory.getInstance("PBKDF2WithHmacSHA256").generateSecret(spec)
        val key = SecretKeySpec(rawKey.encoded, "AES")

        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.DECRYPT_MODE, key, GCMParameterSpec(GCM_TAG_BITS, iv))
        val plaintext = String(cipher.doFinal(ciphertext), Charsets.UTF_8)

        return plaintext.split(',')
    }

    /**
     * Format 1 (simple): first 24 chars = IV hex (12 bytes), rest = Base64 ciphertext
     * Key = SHA-256(password) imported as raw AES key
     */
    private fun decryptSha256Format(encrypted: String, password: String): List<String> {
        val ivHex = encrypted.substring(0, 24)
        val ciphertextBase64 = encrypted.substring(24)

        val iv = ivHex.hexToBytes()
        val ciphertext = Base64.decode(ciphertextBase64, Base64.NO_WRAP)

        val pwHash = MessageDigest.getInstance("SHA-256")
            .digest(password.toByteArray(Charsets.UTF_8))
        val key = SecretKeySpec(pwHash, "AES")

        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.DECRYPT_MODE, key, GCMParameterSpec(GCM_TAG_BITS, iv))
        val plaintext = String(cipher.doFinal(ciphertext), Charsets.UTF_8)

        return plaintext.split(',')
    }

    /**
     * Migrates legacy accounts to the new enclave with passcode auth.
     *
     * @param activity Fragment Activity
     * @param legacyAccounts List of (accountId, mnemonicEncrypted) pairs
     * @param password The user's passcode/password
     * @param onSuccessCallback Called with the session token
     * @param onErrorCallback Called on failure
     */
    fun migrateToEnclave(
        activity: FragmentActivity,
        legacyAccounts: List<Pair<String, String>>,
        password: String,
        usageCount: Int = 1,
        onSuccessCallback: (token: String) -> Unit,
        onErrorCallback: (String?) -> Unit
    ) {
        try {
            val secrets = mutableListOf<Array<String>>()
            val unmigratedAccountIds = mutableSetOf<String>()
            for ((accountId, mnemonicEncrypted) in legacyAccounts) {
                val mnemonic = decryptLegacyMnemonic(mnemonicEncrypted, password)
                if (mnemonic == null) {
                    unmigratedAccountIds.add(accountId)
                    continue
                }
                secrets.add(arrayOf(accountId, mnemonic.joinToString(" ")))
            }

            // Only a full failure proves the passcode wrong; a partial one means damaged blobs,
            // and the readable accounts must not be held hostage to them.
            if (secrets.isEmpty()) {
                onErrorCallback("Invalid password")
                return
            }
            if (unmigratedAccountIds.isNotEmpty()) {
                Logger.e(
                    LOG_TAG,
                    "Legacy migration: skipping accounts that failed to decrypt " +
                        "count=${unmigratedAccountIds.size} accountIds=$unmigratedAccountIds"
                )
            }

            EnclaveManager.sharedInstance.migrateSecrets(
                secrets,
                AuthType.PASSCODE,
                password,
                usageCount,
                activity,
                object : EnclaveManager.SessionCallback {
                    override fun onSuccess(token: String?, validUntil: Long) {
                        onSuccessCallback(token!!)
                    }

                    override fun onError(error: String?) {
                        onErrorCallback(error)
                    }
                }
            )
        } catch (e: Exception) {
            onErrorCallback("migrateToEnclave failed: ${e.message}")
        }
    }

    // Called when trying to unlock using biometrics, but migration is necessary.
    fun migrateBiometricsToEnclave(
        activity: FragmentActivity?,
        usageCount: Int = 1,
        callback: (newToken: String?) -> Unit
    ) {
        Logger.i(LOG_TAG, "Legacy biometric migration: started")

        val safeFail: () -> Unit = {
            callback(null)
        }

        val safeActivity = activity ?: run {
            Logger.d(LOG_TAG, "Legacy biometric migration: deferred reason=no_activity")
            return safeFail()
        }

        val password = WSecureStorage.getBiometricPasscode(safeActivity) ?: run {
            Logger.d(
                LOG_TAG,
                "Legacy biometric migration: deferred reason=no_legacy_biometric_passcode"
            )
            return safeFail()
        }

        fun migrateBiometricAuth(activity: FragmentActivity, token: String) {
            WalletCore.enclaveMigrateAuth(
                activity,
                token,
                AuthType.BIOMETRIC,
                null,
                false,
                usageCount
            ) { newToken, error ->
                if (newToken == null) {
                    Logger.e(
                        LOG_TAG,
                        "Legacy biometric migration: authentication migration failed " +
                            "reason=${error?.type?.name ?: "missing_token"}"
                    )
                    return@enclaveMigrateAuth safeFail()
                }

                WalletCore.cleanupLegacyBiometricAuthIfMigrated()

                Logger.i(LOG_TAG, "Legacy biometric migration: completed")
                callback(newToken)
            }
        }

        if (needsMigration()) {
            Logger.i(LOG_TAG, "Legacy biometric migration: migrating account secrets")
            WalletCore.enclaveMigrateFromLegacy(
                activity,
                password
            ) { token, error ->
                if (token == null) {
                    Logger.e(
                        LOG_TAG,
                        "Legacy biometric migration: account migration failed " +
                            "reason=${error?.type?.name ?: "invalid_passcode_or_legacy_data"}"
                    )
                    return@enclaveMigrateFromLegacy safeFail()
                }

                WalletCore.cleanupLegacyAuthAfterMigration()

                migrateBiometricAuth(activity, token)
            }
        } else {
            EnclaveManager.sharedInstance.authorize(
                AuthType.PASSCODE,
                false,
                password,
                activity,
                object : EnclaveManager.SessionCallback {
                    override fun onSuccess(token: String?, validUntil: Long) {
                        val token = token ?: return safeFail()
                        migrateBiometricAuth(activity, token)
                    }

                    override fun onError(error: String?) {
                        val reason = if (DeviceLockedException.matches(error)) {
                            "device_locked"
                        } else {
                            "passcode_authorization_failed"
                        }
                        Logger.e(
                            LOG_TAG,
                            "Legacy biometric migration: prerequisite authorization failed " +
                                "reason=$reason"
                        )
                        safeFail()
                    }
                }
            )
        }
    }
}
