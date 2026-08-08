package org.mytonwallet.app_air.walletcore.helpers

import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class MultichainAccountUpgradeDetectorTest {
    private val backendAuthPublicKey =
        "8a88e3dd7409f195fd52db2d3cba5d72ca6709bf1d94121bf3748801b40f6f5c"
    private val backendAuthToken =
        "gOtof026jOQAKTjektdosbJCLUK0TsQ55i70nrfAttF+m53f0E6TmFLjBSnRKawR5L/bycdGhkieUSvzbop+Cg=="
    private val encryptedAccountIds = setOf("account-mainnet")
    private val supportedUpgradeChains = setOf("ton", "ethereum")

    @Test
    fun `fully upgraded accounts skip SDK preparation`() {
        assertFalse(needsSDKPreparation(storedAccountJSON()))
    }

    @Test
    fun `legacy TON accounts do not require multichain wallets`() {
        assertFalse(
            needsSDKPreparation(storedAccountJSON(accountType = "ton", includeEthereum = false))
        )
    }

    @Test
    fun `missing supported chain requires SDK preparation`() {
        assertTrue(needsSDKPreparation(storedAccountJSON(includeEthereum = false)))
    }

    @Test
    fun `missing backend auth token requires SDK preparation`() {
        assertTrue(needsSDKPreparation(storedAccountJSON(includeAuthToken = false)))
    }

    @Test
    fun `invalid backend auth token requires SDK preparation`() {
        assertTrue(needsSDKPreparation(storedAccountJSON(), authTokenIsValid = false))
    }

    @Test
    fun `missing local storage is conservative for encrypted accounts`() {
        assertTrue(needsSDKPreparation(null))
    }

    @Test
    fun `malformed local storage is conservative for encrypted accounts`() {
        assertTrue(needsSDKPreparation("not-json"))
    }

    @Test
    fun `malformed derivation is conservative for encrypted accounts`() {
        assertTrue(
            needsSDKPreparation(
                storedAccountJSON().replace(
                    "{\"path\":\"m/44'/60'/0'\",\"index\":0}",
                    "\"invalid\""
                )
            )
        )
    }

    @Test
    fun `missing stored account is conservative for encrypted accounts`() {
        assertTrue(needsSDKPreparation("{}"))
    }

    @Test
    fun `accounts without encrypted secrets skip SDK preparation`() {
        assertFalse(
            runBlocking {
                MultichainAccountUpgradeDetector.needsSDKPreparation(
                    emptySet(),
                    null,
                    supportedUpgradeChains
                )
            }
        )
    }

    @Test
    fun `backend auth validator failure is conservative`() {
        assertTrue(
            runBlocking {
                MultichainAccountUpgradeDetector.needsSDKPreparation(
                    encryptedAccountIds,
                    storedAccountJSON(),
                    supportedUpgradeChains
                ) { _, _ -> throw IllegalStateException("bridge unavailable") }
            }
        )
    }

    @Test
    fun `valid backend auth signature is accepted`() {
        assertTrue(
            MultichainAccountUpgradeDetector.isBackendAuthTokenValid(
                backendAuthToken,
                backendAuthPublicKey
            )
        )
    }

    @Test
    fun `invalid backend auth signature is rejected`() {
        val invalidToken = "A${backendAuthToken.drop(1)}"

        assertFalse(
            MultichainAccountUpgradeDetector.isBackendAuthTokenValid(
                invalidToken,
                backendAuthPublicKey
            )
        )
    }

    @Test
    fun `malformed backend auth values are rejected`() {
        assertFalse(
            MultichainAccountUpgradeDetector.isBackendAuthTokenValid(
                "not-base64",
                backendAuthPublicKey
            )
        )
        assertFalse(
            MultichainAccountUpgradeDetector.isBackendAuthTokenValid(
                backendAuthToken,
                "not-a-public-key"
            )
        )
    }

    private fun needsSDKPreparation(storedAccountsJSON: String?, authTokenIsValid: Boolean = true) =
        runBlocking {
            MultichainAccountUpgradeDetector.needsSDKPreparation(
                encryptedAccountIds,
                storedAccountsJSON,
                supportedUpgradeChains
            ) { _, _ -> authTokenIsValid }
        }

    private fun storedAccountJSON(
        accountType: String = "bip39",
        includeEthereum: Boolean = true,
        includeAuthToken: Boolean = true
    ): String {
        val ethereum = if (includeEthereum) {
            ""","ethereum":{"derivation":{"path":"m/44'/60'/0'","index":0}}"""
        } else {
            ""
        }
        val authToken = if (includeAuthToken) ",\"authToken\":\"token\"" else ""
        return """
            {
              "account-mainnet": {
                "type": "$accountType",
                "byChain": {
                  "ton": {
                    "derivation": {"path": "m/44'/607'/0'", "index": 0},
                    "publicKey": "public-key"$authToken
                  }$ethereum
                }
              }
            }
        """.trimIndent()
    }
}
