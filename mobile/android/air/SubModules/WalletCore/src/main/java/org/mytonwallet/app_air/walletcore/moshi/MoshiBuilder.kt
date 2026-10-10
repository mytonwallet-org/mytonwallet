package org.mytonwallet.app_air.walletcore.moshi

import com.squareup.moshi.Moshi
import com.squareup.moshi.adapters.PolymorphicJsonAdapterFactory
import com.squareup.moshi.kotlin.reflect.KotlinJsonAdapterFactory
import org.mytonwallet.app_air.walletcore.moshi.adapter.AccountDomainUpdateAdapter
import org.mytonwallet.app_air.walletcore.moshi.adapter.BigDecimalJsonAdapter
import org.mytonwallet.app_air.walletcore.moshi.adapter.BigIntegerJsonAdapter
import org.mytonwallet.app_air.walletcore.moshi.adapter.EnumJsonAdapterFactory
import org.mytonwallet.app_air.walletcore.moshi.adapter.JSONArrayAdapter
import org.mytonwallet.app_air.walletcore.moshi.adapter.JSONObjectAdapter
import org.mytonwallet.app_air.walletcore.moshi.adapter.MfaUpdateAdapter
import org.mytonwallet.app_air.walletcore.moshi.adapter.NftAttributeAdapter
import org.mytonwallet.app_air.walletcore.moshi.adapter.ReturnStrategyAdapter
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2ActionPresentation
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2MessageContent
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2ResolvedAction
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2Update
import org.mytonwallet.app_air.walletcore.moshi.api.ApiUpdate

