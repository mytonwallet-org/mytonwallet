package org.mytonwallet.app_air.walletcore

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.mytonwallet.app_air.walletbasecontext.utils.ApplicationContextHolder
import org.mytonwallet.app_air.walletcontext.globalStorage.IGlobalStorageProvider
import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage
import org.mytonwallet.app_air.walletcore.moshi.api.ApiUpdate
import org.mytonwallet.app_air.walletcore.stores.AccountStore

@RunWith(AndroidJUnit4::class)
class UpdatingStatusRoutingTest {
    @Test
    fun inactiveAccountUpdateDoesNotChangeActiveAccountStatus() {
        ApplicationContextHolder.update(InstrumentationRegistry.getInstrumentation().targetContext)
        WGlobalStorage.init(EmptyGlobalStorageProvider())

        val activeId = "active"
        val inactiveId = "inactive"
        var statusEvents = 0
        val observer = object : WalletCore.EventObserver {
            override fun onWalletEvent(walletEvent: WalletEvent) {
                if (walletEvent != WalletEvent.UpdatingStatusChanged) return
                statusEvents++
                assertFalse(AccountStore.updatingActivities)
                AccountStore.updateActiveAccount(inactiveId)
                assertTrue(AccountStore.updatingActivities)
                AccountStore.updateActiveAccount(activeId)
            }
        }

        InstrumentationRegistry.getInstrumentation().runOnMainSync {
            AccountStore.updateActiveAccount(activeId)
            WalletCore.registerObserver(observer)
            try {
                WalletCore.notifyApiUpdate(
                    ApiUpdate.ApiUpdateUpdatingStatus("activities", inactiveId, true)
                )
                assertFalse(AccountStore.updatingActivities)
                assertEquals(1, statusEvents)
            } finally {
                WalletCore.unregisterObserver(observer)
                AccountStore.setUpdatingActivities(inactiveId, false)
                AccountStore.updateActiveAccount(null)
            }
        }
    }

    private class EmptyGlobalStorageProvider : IGlobalStorageProvider {
        override fun incrementDoNotSynchronize() = Unit
        override fun decrementDoNotSynchronize() = Unit
        override fun contains(key: String) = false
        override fun getInt(key: String): Int? = if (key == "stateVersion") Int.MAX_VALUE else null
        override fun getString(key: String): String? = null
        override fun getBool(key: String): Boolean? = null
        override fun getDict(key: String): JSONObject? = null
        override fun getArray(key: String): JSONArray? = null
        override fun set(key: String, value: Any?, persistInstantly: Int) = Unit
        override fun set(items: Map<String, Any?>, persistInstantly: Int) = Unit
        override fun setEmptyObject(key: String, persistInstantly: Int) = Unit
        override fun setEmptyObjects(keys: Array<String>, persistInstantly: Int) = Unit
        override fun remove(key: String, persistInstantly: Int) = Unit
        override fun remove(keys: Array<String>, persistInstantly: Int) = Unit
        override fun keysIn(key: String): Array<String> = emptyArray()
    }
}
