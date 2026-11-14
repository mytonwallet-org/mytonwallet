package org.mytonwallet.app_air.walletcontext.sdkStorage

import android.content.Context
import com.squareup.moshi.Types
import org.mytonwallet.app_air.walletbasecontext.logger.Logger
import org.mytonwallet.app_air.walletcontext.installationStorage.AtomicJsonFile
import org.mytonwallet.app_air.walletcontext.installationStorage.storageMoshi
import org.mytonwallet.app_air.walletcontext.secureStorage.WSecureStorage

// The SDK client identity outlives wallets, so no wallet clear may empty this storage, and
// noBackupFilesDir keeps it off a transferred device.
object WSdkInstallationStorage {
    val keys = setOf("clientId", "referrer")

    private val adapter = storageMoshi.adapter<Map<String, String>>(
        Types.newParameterizedType(Map::class.java, String::class.java, String::class.java)
    )
    private var document: InstallationDocument? = null

    val values = InstallationScopedValues(
        installation = object : ValueStore {
            override fun read(key: String) = getValue(key)
            override fun write(key: String, value: String) = setValue(key, value)
            override fun delete(key: String) {
                removeValue(key)
            }
        },
        legacy = object : ValueStore {
            override fun read(key: String) = WSecureStorage.getSecValue(key).ifEmpty { null }
            override fun write(key: String, value: String): Boolean {
                WSecureStorage.setSecValue(key, value)
                return true
            }

            override fun delete(key: String) = WSecureStorage.removeSecValue(key)
        }
    )

    @Synchronized
    fun init(context: Context) {
        val file = AtomicJsonFile(
            context.noBackupFilesDir,
            "sdk-installation-v1.json",
            adapter,
            4096
        )
        document = InstallationDocument(
            object : MapDocument {
                override fun exists() = file.exists()
                override fun read() = file.read()
                override fun write(values: Map<String, String>) = file.write(values)
            }
        ) { operation, error ->
            Logger.e(
                Logger.LogTag.SECURE_STORAGE,
                "SDK installation storage $operation failed error=${error.javaClass.simpleName}"
            )
        }
    }

    @Synchronized
    fun getValue(key: String): String? = document?.get(key)

    @Synchronized
    fun setValue(key: String, value: String): Boolean = document?.set(key, value) ?: false

    @Synchronized
    fun removeValue(key: String): Boolean = document?.remove(key) ?: false

    @Synchronized
    fun getKeys(): Array<String> = document?.keys().orEmpty().toTypedArray()

    fun beforeWalletClear() = keys.forEach { key -> runCatching { values.read(key) } }
}

internal interface MapDocument {
    fun exists(): Boolean
    fun read(): Map<String, String>
    fun write(values: Map<String, String>)
}

// A document that exists but cannot be read holds an identity this process cannot see, so it
// answers nothing and accepts no write until a later read succeeds.
internal class InstallationDocument(
    private val file: MapDocument,
    private val onError: (String, Exception) -> Unit
) {
    private var cached: Map<String, String>? = null

    fun get(key: String): String? = current()?.get(key)

    fun set(key: String, value: String): Boolean {
        val values = current() ?: return false
        return values[key] == value || commit(values + (key to value))
    }

    fun remove(key: String): Boolean {
        val values = current() ?: return false
        return key !in values || commit(values - key)
    }

    fun keys(): Set<String> = current()?.keys.orEmpty()

    private fun current(): Map<String, String>? = cached ?: try {
        (if (file.exists()) file.read() else emptyMap()).also { cached = it }
    } catch (e: Exception) {
        onError("read", e)
        null
    }

    private fun commit(next: Map<String, String>): Boolean = try {
        file.write(next)
        cached = next
        true
    } catch (e: Exception) {
        // A failed commit may still have reached the disk, so the next access rereads it.
        cached = null
        onError("write", e)
        false
    }
}
