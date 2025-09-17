package org.mytonwallet.app_air.walletcore.moshi

import com.squareup.moshi.Moshi
import com.squareup.moshi.adapters.PolymorphicJsonAdapterFactory
import com.squareup.moshi.kotlin.reflect.KotlinJsonAdapterFactory
import org.mytonwallet.app_air.walletcore.moshi.adapter.BigDecimalJsonAdapter
import org.mytonwallet.app_air.walletcore.moshi.adapter.BigIntegerJsonAdapter
import org.mytonwallet.app_air.walletcore.moshi.adapter.JSONArrayAdapter
import org.mytonwallet.app_air.walletcore.moshi.adapter.JSONObjectAdapter
import org.mytonwallet.app_air.walletcore.moshi.adapter.ReturnStrategyAdapter
import org.mytonwallet.app_air.walletcore.moshi.adapter.factory.EnumJsonAdapterFactory
import org.mytonwallet.app_air.walletcore.moshi.adapter.factory.SealedJsonAdapterFactory
import org.mytonwallet.app_air.walletcore.moshi.api.ApiUpdate

class MoshiBuilder {
    companion object {
        fun build(): Moshi {
            return Moshi.Builder()
                .add(BigIntegerJsonAdapter())
                .add(BigDecimalJsonAdapter())
                .add(SealedJsonAdapterFactory())
                .add(ReturnStrategyAdapter())
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
                    PolymorphicJsonAdapterFactory.of(ApiUpdate::class.java, "type")
                        .withSubtype(
                            ApiUpdate.ApiUpdateDappSendTransactions::class.java,
                            "dappSendTransactions"
                        )
                        .withSubtype(ApiUpdate.ApiUpdateDappConnect::class.java, "dappConnect")
                        .withSubtype(
                            ApiUpdate.ApiUpdateDappDisconnect::class.java,
                            "dappDisconnect"
                        )
                        .withSubtype(ApiUpdate.ApiUpdateDappLoading::class.java, "dappLoading")
                        .withSubtype(ApiUpdate.ApiUpdateTokens::class.java, "updateTokens")
                        .withSubtype(
                            ApiUpdate.ApiUpdateDappConnectComplete::class.java,
                            "dappConnectComplete"
                        )
                        .withSubtype(
                            ApiUpdate.ApiUpdateDappCloseLoading::class.java,
                            "dappCloseLoading"
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
                        .withDefaultValue(null)
                )
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
                .add(KotlinJsonAdapterFactory())
                .build()
        }
    }
}
