package org.mytonwallet.app_air.walletcontext.sdkStorage

import java.io.IOException
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class WSdkInstallationStorageTest {
    @Test
    fun clientIdSurvivesEveryWalletClear() {
        val installation = MemoryStore()
        val legacy = MemoryStore()
        val values = InstallationScopedValues(installation, legacy)

        values.write("clientId", "\"a1b2:\"")
        legacy.values.clear()

        assertEquals("\"a1b2:\"", values.read("clientId"))
    }

    @Test
    fun legacyValueMovesToInstallationStorageOnFirstRead() {
        val installation = MemoryStore()
        val legacy = MemoryStore(mutableMapOf("clientId" to "\"c3d4:\""))
        val values = InstallationScopedValues(installation, legacy)

        assertEquals("\"c3d4:\"", values.read("clientId"))
        assertEquals("\"c3d4:\"", installation.values["clientId"])
        assertNull(legacy.values["clientId"])

        legacy.values.clear()
        assertEquals("\"c3d4:\"", values.read("clientId"))
    }

    @Test
    fun legacyValueStaysWhenInstallationWriteFails() {
        val installation = MemoryStore(canWrite = false)
        val legacy = MemoryStore(mutableMapOf("clientId" to "\"e5f6:\""))
        val values = InstallationScopedValues(installation, legacy)

        assertEquals("\"e5f6:\"", values.read("clientId"))
        assertEquals("\"e5f6:\"", legacy.values["clientId"])

        values.write("clientId", "\"e5f6:ref\"")
        assertEquals("\"e5f6:ref\"", legacy.values["clientId"])
    }

    @Test
    fun identityWrittenDuringAnOutageReachesInstallationBeforeTheClear() {
        val installation = MemoryStore(canWrite = false)
        val legacy = MemoryStore()
        val values = InstallationScopedValues(installation, legacy)
        values.write("clientId", "\"a7b8:\"")

        installation.canWrite = true
        WSdkInstallationStorage.keys.forEach { values.read(it) }
        legacy.values.clear()

        assertEquals("\"a7b8:\"", values.read("clientId"))
    }

    @Test
    fun missingValueReadsAsEmpty() {
        assertEquals("", InstallationScopedValues(MemoryStore(), MemoryStore()).read("clientId"))
    }

    @Test
    fun removeDeletesBothCopies() {
        val installation = MemoryStore(mutableMapOf("referrer" to "\"x\""))
        val legacy = MemoryStore(mutableMapOf("referrer" to "\"y\""))

        InstallationScopedValues(installation, legacy).remove("referrer")

        assertNull(installation.values["referrer"])
        assertNull(legacy.values["referrer"])
    }

    @Test
    fun absentDocumentStartsEmptyAndAcceptsWrites() {
        val file = MemoryDocument(exists = false)
        val document = InstallationDocument(file) { _, _ -> }

        assertNull(document.get("clientId"))
        assertTrue(document.set("clientId", "\"a1:\""))
        assertEquals(mapOf("clientId" to "\"a1:\""), file.content)
    }

    @Test
    fun unreadableDocumentIsNeverReplaced() {
        val file = MemoryDocument(content = mapOf("clientId" to "\"a1:\""), canRead = false)
        val document = InstallationDocument(file) { _, _ -> }

        assertNull(document.get("clientId"))
        assertFalse(document.set("clientId", "\"b2:\""))
        assertFalse(document.remove("clientId"))
        assertEquals(mapOf("clientId" to "\"a1:\""), file.content)

        file.canRead = true
        assertEquals("\"a1:\"", document.get("clientId"))
    }

    @Test
    fun failedCommitRereadsWhatReachedTheDisk() {
        val file = MemoryDocument(exists = false, failAfterWrite = true)
        val document = InstallationDocument(file) { _, _ -> }

        assertFalse(document.set("clientId", "\"a1:\""))

        file.failAfterWrite = false
        assertEquals("\"a1:\"", document.get("clientId"))
    }

    private class MemoryStore(
        val values: MutableMap<String, String> = mutableMapOf(),
        var canWrite: Boolean = true
    ) : ValueStore {
        override fun read(key: String): String? = values[key]

        override fun write(key: String, value: String): Boolean {
            if (canWrite) values[key] = value
            return canWrite
        }

        override fun delete(key: String) {
            values.remove(key)
        }
    }

    private class MemoryDocument(
        var content: Map<String, String> = emptyMap(),
        private var exists: Boolean = true,
        var canRead: Boolean = true,
        var failAfterWrite: Boolean = false
    ) : MapDocument {
        override fun exists() = exists

        override fun read(): Map<String, String> {
            if (!canRead) throw IOException("unreadable")
            return content
        }

        override fun write(values: Map<String, String>) {
            content = values
            exists = true
            if (failAfterWrite) throw IOException("verification failed")
        }
    }
}