class MoshiBuilder {
    companion object {
        fun build(): Moshi = Moshi.Builder()
            .add(NftAttributeAdapter())
            .add(BigIntegerJsonAdapter())
            .add(BigDecimalJsonAdapter())
            .add(ReturnStrategyAdapter())
            .add(AccountDomainUpdateAdapter())
            .add(MfaUpdateAdapter())
            .add(EnumJsonAdapterFactory())
            .add(JSONArrayAdapter())
            .add(JSONObjectAdapter())
            .add(
                PolymorphicJsonAdapterFactory.of(StakingState::class.java, "type")
                    .withSubtype(StakingState.Liquid::class.java, "liquid")
                    .withSubtype(StakingState.Jetton::class.java, "jetton")
                    .withSubtype(StakingState.Ethena::class.java, "ethena")
                    .withSubtype(StakingState.Nominators::class.java, "nominators")
                    .withDefaultValue(null)
            )
            .add(
                PolymorphicJsonAdapterFactory.of(MApiTransaction::class.java, "kind")
                    .withSubtype(MApiTransaction.Transaction::class.java, "transaction")
                    .withSubtype(MApiTransaction.Swap::class.java, "swap")
                    .withDefaultValue(null)
            )
            .add(
                PolymorphicJsonAdapterFactory.of(MWalletPermission::class.java, "kind")
                    .withSubtype(MWalletPermission.Approval::class.java, "approval")
                    .withSubtype(MWalletPermission.Delegation::class.java, "delegation")
                    .withDefaultValue(null)
            )
            .add(
                PolymorphicJsonAdapterFactory.of(ApiUpdate::class.java, "type")
                    .withSubtype(ApiUpdate.ApiUpdateAgentV2::class.java, "agentV2")
                    .withSubtype(
                        ApiUpdate.ApiUpdateDappSendTransactions::class.java,
                        "dappSendTransactions"
                    )
                    .withSubtype(
                        ApiUpdate.ApiUpdateDappSignData::class.java,
                        "dappSignData"
                    )
                    .withSubtype(ApiUpdate.ApiUpdateDappConnect::class.java, "dappConnect")
                    .withSubtype(
                        ApiUpdate.ApiUpdateDappDisconnect::class.java,
                        "dappDisconnect"
                    )
                    .withSubtype(ApiUpdate.ApiUpdateDappLoading::class.java, "dappLoading")
                    .withSubtype(
                        ApiUpdate.ApiUpdateDappAlreadyConnected::class.java,
                        "dappAlreadyConnected"
                    )
                    .withSubtype(
                        ApiUpdate.ApiUpdateDappDisconnected::class.java,
                        "dappDisconnected"
                    )
                    .withSubtype(ApiUpdate.ApiUpdateTokens::class.java, "updateTokens")
                    .withSubtype(
                        ApiUpdate.ApiUpdateUpdatingStatus::class.java,
                        "updatingStatus"
                    )
                    .withSubtype(ApiUpdate.ApiUpdateShowError::class.java, "showError")
                    .withSubtype(ApiUpdate.ApiUpdateOpenUrl::class.java, "openUrl")
                    .withSubtype(
                        ApiUpdate.ApiUpdateAccountConfig::class.java,
                        "updateAccountConfig"
                    )
                    .withSubtype(ApiUpdate.ApiUpdateStaking::class.java, "updateStaking")
                    .withSubtype(ApiUpdate.ApiUpdateConfig::class.java, "updateConfig")
                    .withSubtype(ApiUpdate.ApiUpdateNftSent::class.java, "nftSent")
                    .withSubtype(ApiUpdate.ApiUpdateNftReceived::class.java, "nftReceived")
                    .withSubtype(
                        ApiUpdate.ApiUpdateAccountDomainData::class.java,
                        "updateAccountDomainData"
                    )
                    .withSubtype(ApiUpdate.ApiUpdateBalances::class.java, "updateBalances")
                    .withSubtype(
                        ApiUpdate.ApiUpdateNewLocalActivities::class.java,
                        "newLocalActivities"
                    )
                    .withSubtype(ApiUpdate.ApiUpdateNewActivities::class.java, "newActivities")
                    .withSubtype(ApiUpdate.ApiUpdateNfts::class.java, "updateNfts")
                    .withSubtype(
                        ApiUpdate.ApiUpdateDappConnectComplete::class.java,
                        "dappConnectComplete"
                    )
                    .withSubtype(
                        ApiUpdate.ApiUpdateDappCloseLoading::class.java,
                        "dappCloseLoading"
                    )
                    .withSubtype(
                        ApiUpdate.ApiUpdateDappRequestSettled::class.java,
                        "dappRequestSettled"
                    )
                    .withSubtype(ApiUpdate.ApiUpdateDapps::class.java, "updateDapps")
                    .withSubtype(
                        ApiUpdate.ApiUpdateInitialActivities::class.java,
                        "initialActivities"
                    )
                    .withSubtype(
                        ApiUpdate.ApiUpdateWalletVersions::class.java,
                        "updateWalletVersions"
                    )
                    .withSubtype(
                        ApiUpdate.ApiUpdateCurrencyRates::class.java,
                        "updateCurrencyRates"
                    )
                    .withSubtype(
                        ApiUpdate.ApiUpdateUpdateAccount::class.java,
                        "updateAccount"
                    )
                    .withSubtype(
                        ApiUpdate.ApiUpdateWalletConnectPayLoading::class.java,
                        "walletConnectPayLoading"
                    )
                    .withSubtype(
                        ApiUpdate.ApiUpdateWalletConnectPayCloseLoading::class.java,
                        "walletConnectPayCloseLoading"
                    )
                    .withSubtype(
                        ApiUpdate.ApiUpdateWalletConnectPaySignTransaction::class.java,
                        "walletConnectPaySignTransaction"
                    )
                    .withSubtype(
                        ApiUpdate.ApiUpdateWalletConnectPaySignTransactionComplete::class.java,
                        "walletConnectPaySignTransactionComplete"
                    )
                    .withSubtype(
                        ApiUpdate.ApiUpdateWalletConnectPaySignData::class.java,
                        "walletConnectPaySignData"
                    )
                    .withSubtype(
                        ApiUpdate.ApiUpdateWalletConnectPaySignDataComplete::class.java,
                        "walletConnectPaySignDataComplete"
                    )
                    .withSubtype(
                        ApiUpdate.ApiUpdateWalletConnectPayDataCollection::class.java,
                        "walletConnectPayDataCollection"
                    )
                    .withSubtype(
                        ApiUpdate.ApiUpdateWalletConnectPayDataCollectionComplete::class.java,
                        "walletConnectPayDataCollectionComplete"
                    )
                    .withSubtype(
                        ApiUpdate.ApiUpdateWalletConnectPayOptionSelection::class.java,
                        "walletConnectPayOptionSelection"
                    )
                    .withSubtype(
                        ApiUpdate.ApiUpdateWalletConnectPayOptionSelectionComplete::class.java,
                        "walletConnectPayOptionSelectionComplete"
                    )
                    .withSubtype(
                        ApiUpdate.ApiUpdateWalletConnectPayProcessing::class.java,
                        "walletConnectPayProcessing"
                    )
                    .withSubtype(
                        ApiUpdate.ApiUpdateWalletConnectPayPaymentComplete::class.java,
                        "walletConnectPayPaymentComplete"
                    )
                    .withDefaultValue(null)
            )
            .addAgentV2Adapters()
            .add(
                PolymorphicJsonAdapterFactory.of(ApiParsedPayload::class.java, "type")
                    .withSubtype(ApiParsedPayload.ApiCommentPayload::class.java, "comment")
                    .withSubtype(
                        ApiParsedPayload.ApiEncryptedCommentPayload::class.java,
                        "encrypted-comment"
                    )
                    .withSubtype(
                        ApiParsedPayload.ApiNftTransferPayload::class.java,
                        "nft:transfer"
                    )
                    .withSubtype(
                        ApiParsedPayload.ApiNftOwnershipAssignedPayload::class.java,
                        "nft:ownership-assigned"
                    )
                    .withSubtype(
                        ApiParsedPayload.ApiTokensTransferPayload::class.java,
                        "tokens:transfer"
                    )
                    .withSubtype(
                        ApiParsedPayload.ApiTokensTransferNonStandardPayload::class.java,
                        "tokens:transfer-non-standard"
                    )
                    .withSubtype(ApiParsedPayload.ApiUnknownPayload::class.java, "unknown")
                    .withSubtype(
                        ApiParsedPayload.ApiTokensBurnPayload::class.java,
                        "tokens:burn"
                    )
                    .withSubtype(
                        ApiParsedPayload.ApiLiquidStakingDepositPayload::class.java,
                        "liquid-staking:deposit"
                    )
                    .withSubtype(
                        ApiParsedPayload.ApiLiquidStakingWithdrawalNftPayload::class.java,
                        "liquid-staking:withdrawal-nft"
                    )
                    .withSubtype(
                        ApiParsedPayload.ApiLiquidStakingWithdrawalPayload::class.java,
                        "liquid-staking:withdrawal"
                    )
                    .withSubtype(
                        ApiParsedPayload.ApiTokenBridgePaySwap::class.java,
                        "token-bridge:pay-swap"
                    )
                    .withSubtype(
                        ApiParsedPayload.ApiDnsChangeRecord::class.java,
                        "dns:change-record"
                    )
                    .withSubtype(
                        ApiParsedPayload.ApiVestingAddWhitelistPayload::class.java,
                        "vesting:add-whitelist"
                    )
                    .withSubtype(
                        ApiParsedPayload.ApiSingleNominatorWithdrawPayload::class.java,
                        "single-nominator:withdraw"
                    )
                    .withSubtype(
                        ApiParsedPayload.ApiSingleNominatorChangeValidatorPayload::class.java,
                        "single-nominator:change-validator"
                    )
                    .withSubtype(
                        ApiParsedPayload.ApiLiquidStakingVotePayload::class.java,
                        "liquid-staking:vote"
                    )
                    .withDefaultValue(null)
            )
            .add(
                PolymorphicJsonAdapterFactory.of(MSignDataPayload::class.java, "type")
                    .withSubtype(MSignDataPayload.SignDataPayloadText::class.java, "text")
                    .withSubtype(MSignDataPayload.SignDataPayloadBinary::class.java, "binary")
                    .withSubtype(MSignDataPayload.SignDataPayloadCell::class.java, "cell")
                    .withSubtype(MSignDataPayload.SignDataPayloadEip712::class.java, "eip712")
                    .withDefaultValue(null)
            )
            .add(
                PolymorphicJsonAdapterFactory.of(ApiTransferPayload::class.java, "type")
                    .withSubtype(ApiTransferPayload.Comment::class.java, "comment")
                    .withSubtype(ApiTransferPayload.Binary::class.java, "binary")
                    .withSubtype(ApiTransferPayload.Base64::class.java, "base64")
                    .withDefaultValue(null)
            )
            .add(KotlinJsonAdapterFactory())
            .build()
    }
}

