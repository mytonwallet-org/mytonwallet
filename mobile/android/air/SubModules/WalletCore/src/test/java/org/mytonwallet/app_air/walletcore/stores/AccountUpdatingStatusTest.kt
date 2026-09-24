package org.mytonwallet.app_air.walletcore.stores

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class AccountUpdatingStatusTest {
    @Test
    fun updatingStatusFollowsTheActiveAccount() {
        val firstAccountId = "first"
        val secondAccountId = "second"
        AccountStore.updateActiveAccount(firstAccountId)
        try {
            AccountStore.setUpdatingActivities(secondAccountId, true)
            AccountStore.setUpdatingBalance(firstAccountId, true)
            assertFalse(AccountStore.updatingActivities)
            assertTrue(AccountStore.updatingBalance)

            AccountStore.updateActiveAccount(secondAccountId)
            assertTrue(AccountStore.updatingActivities)
            assertFalse(AccountStore.updatingBalance)

            AccountStore.setUpdatingActivities(secondAccountId, false)
            assertFalse(AccountStore.updatingActivities)
        } finally {
            AccountStore.setUpdatingActivities(secondAccountId, false)
            AccountStore.setUpdatingBalance(firstAccountId, false)
            AccountStore.updateActiveAccount(null)
        }
    }
}
