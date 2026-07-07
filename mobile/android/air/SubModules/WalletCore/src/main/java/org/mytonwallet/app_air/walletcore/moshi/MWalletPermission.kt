package org.mytonwallet.app_air.walletcore.moshi

import com.squareup.moshi.JsonClass
import java.math.BigDecimal
import java.math.BigInteger

sealed class MWalletPermission {
    abstract val chain: String

    @JsonClass(generateAdapter = true)
    data class Approval(
        override val chain: String,
        val tokenAddress: String,
        val tokenSlug: String,
        val tokenName: String,
        val tokenSymbol: String,
        val tokenDecimals: Int,
        val tokenImage: String? = null,
        val spenderAddress: String,
        val spenderName: String? = null,
        val spenderIcon: String? = null,
        // Serialized as a decimal string on the JS side.
        val allowance: BigDecimal,
        val isUnlimited: Boolean,
    ) : MWalletPermission()

    @JsonClass(generateAdapter = true)
    data class Delegation(
        override val chain: String,
        val delegateAddress: String,
        val delegateName: String? = null,
        val delegateIcon: String? = null,
    ) : MWalletPermission()
}

@JsonClass(generateAdapter = true)
data class MTonPlugin(
    val address: String,
    val name: String? = null,
    val balance: BigInteger,
    val isInitialized: Boolean,
)

sealed class MRevokeWalletPermissionOptions {
    abstract val accountId: String
    abstract val password: String?

    @JsonClass(generateAdapter = true)
    data class Approval(
        override val accountId: String,
        override val password: String?,
        val tokenAddress: String,
        val spenderAddress: String,
        val kind: String = "approval",
    ) : MRevokeWalletPermissionOptions()

    @JsonClass(generateAdapter = true)
    data class Delegation(
        override val accountId: String,
        override val password: String?,
        val delegateAddress: String,
        val kind: String = "delegation",
    ) : MRevokeWalletPermissionOptions()
}

@JsonClass(generateAdapter = true)
data class MRevokeWalletPermissionResult(
    val txId: String? = null,
    val error: String? = null,
)