internal fun Moshi.Builder.addAgentV2Adapters(): Moshi.Builder = this
    .add(
        PolymorphicJsonAdapterFactory.of(AgentV2MessageContent::class.java, "kind")
            .withSubtype(AgentV2MessageContent.Markdown::class.java, "markdown")
            .withSubtype(AgentV2MessageContent.Semantic::class.java, "semantic")
            .withDefaultValue(null)
    )
    .add(
        PolymorphicJsonAdapterFactory.of(AgentV2ActionPresentation::class.java, "kind")
            .withSubtype(AgentV2ActionPresentation.Send::class.java, "send")
            .withSubtype(AgentV2ActionPresentation.Inactive::class.java, "inactive")
    )
    .add(
        PolymorphicJsonAdapterFactory.of(AgentV2ResolvedAction::class.java, "kind")
            .withSubtype(AgentV2ResolvedAction.OpenReceive::class.java, "openReceive")
            .withSubtype(AgentV2ResolvedAction.OpenStaking::class.java, "openStaking")
            .withSubtype(AgentV2ResolvedAction.OpenSwap::class.java, "openSwap")
            .withSubtype(AgentV2ResolvedAction.SendForm::class.java, "sendForm")
            .withSubtype(AgentV2ResolvedAction.OpenDapp::class.java, "openDapp")
            .withSubtype(AgentV2ResolvedAction.Inactive::class.java, "inactive")
    )
    .add(
        PolymorphicJsonAdapterFactory.of(AgentV2Update::class.java, "kind")
            .withSubtype(AgentV2Update.RunStarted::class.java, "runStarted")
            .withSubtype(AgentV2Update.MessageStarted::class.java, "messageStarted")
            .withSubtype(AgentV2Update.TextDelta::class.java, "textDelta")
            .withSubtype(AgentV2Update.AnswerTablesChanged::class.java, "answerTablesChanged")
            .withSubtype(AgentV2Update.AnswerLinkAdded::class.java, "answerLinkAdded")
            .withSubtype(AgentV2Update.MessageContentEnded::class.java, "messageContentEnded")
            .withSubtype(AgentV2Update.MessageCompleted::class.java, "messageCompleted")
            .withSubtype(AgentV2Update.ActionAvailable::class.java, "actionAvailable")
            .withSubtype(AgentV2Update.FollowupsAvailable::class.java, "followupsAvailable")
            .withSubtype(
                AgentV2Update.SemanticContentAvailable::class.java,
                "semanticContentAvailable"
            )
            .withSubtype(AgentV2Update.RunFailed::class.java, "runFailed")
            .withSubtype(AgentV2Update.RunCancelled::class.java, "runCancelled")
            .withSubtype(
                AgentV2Update.WalletAuthorityChanged::class.java,
                "walletAuthorityChanged"
            )
            .withSubtype(AgentV2Update.ThreadChanged::class.java, "threadChanged")
            .withSubtype(AgentV2Update.RuntimeReady::class.java, "runtimeReady")
            .withDefaultValue(null)
    )
