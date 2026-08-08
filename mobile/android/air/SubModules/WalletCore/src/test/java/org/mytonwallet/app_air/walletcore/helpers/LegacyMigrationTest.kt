package org.mytonwallet.app_air.walletcore.helpers

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class LegacyMigrationTest {

    @Test
    fun `selectRequiredAccounts ignores optional accounts`() {
        val legacyAccounts = listOf(
            "required" to "required-ciphertext",
            "optional" to "corrupted-ciphertext"
        )

        val result = LegacyMigration.selectRequiredAccounts(legacyAccounts, setOf("required"))

        assertEquals(listOf("required" to "required-ciphertext"), result)
    }

    @Test
    fun `selectRequiredAccounts rejects missing required account`() {
        val legacyAccounts = listOf("optional" to "optional-ciphertext")

        val result = LegacyMigration.selectRequiredAccounts(legacyAccounts, setOf("required"))

        assertNull(result)
    }
}
