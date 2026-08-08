package org.mytonwallet.app_air.walletcore.helpers

import com.iwebpp.crypto.TweetNaclFast
import com.squareup.moshi.JsonClass
import com.squareup.moshi.Moshi
import com.squareup.moshi.Types
import kotlin.io.encoding.Base64
import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage
import org.mytonwallet.app_air.walletcontext.secureStorage.WSecureStorage
import org.mytonwallet.app_air.walletcore.models.MAccount
import org.mytonwallet.app_air.walletcore.models.blockchain.MBlockchain
import org.mytonwallet.app_air.walletcore.moshi.ApiDerivation

internal object MultichainAccountUpgradeDetector {
    private val backendAuthMessage =
        "MyTonWallet_AuthToken_n6i0k4w8pb".toByteArray(Charsets.UTF_8)
    private val storedAccountsAdapter by lazy {
        val type = Types.newParameterizedType(
            Map::class.java,
            String::class.java,
            StoredAccount::class.java
        )
        Moshi.Builder().build().adapter<Map<String, StoredAccount>>(type)
    }

    suspend fun needsSDKPreparation(): Boolean {
        val encryptedAccountIds = WGlobalStorage.accountIds().mapNotNullTo(
            mutableSetOf()
        ) { accountId ->
            when (WGlobalStorage.getAccount(accountId)?.optString("type")) {
                MAccount.AccountType.HARDWARE.value,
                MAccount.AccountType.VIEW.value -> null

                else -> accountId
            }
        }
        val supportedUpgradeChains = MBlockchain.supportedChains
            .filter { it.multiWalletSupport != null }
            .mapTo(mutableSetOf()) { it.name }

        return needsSDKPreparation(
            encryptedAccountIds,
            WSecureStorage.getSecValue("accounts").takeIf { it.isNotEmpty() },
            supportedUpgradeChains
        )
    }

    internal suspend fun needsSDKPreparation(
        encryptedAccountIds: Set<String>,
        storedAccountsJSON: String?,
        supportedUpgradeChains: Set<String>,
        authTokenValidator: suspend (authToken: String, publicKey: String) -> Boolean =
            ::isBackendAuthTokenValid
    ): Boolean {
        if (encryptedAccountIds.isEmpty()) {
            return false
        }
        val storedAccounts = try {
            storedAccountsJSON?.let(storedAccountsAdapter::fromJson) ?: return true
        } catch (_: Exception) {
            return true
        }

        return encryptedAccountIds.any { accountId ->
            val account = storedAccounts[accountId] ?: return@any true
            if (account.type != "bip39" && account.type != "ton") {
                return@any true
            }

            val hasMissingChains = account.type == "bip39" && supportedUpgradeChains.any { chain ->
                account.byChain[chain]?.derivation == null
            }
            if (hasMissingChains) {
                return@any true
            }

            val tonWallet = account.byChain["ton"]
            val publicKey = tonWallet?.publicKey?.takeIf { it.isNotEmpty() } ?: return@any false
            val authToken = tonWallet.authToken?.takeIf { it.isNotEmpty() } ?: return@any true
            try {
                !authTokenValidator(authToken, publicKey)
            } catch (_: Exception) {
                true
            }
        }
    }

    internal fun isBackendAuthTokenValid(authToken: String, publicKey: String): Boolean = try {
        val signature = Base64.Default.decode(authToken)
        if (signature.size != 64 || Base64.Default.encode(signature) != authToken) {
            false
        } else {
            val publicKeyBytes = publicKey.hexToBytes()
            publicKeyBytes.size == 32 && TweetNaclFast.Signature(publicKeyBytes, null)
                .detached_verify(backendAuthMessage, signature)
        }
    } catch (_: Exception) {
        false
    }

    @JsonClass(generateAdapter = true)
    internal data class StoredAccount(val type: String, val byChain: Map<String, StoredChain>)

    @JsonClass(generateAdapter = true)
    internal data class StoredChain(
        val derivation: ApiDerivation?,
        val publicKey: String?,
        val authToken: String?
    )
}
