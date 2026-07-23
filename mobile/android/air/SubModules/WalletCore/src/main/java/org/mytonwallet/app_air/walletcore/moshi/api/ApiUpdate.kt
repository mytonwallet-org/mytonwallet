package org.mytonwallet.app_air.walletcore.moshi.api

import com.squareup.moshi.JsonClass
import org.mytonwallet.app_air.walletcore.models.blockchain.MBlockchain
import org.mytonwallet.app_air.walletcore.moshi.ApiConnectionType
import org.mytonwallet.app_air.walletcore.moshi.ApiDapp
import org.mytonwallet.app_air.walletcore.moshi.ApiDappTransfer
import org.mytonwallet.app_air.walletcore.moshi.ApiDerivation
import org.mytonwallet.app_air.walletcore.moshi.ApiTokenWithPrice
import org.mytonwallet.app_air.walletcore.moshi.ApiTonConnectProof
import org.mytonwallet.app_air.walletcore.moshi.MApiTransaction
import org.mytonwallet.app_air.walletcore.moshi.MSignDataPayload
import org.mytonwallet.app_air.walletcore.moshi.WcPayAmount
import org.mytonwallet.app_air.walletcore.moshi.WcPayMerchant
import org.mytonwallet.app_air.walletcore.moshi.WcPayPaymentInfo
import org.mytonwallet.app_air.walletcore.moshi.WcPayPaymentOption
import org.mytonwallet.app_air.walletcore.moshi.adapter.AccountDomainUpdate
import org.mytonwallet.app_air.walletcore.moshi.adapter.MfaUpdate
import org.mytonwallet.app_air.walletcore.moshi.adapter.factory.JsonSealed
import org.mytonwallet.app_air.walletcore.moshi.adapter.factory.JsonSealedSubtype
import java.math.BigInteger

@JsonSealed("type", fallbackToNull = true)
sealed class ApiUpdate {

    interface ApiUpdateDappSignRequest {
        val promiseId: String
        val accountId: String
        val dapp: ApiDapp
        val isDangerous: Boolean
    }

    @JsonSealedSubtype("dappSendTransactions")
    @JsonClass(generateAdapter = true)
    data class ApiUpdateDappSendTransactions(
        override val promiseId: String,
        override val accountId: String,
        override val dapp: ApiDapp,
        val operationChain: String,
        val transactions: List<ApiDappTransfer>,
        val vestingAddress: String? = null,
        val validUntil: Long? = null,
        val emulation: Emulation? = null,
        val shouldHideTransfers: Boolean? = null,
        val isLegacyOutput: Boolean? = null
    ) : ApiUpdate(), ApiUpdateDappSignRequest {

        override val isDangerous: Boolean = transactions.any { it.isDangerous }

        @JsonClass(generateAdapter = true)
        data class Emulation(
            val activities: List<MApiTransaction>,
            val realFee: BigInteger
        )
    }

    @JsonSealedSubtype("dappSignData")
    @JsonClass(generateAdapter = true)
    data class ApiUpdateDappSignData(
        override val promiseId: String,
        override val accountId: String,
        override val dapp: ApiDapp,
        val operationChain: String,
        val payloadToSign: MSignDataPayload
    ) : ApiUpdate(), ApiUpdateDappSignRequest {
        override val isDangerous: Boolean = false
    }

    @JsonSealedSubtype("dappConnect")
    @JsonClass(generateAdapter = true)
    data class ApiUpdateDappConnect(
        val identifier: String? = null,
        val promiseId: String,
        val accountId: String,
        val dapp: ApiDapp,
        val permissions: Permissions,
        val proof: ApiTonConnectProof? = null
    ) : ApiUpdate() {
        @JsonClass(generateAdapter = true)
        data class Permissions(
            val address: Boolean,
            val proof: Boolean
        )
    }

    @JsonSealedSubtype("dappAlreadyConnected")
    @JsonClass(generateAdapter = true)
    data class ApiUpdateDappAlreadyConnected(
        val url: String? = null
    ) : ApiUpdate()

    @JsonSealedSubtype("dappDisconnect")
    @JsonClass(generateAdapter = true)
    data class ApiUpdateDappDisconnect(
        val accountId: String,
        val url: String
    ) : ApiUpdate()

    @JsonSealedSubtype("dappLoading")
    @JsonClass(generateAdapter = true)
    data class ApiUpdateDappLoading(
        val connectionType: ApiConnectionType,
        val isSse: Boolean? = null,
        val accountId: String? = null,
        // Set when a wake deeplink opens the placeholder request modal before the request event arrives
        val isWaitingForRequest: Boolean? = null,
        val returnUrl: String? = null
    ) : ApiUpdate()

    @JsonSealedSubtype("updateTokens")
    @JsonClass(generateAdapter = true)
    data class ApiUpdateTokens(
        val tokens: Map<String, ApiTokenWithPrice>
    ) : ApiUpdate()

    @JsonSealedSubtype("dappConnectComplete")
    @JsonClass(generateAdapter = true)
    data class ApiUpdateDappConnectComplete(
        val type: String? = null
    ) : ApiUpdate()

    @JsonSealedSubtype("dappDisconnected")
    @JsonClass(generateAdapter = true)
    data class ApiUpdateDappDisconnected(
        val url: String? = null
    ) : ApiUpdate()

    @JsonSealedSubtype("dappCloseLoading")
    @JsonClass(generateAdapter = true)
    data class ApiUpdateDappCloseLoading(
        val type: String? = null
    ) : ApiUpdate()

    @JsonSealedSubtype("updateDapps")
    @JsonClass(generateAdapter = true)
    data class ApiUpdateDapps(
        val type: String? = null
    ) : ApiUpdate()

