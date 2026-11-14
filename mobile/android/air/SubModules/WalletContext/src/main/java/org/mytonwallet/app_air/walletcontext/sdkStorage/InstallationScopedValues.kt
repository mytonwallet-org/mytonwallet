package org.mytonwallet.app_air.walletcontext.sdkStorage

interface ValueStore {
    fun read(key: String): String?
    fun write(key: String, value: String): Boolean
    fun delete(key: String)
}

class InstallationScopedValues(
    private val installation: ValueStore,
    private val legacy: ValueStore
) {
    fun read(key: String): String {
        installation.read(key)?.let { return it }
        val legacyValue = legacy.read(key) ?: return ""
        if (installation.write(key, legacyValue)) legacy.delete(key)
        return legacyValue
    }

    fun write(key: String, value: String) {
        if (installation.write(key, value)) legacy.delete(key) else legacy.write(key, value)
    }

    fun remove(key: String) {
        installation.delete(key)
        legacy.delete(key)
    }
}
