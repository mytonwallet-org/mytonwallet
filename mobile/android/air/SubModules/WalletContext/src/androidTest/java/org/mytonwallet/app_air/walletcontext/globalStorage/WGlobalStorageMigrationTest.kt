package org.mytonwallet.app_air.walletcontext.globalStorage

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.json.JSONArray
import org.json.JSONObject
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.mytonwallet.app_air.walletbasecontext.utils.ApplicationContextHolder
import org.mytonwallet.app_air.walletcontext.cacheStorage.WCacheStorage
import org.mytonwallet.app_air.walletcontext.secureStorage.WSecureStorage

@RunWith(AndroidJUnit4::class)
class WGlobalStorageMigrationTest {
    @Before
    fun setUp() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        ApplicationContextHolder.update(context.applicationContext)
        if (WGlobalStorage.isInitialized) {
            WGlobalStorage.clearCachedData()
        }
        WCacheStorage.init(context)
        WSecureStorage.init(context)
        WSecureStorage.clearStorage()
    }

    @After
    fun tearDown() {
        WSecureStorage.clearStorage()
    }

    @Test
    fun legacySingleAccountCacheMigratesToCurrentSchema() {
        val storage = InMemoryGlobalStorageProvider(
            JSONObject().apply {
                put(
                    "addresses",
                    JSONObject().apply {
                        put(
                            "byAccountId",
                            JSONObject().apply {
                                put("0-ton-mainnet", "EQlegacy")
                            }
                        )
                    }
                )
                put("currentTokenSlug", "toncoin")
                put("currentTokenPeriod", "1D")
                put("isBackupRequired", true)
                put(
                    "transactions",
                    JSONObject().apply {
                        put("byId", JSONObject().apply { put("legacy", JSONObject()) })
                    }
                )
                put("savedAddresses", JSONObject().apply { put("EQsaved", "Saved") })
                put(
                    "settings",
                    JSONObject().apply {
                        put("areTokensWithNoPriceHidden", false)
                        put("langSource", "user")
                    }
                )
                put(
                    "tokenInfo",
                    JSONObject().apply {
                        put(
                            "bySlug",
                            JSONObject().apply {
                                put("toncoin", JSONObject().apply { put("slug", "toncoin") })
                                put(
                                    "legacy-token",
                                    JSONObject().apply {
                                        put("slug", "legacy-token")
                                    }
                                )
                            }
                        )
                    }
                )
            }
        )

        WGlobalStorage.init(storage)

        assertEquals(60, storage.getInt("stateVersion"))
        assertEquals("0-ton-mainnet", storage.getString("currentAccountId"))
        assertEquals(
            "EQlegacy",
            storage.getString("accounts.byId.0-ton-mainnet.byChain.ton.address")
        )
        assertEquals(
            "EQlegacy",
            storage.getString("accounts.byId.0-testnet.byChain.ton.address")
        )
        assertEquals("mnemonic", storage.getString("accounts.byId.0-ton-mainnet.type"))
        assertEquals("none", storage.getString("staking.state"))
        assertTrue(storage.getBool("settings.areTokensWithNoBalanceHidden") == true)
        assertTrue(storage.getBool("settings.areTokensWithNoCostHidden") == true)
        assertNotNull(storage.getArray("byAccountId.0-ton-mainnet.savedAddresses"))
        assertFalse(storage.contains("byAccountId.0-ton-mainnet.transactions"))
        assertFalse(storage.contains("byAccountId.0-ton-mainnet.backupWallet"))
        assertFalse(storage.contains("addresses"))
        assertEquals(0, storage.doNotSynchronize)
    }

    @Test
    fun stateTwoMigrationRecreatesTestnetAccountAndState() {
        val storage = InMemoryGlobalStorageProvider(
            JSONObject().apply {
                put("stateVersion", 2)
                put("currentAccountId", "0-ton-mainnet")
                put(
                    "accounts",
                    JSONObject().apply {
                        put(
                            "byId",
                            JSONObject().apply {
                                put(
                                    "0-ton-mainnet",
                                    JSONObject().apply {
                                        put("address", "EQmain")
                                    }
                                )
                                put(
                                    "0-testnet",
                                    JSONObject().apply {
                                        put("address", "EQoldTestnet")
                                    }
                                )
                            }
                        )
                    }
                )
                put(
                    "byAccountId",
                    JSONObject().apply {
                        put("0-ton-mainnet", JSONObject())
                    }
                )
                put("settings", JSONObject().apply { put("langSource", "user") })
            }
        )

        WGlobalStorage.init(storage)

        assertEquals(
            "EQmain",
            storage.getString("accounts.byId.0-testnet.byChain.ton.address")
        )
        assertNotNull(storage.getDict("byAccountId.0-testnet"))
    }

    @Test
    fun stateFiftyNineMigrationRemovesLegacyMnemonicsOnlyOnce() {
        WSecureStorage.setSecValue(
            "accounts",
            JSONObject().apply {
                put(
                    "stale",
                    JSONObject().apply {
                        put("type", "ton")
                        put("mnemonicEncrypted", "corrupted")
                    }
                )
            }.toString()
        )
        val storage = InMemoryGlobalStorageProvider(
            JSONObject().apply { put("stateVersion", 59) }
        )

        WGlobalStorage.init(storage)

        assertEquals(60, storage.getInt("stateVersion"))
        val migratedAccount = WSecureStorage.getAccounts().getJSONObject("stale")
        assertEquals("ton", migratedAccount.getString("type"))
        assertFalse(migratedAccount.has("mnemonicEncrypted"))

        val accountsAfterMigration = WSecureStorage.getAccounts()
        accountsAfterMigration.getJSONObject("stale").put("mnemonicEncrypted", "later-value")
        WSecureStorage.setSecValue("accounts", accountsAfterMigration.toString())
        WGlobalStorage.init(storage)

        assertEquals(
            "later-value",
            WSecureStorage.getAccounts().getJSONObject("stale").getString("mnemonicEncrypted")
        )
    }

    @Test
    fun removingLastMnemonicAccountRemovesLegacyMnemonics() {
        WSecureStorage.setSecValue(
            "accounts",
            JSONObject().apply {
                put("first", JSONObject().apply { put("mnemonicEncrypted", "first-secret") })
                put("second", JSONObject().apply { put("mnemonicEncrypted", "second-secret") })
            }.toString()
        )
        val storage = InMemoryGlobalStorageProvider(
            JSONObject().apply {
                put("stateVersion", 60)
                put(
                    "accounts",
                    JSONObject().apply {
                        put(
                            "byId",
                            JSONObject().apply {
                                put("first", JSONObject().apply { put("type", "mnemonic") })
                                put("second", JSONObject().apply { put("type", "mnemonic") })
                            }
                        )
                    }
                )
            }
        )
        WGlobalStorage.init(storage)

        WGlobalStorage.removeAccount("first")

        assertTrue(
            WSecureStorage.getAccounts().getJSONObject("first").has("mnemonicEncrypted")
        )
        assertTrue(
            WSecureStorage.getAccounts().getJSONObject("second").has("mnemonicEncrypted")
        )

        WGlobalStorage.removeAccount("second")

        assertFalse(
            WSecureStorage.getAccounts().getJSONObject("first").has("mnemonicEncrypted")
        )
        assertFalse(
            WSecureStorage.getAccounts().getJSONObject("second").has("mnemonicEncrypted")
        )
    }

    private class InMemoryGlobalStorageProvider(private var root: JSONObject) :
        IGlobalStorageProvider {
        var doNotSynchronize = 0
            private set

        override fun incrementDoNotSynchronize() {
            doNotSynchronize++
        }

        override fun decrementDoNotSynchronize() {
            doNotSynchronize = (doNotSynchronize - 1).coerceAtLeast(0)
        }

        override fun contains(key: String): Boolean = getValue(key) != null

        override fun getInt(key: String): Int? = (getValue(key) as? Number)?.toInt()

        override fun getString(key: String): String? = getValue(key) as? String

        override fun getBool(key: String): Boolean? = getValue(key) as? Boolean

        override fun getDict(key: String): JSONObject? = getValue(key) as? JSONObject

        override fun getArray(key: String): JSONArray? = getValue(key) as? JSONArray

        override fun set(key: String, value: Any?, persistInstantly: Int) {
            setValue(key, value)
        }

        override fun set(items: Map<String, Any?>, persistInstantly: Int) {
            items.forEach { (key, value) -> setValue(key, value) }
        }

        override fun setEmptyObject(key: String, persistInstantly: Int) {
            setValue(key, JSONObject())
        }

        override fun setEmptyObjects(keys: Array<String>, persistInstantly: Int) {
            keys.forEach { setValue(it, JSONObject()) }
        }

        override fun remove(key: String, persistInstantly: Int) {
            setValue(key, null)
        }

        override fun remove(keys: Array<String>, persistInstantly: Int) {
            keys.forEach { setValue(it, null) }
        }

        override fun keysIn(key: String): Array<String> =
            getDict(key)?.keys()?.asSequence()?.toList()?.toTypedArray() ?: emptyArray()

        private fun getValue(key: String): Any? {
            var current: Any = root
            for (part in key.split('.')) {
                current = (current as? JSONObject)?.opt(part) ?: return null
                if (current == JSONObject.NULL) {
                    return null
                }
            }
            return current
        }

        private fun setValue(key: String, value: Any?) {
            val parts = key.split('.')
            var current = root
            for (part in parts.dropLast(1)) {
                current = current.optJSONObject(part) ?: JSONObject().also {
                    current.put(part, it)
                }
            }

            val finalPart = parts.last()
            if (value == null) {
                current.remove(finalPart)
            } else {
                current.put(finalPart, value)
            }
        }
    }
}