    @JsonSealedSubtype("initialActivities")
    @JsonClass(generateAdapter = true)
    data class ApiUpdateInitialActivities(
        val accountId: String,
        val chain: MBlockchain,
        val mainActivities: List<MApiTransaction>,
        val bySlug: Map<String, List<MApiTransaction>>
    ) : ApiUpdate()

    @JsonSealedSubtype("updateWalletVersions")
    @JsonClass(generateAdapter = true)
    data class ApiUpdateWalletVersions(
        val accountId: String,
        val currentVersion: String,
        val versions: List<Version>
    ) : ApiUpdate() {
        @JsonClass(generateAdapter = true)
        data class Version(
            val address: String,
            val balance: BigInteger,
            val isInitialized: Boolean,
            val version: String
        )
    }

    @JsonSealedSubtype("updateCurrencyRates")
    @JsonClass(generateAdapter = true)
    data class ApiUpdateCurrencyRates(
        val rates: Map<String, Double>
    ) : ApiUpdate()

    @JsonSealedSubtype("updateAccount")
    @JsonClass(generateAdapter = true)
    data class ApiUpdateUpdateAccount(
        val accountId: String,
        val chain: MBlockchain,
        val address: String?,
        /** `false` means that the account has no domain; `undefined` means that the domain has not changed */
        val domain: AccountDomainUpdate?,
        val isMultisig: Boolean?,
        val derivation: ApiDerivation?,
        /** `false` means the MFA was removed; absent means it has not changed */
        val mfa: MfaUpdate?
    ) : ApiUpdate()

    /* WalletConnect Pay */

    @JsonSealedSubtype("walletConnectPayLoading")
    @JsonClass(generateAdapter = true)
    data class ApiUpdateWalletConnectPayLoading(
        val accountId: String
    ) : ApiUpdate()

    @JsonSealedSubtype("walletConnectPayCloseLoading")
    @JsonClass(generateAdapter = true)
    data class ApiUpdateWalletConnectPayCloseLoading(
        val type: String? = null
    ) : ApiUpdate()

    @JsonSealedSubtype("walletConnectPaySignTransaction")
    @JsonClass(generateAdapter = true)
    data class ApiUpdateWalletConnectPaySignTransaction(
        val promiseId: String,
        val accountId: String,
        val merchant: WcPayMerchant,
        val operationChain: String,
        val transactions: List<ApiDappTransfer>,
        val emulation: ApiUpdateDappSendTransactions.Emulation? = null,
        val paymentInfo: WcPayPaymentInfo? = null,
        val paymentOption: WcPayPaymentOption? = null,
        val isSignOnly: Boolean,
        val isLegacyOutput: Boolean? = null,
        val shouldHideTransfers: Boolean? = null,
        val validUntil: Long? = null
    ) : ApiUpdate()

    @JsonSealedSubtype("walletConnectPaySignTransactionComplete")
    @JsonClass(generateAdapter = true)
    data class ApiUpdateWalletConnectPaySignTransactionComplete(
        val accountId: String
    ) : ApiUpdate()

    @JsonSealedSubtype("walletConnectPaySignData")
    @JsonClass(generateAdapter = true)
    data class ApiUpdateWalletConnectPaySignData(
        val promiseId: String,
        val accountId: String,
        val merchant: WcPayMerchant,
        val operationChain: String,
        val payloadToSign: MSignDataPayload,
        val paymentInfo: WcPayPaymentInfo? = null,
        val paymentOption: WcPayPaymentOption? = null
    ) : ApiUpdate()

    @JsonSealedSubtype("walletConnectPaySignDataComplete")
    @JsonClass(generateAdapter = true)
    data class ApiUpdateWalletConnectPaySignDataComplete(
        val accountId: String
    ) : ApiUpdate()

    @JsonSealedSubtype("walletConnectPayDataCollection")
    @JsonClass(generateAdapter = true)
    data class ApiUpdateWalletConnectPayDataCollection(
        val promiseId: String,
        val url: String
    ) : ApiUpdate()

    @JsonSealedSubtype("walletConnectPayDataCollectionComplete")
    @JsonClass(generateAdapter = true)
    data class ApiUpdateWalletConnectPayDataCollectionComplete(
        val type: String? = null
    ) : ApiUpdate()

    @JsonSealedSubtype("walletConnectPayOptionSelection")
    @JsonClass(generateAdapter = true)
    data class ApiUpdateWalletConnectPayOptionSelection(
        val promiseId: String,
        val paymentLink: String,
        val accountId: String,
        val merchant: WcPayMerchant,
        val paymentInfo: WcPayPaymentInfo? = null,
        val options: List<WcPayPaymentOption>,
        val isLoading: Boolean? = null,
        val shouldSwitchWallet: Boolean? = null
    ) : ApiUpdate()

    @JsonSealedSubtype("walletConnectPayOptionSelectionComplete")
    @JsonClass(generateAdapter = true)
    data class ApiUpdateWalletConnectPayOptionSelectionComplete(
        val type: String? = null
    ) : ApiUpdate()

    @JsonSealedSubtype("walletConnectPayProcessing")
    @JsonClass(generateAdapter = true)
    data class ApiUpdateWalletConnectPayProcessing(
        val accountId: String,
        val merchant: WcPayMerchant,
        val operationChain: String
    ) : ApiUpdate()

    @JsonSealedSubtype("walletConnectPayPaymentComplete")
    @JsonClass(generateAdapter = true)
    data class ApiUpdateWalletConnectPayPaymentComplete(
        val accountId: String,
        val merchant: WcPayMerchant,
        val operationChain: String,
        val txId: String? = null,
        val paymentAmount: WcPayAmount? = null
    ) : ApiUpdate()

    // NOTICE: Do NOT forget to add new sub-types to MoshiBuilder file to prevent minification issues.
}
