package org.mytonwallet.app_air.walletcore.moshi.api

import com.squareup.moshi.JsonClass
import com.squareup.moshi.Types
import org.json.JSONArray
import org.json.JSONObject
import org.mytonwallet.app_air.walletcontext.models.MBlockchainNetwork
import org.mytonwallet.app_air.walletcore.api.ArgumentsBuilder
import org.mytonwallet.app_air.walletcore.models.MBlockchain
import org.mytonwallet.app_air.walletcore.moshi.ApiDapp
import org.mytonwallet.app_air.walletcore.moshi.ApiNft
import org.mytonwallet.app_air.walletcore.moshi.ApiNotificationAddress
import org.mytonwallet.app_air.walletcore.moshi.ApiSubmitTransferResult
import org.mytonwallet.app_air.walletcore.moshi.ApiSubmitTransfersResult
import org.mytonwallet.app_air.walletcore.moshi.ApiTonConnectProof
import org.mytonwallet.app_air.walletcore.moshi.ApiTransferToSign
import org.mytonwallet.app_air.walletcore.moshi.DeviceInfo
import org.mytonwallet.app_air.walletcore.moshi.MApiCheckNftDraftOptions
import org.mytonwallet.app_air.walletcore.moshi.MApiCheckStakeDraftResult
import org.mytonwallet.app_air.walletcore.moshi.MApiCheckTransactionDraftOptions
import org.mytonwallet.app_air.walletcore.moshi.MApiCheckTransactionDraftResult
import org.mytonwallet.app_air.walletcore.moshi.MApiLedgerAccountInfo
import org.mytonwallet.app_air.walletcore.moshi.MApiSubmitTransferOptions
import org.mytonwallet.app_air.walletcore.moshi.MApiSwapEstimateRequest
import org.mytonwallet.app_air.walletcore.moshi.MApiSwapEstimateResponse
import org.mytonwallet.app_air.walletcore.moshi.MApiTransaction
import org.mytonwallet.app_air.walletcore.moshi.MImportedViewWalletResponse
import org.mytonwallet.app_air.walletcore.moshi.MImportedWalletResponse
import org.mytonwallet.app_air.walletcore.moshi.MSignDataPayload
import org.mytonwallet.app_air.walletcore.moshi.ReturnStrategy
import org.mytonwallet.app_air.walletcore.moshi.StakingState
import org.mytonwallet.app_air.walletcore.moshi.ledger.MLedgerWalletInfo
import java.lang.reflect.Type
import java.math.BigInteger

sealed class ApiMethod<T> {
    abstract val name: String
    abstract val type: Type
    abstract val arguments: String

    /* Other */
    object Other {
        class SetIsAppFocused(
            isFocused: Boolean
        ) : ApiMethod<Array<String>>() {
            override val name: String = "setIsAppFocused"
            override val type: Type = Any::class.java
            override val arguments: String = ArgumentsBuilder()
                .boolean(isFocused)
                .build()
        }

        class WaitForLedgerApp(chain: MBlockchain, options: Options? = null) :
            ApiMethod<Boolean>() {
            @JsonClass(generateAdapter = true)
            data class Options(
                val timeout: Int? = null,
                val attemptPause: Int? = null
            )

            override val name: String = "waitForLedgerApp"
            override val type: Type = Boolean::class.java
            override val arguments: String = ArgumentsBuilder()
                .string(chain.name)
                .jsObject(options, Options::class.java)
                .build()
        }
    }

    /* Auth */
    object Auth {
        class GenerateMnemonic : ApiMethod<Array<String>>() {
            override val name: String = "generateMnemonic"
            override val type: Type = Array<String>::class.java
            override val arguments: String = ArgumentsBuilder()
                .boolean(true)
                .build()
        }

        class GetLedgerWallets(
            chain: MBlockchain,
            network: MBlockchainNetwork,
            startWalletIndex: Int,
            count: Int
        ) : ApiMethod<Array<MLedgerWalletInfo>>() {
            override val name: String = "getLedgerWallets"
            override val type: Type = Array<MLedgerWalletInfo>::class.java
            override val arguments: String = ArgumentsBuilder()
                .string(chain.name)
                .string(network.value)
                .number(startWalletIndex)
                .number(count)
                .build()
        }

        class ImportLedgerWallet(
            network: MBlockchainNetwork,
            accountInfo: MApiLedgerAccountInfo
        ) : ApiMethod<MImportedWalletResponse>() {
            override val name: String = "importLedgerAccount"
            override val type: Type = MImportedWalletResponse::class.java
            override val arguments: String = ArgumentsBuilder()
                .string(network.value)
                .jsObject(accountInfo, MApiLedgerAccountInfo::class.java)
                .build()
        }

        class ImportViewAccount(
            network: MBlockchainNetwork,
            addressByChain: Map<MBlockchain, String>
        ) : ApiMethod<MImportedViewWalletResponse>() {
            override val name: String = "importViewAccount"
            override val type: Type = MImportedViewWalletResponse::class.java
            override val arguments: String = ArgumentsBuilder()
                .string(network.value)
                .jsonObject(JSONObject().apply {
                    addressByChain.forEach { (chain, address) ->
                        put(chain.name, address)
                    }
                })
                .build()
        }
    }

    /* Wallet Data */
    object WalletData {
        class DecryptComment(
            accountId: String,
            activity: MApiTransaction,
            passcode: String
        ) : ApiMethod<String>() {
            override val name: String = "decryptComment"
            override val type: Type = String::class.java
            override val arguments: String = ArgumentsBuilder()
                .string(accountId)
                .jsObject(activity, MApiTransaction::class.java)
                .string(passcode)
                .build()
        }

        class FetchActivityDetails(
            accountId: String,
            activity: MApiTransaction,
        ) : ApiMethod<MApiTransaction>() {
            override val name: String = "fetchActivityDetails"
            override val type: Type = MApiTransaction::class.java
            override val arguments: String = ArgumentsBuilder()
                .string(accountId)
                .jsObject(activity, MApiTransaction::class.java)
                .build()
        }

        class FetchTransactionById(
            options: Options
        ) : ApiMethod<List<MApiTransaction>>() {

            @JsonClass(generateAdapter = true)
            data class Options(
                val chain: String,
                val network: String,
                val walletAddress: String,
                val txId: String? = null,
                val txHash: String? = null
            )

            override val name: String = "fetchTransactionById"
            override val type: Type =
                Types.newParameterizedType(List::class.java, MApiTransaction::class.java)
            override val arguments: String = ArgumentsBuilder()
                .jsObject(options, Options::class.java)
                .build()
        }
    }

    /* Tokens */
    object Tokens {
        class BuildTokenSlug(
            chain: String,
            address: String,
        ) : ApiMethod<String>() {
            override val name: String = "buildTokenSlug"
            override val type: Type = String::class.java
            override val arguments: String = ArgumentsBuilder()
                .string(chain)
                .string(address)
                .build()
        }
    }

    object Settings {
        class FetchMnemonic(
            accountId: String,
            password: String
        ) : ApiMethod<Array<String>>() {
            override val name: String = "fetchMnemonic"
            override val type: Type = Array<String>::class.java
            override val arguments: String = ArgumentsBuilder()
                .string(accountId)
                .string(password)
                .build()
        }

        class ChangePassword(
            oldPasscode: String,
            newPasscode: String
        ) : ApiMethod<Nothing>() {
            override val name: String = "changePassword"
            override val type: Type = Nothing::class.java
            override val arguments: String = ArgumentsBuilder()
                .string(oldPasscode)
                .string(newPasscode)
                .build()
        }
    }

    /* Transfer */

    object Transfer {
        class CheckTransactionDraft(
            chain: MBlockchain,
            options: MApiCheckTransactionDraftOptions
        ) : ApiMethod<MApiCheckTransactionDraftResult>() {
            override val name: String = "checkTransactionDraft"
            override val type: Type = MApiCheckTransactionDraftResult::class.java
            override val arguments: String = ArgumentsBuilder()
                .string(chain.name)
                .jsObject(options, MApiCheckTransactionDraftOptions::class.java)
                .build()
        }

        class SubmitTransfer(
            chain: MBlockchain,
            options: MApiSubmitTransferOptions
        ) : ApiMethod<ApiSubmitTransferResult>() {
            override val name: String = "submitTransfer"
            override val type: Type = ApiSubmitTransferResult::class.java
            override val arguments: String = ArgumentsBuilder()
                .string(chain.name)
                .jsObject(options, MApiSubmitTransferOptions::class.java)
                .build()
        }

        class SignTransfers(
            accountId: String,
            transactions: List<ApiTransferToSign>,
            options: Options
        ) : ApiMethod<JSONArray>() {

            @JsonClass(generateAdapter = true)
            data class Options(
                val password: String?,
                val validUntil: Long?,
                val vestingAddress: String?
            )

            override val name: String = "signTransfers"
            override val type: Type = JSONArray::class.java
            override val arguments: String = ArgumentsBuilder()
                .string(accountId)
                .jsArray(transactions, ApiTransferToSign::class.java)
                .jsObject(options, Options::class.java)
                .build()
        }

        class SignData(
            accountId: String,
            dappUrl: String,
            payloadToSign: MSignDataPayload,
            password: String,
        ) : ApiMethod<JSONObject>() {

            override val name: String = "signData"
            override val type: Type = JSONObject::class.java
            override val arguments: String = ArgumentsBuilder()
                .string(accountId)
                .string(dappUrl)
                .jsObject(payloadToSign, MSignDataPayload::class.java)
                .string(password)
                .build()
        }
    }


    /* Swap */

    object Swap {
        class SwapEstimate(
            accountId: String,
            request: MApiSwapEstimateRequest
        ) : ApiMethod<MApiSwapEstimateResponse>() {
            override val name: String = "swapEstimate"
            override val type: Type = MApiSwapEstimateResponse::class.java
            override val arguments: String = ArgumentsBuilder()
                .string(accountId)
                .jsObject(request, MApiSwapEstimateRequest::class.java)
                .build()
        }
    }


    /* Ton Connect */

    object DApp {
        class GetDapps(
            accountId: String
        ) : ApiMethod<List<ApiDapp>>() {
            override val name: String = "getDapps"
            override val type: Type =
                Types.newParameterizedType(List::class.java, ApiDapp::class.java)
            override val arguments: String = ArgumentsBuilder()
                .string(accountId)
                .build()
        }

        class StartSseConnection(
            request: Request
        ) : ApiMethod<ReturnStrategy?>() {
            override val name: String = "startSseConnection"
            override val type: Type = ReturnStrategy::class.java
            override val arguments: String = ArgumentsBuilder()
                .jsObject(request, Request::class.java)
                .build()

            @JsonClass(generateAdapter = true)
            data class Request(
                val url: String,
                val deviceInfo: DeviceInfo,
                val isFromInAppBrowser: Boolean? = null,
                val identifier: String? = null
            )
        }

        class ConfirmDappRequestSendTransaction(
            promiseId: String,
            signedMessages: JSONArray
        ) : ApiMethod<Unit>() {
            override val name: String = "confirmDappRequestSendTransaction"
            override val type: Type = Unit::class.java
            override val arguments: String = ArgumentsBuilder()
                .string(promiseId)
                .jsObject(signedMessages, JSONArray::class.java)
                .build()
        }

        class ConfirmDappRequestSignData(
            promiseId: String,
            signedData: JSONObject
        ) : ApiMethod<Unit>() {
            override val name: String = "confirmDappRequestSignData"
            override val type: Type = Unit::class.java
            override val arguments: String = ArgumentsBuilder()
                .string(promiseId)
                .jsObject(signedData, JSONObject::class.java)
                .build()
        }

        class SignTonProof(
            accountId: String,
            proofData: ApiTonConnectProof?,
            password: String
        ) : ApiMethod<SignTonProof.Result>() {

            @JsonClass(generateAdapter = true)
            data class Result(val signature: String)

            override val name: String = "signTonProof"
            override val type: Type = Result::class.java
            override val arguments: String = ArgumentsBuilder()
                .string(accountId)
                .jsObject(proofData, ApiTonConnectProof::class.java)
                .string(password)
                .build()
        }

        class ConfirmDappRequestConnect(
            promiseId: String,
            request: Request
        ) : ApiMethod<Unit>() {
            override val name: String = "confirmDappRequestConnect"
            override val type: Type = Unit::class.java
            override val arguments: String = ArgumentsBuilder()
                .string(promiseId)
                .jsObject(request, Request::class.java)
                .build()

            @JsonClass(generateAdapter = true)
            data class Request(
                val accountId: String? = null,
                val proofSignature: String? = null
            )
        }

        class CancelDappRequest(
            promiseId: String,
            reason: String?
        ) : ApiMethod<Unit>() {
            override val name: String = "cancelDappRequest"
            override val type: Type = Unit::class.java
            override val arguments: String = ArgumentsBuilder()
                .string(promiseId)
                .apply { reason?.let { string(it) } }
                .build()
        }

        class DeleteDapp(
            accountId: String,
            appClientId: String,
            origin: String
        ) : ApiMethod<Any>() {
            override val name: String = "deleteDapp"
            override val type: Type = Any::class.java
            override val arguments: String = ArgumentsBuilder()
                .string(accountId)
                .string(origin)
                .string(appClientId)
                .string(null)
                .build()
        }

        class DeleteAllDapps(
            accountId: String
        ) : ApiMethod<Boolean>() {
            override val name: String = "deleteAllDapps"
            override val type: Type = Boolean::class.java
            override val arguments: String = ArgumentsBuilder()
                .string(accountId)
                .build()
        }


        object Inject {
            @JsonClass(generateAdapter = true)
            data class DAppArg(
                val url: String,
                val isUrlEnsured: Boolean,
                var accountId: String,
            )

            class TonConnectConnect(
                dApp: DAppArg,
                request: Any,
                requestId: Int
            ) : ApiMethod<JSONObject>() {
                override val name: String = "tonConnect_connect"
                override val type: Type = JSONObject::class.java
                override val arguments: String = ArgumentsBuilder()
                    .jsObject(dApp, DAppArg::class.java)
                    .jsObject(request, Any::class.java)
                    .number(requestId)
                    .build()
            }

            class TonConnectReconnect(
                dApp: DAppArg,
                requestId: Int
            ) : ApiMethod<JSONObject>() {
                override val name: String = "tonConnect_reconnect"
                override val type: Type = JSONObject::class.java
                override val arguments: String = ArgumentsBuilder()
                    .jsObject(dApp, DAppArg::class.java)
                    .number(requestId)
                    .build()
            }

            class TonConnectDisconnect(
                dApp: DAppArg,
                request: Request
            ) : ApiMethod<JSONObject>() {
                override val name: String = "tonConnect_disconnect"
                override val type: Type = JSONObject::class.java
                override val arguments: String = ArgumentsBuilder()
                    .jsObject(dApp, DAppArg::class.java)
                    .jsObject(request, Request::class.java)
                    .build()

                @JsonClass(generateAdapter = true)
                data class Request(
                    val method: String = "disconnect",
                    val params: List<Any> = emptyList(),
                    val id: String
                )
            }

            class TonConnectSendTransaction(
                dApp: DAppArg,
                request: Request
            ) : ApiMethod<JSONObject>() {
                override val name: String = "tonConnect_sendTransaction"
                override val type: Type = JSONObject::class.java
                override val arguments: String = ArgumentsBuilder()
                    .jsObject(dApp, DAppArg::class.java)
                    .jsObject(request, Request::class.java)
                    .build()

                @JsonClass(generateAdapter = true)
                data class Request(
                    val method: String,
                    val params: List<String>,
                    val id: String
                )
            }

            class TonConnectSignData(
                dApp: DAppArg,
                request: TonConnectSendTransaction.Request
            ) : ApiMethod<JSONObject>() {
                override val name: String = "tonConnect_signData"
                override val type: Type = JSONObject::class.java
                override val arguments: String = ArgumentsBuilder()
                    .jsObject(dApp, DAppArg::class.java)
                    .jsObject(request, TonConnectSendTransaction.Request::class.java)
                    .build()
            }
        }
    }

    /* Domains */
    object Domains {
        class CheckDnsRenewalDraft(accountId: String, nfts: List<ApiNft>) :
            ApiMethod<CheckDnsRenewalDraft.Result>() {

            @JsonClass(generateAdapter = true)
            data class Result(val realFee: BigInteger)

            override val name: String = "checkDnsRenewalDraft"
            override val type: Type = Result::class.java
            override val arguments: String = ArgumentsBuilder()
                .string(accountId)
                .jsArray(nfts, ApiNft::class.java)
                .build()
        }

        class SubmitDnsRenewal(
            accountId: String,
            password: String,
            nfts: List<ApiNft>,
            realFee: BigInteger
        ) : ApiMethod<Any>() {
            override val name: String = "submitDnsRenewal"
            override val type: Type = Any::class.java
            override val arguments: String = ArgumentsBuilder()
                .string(accountId)
                .string(password)
                .jsArray(nfts, ApiNft::class.java)
                .bigInt(realFee)
                .build()
        }

        class CheckDnsChangeWalletDraft(
            accountId: String,
            nft: ApiNft,
            address: String
        ) : ApiMethod<CheckDnsChangeWalletDraft.Result>() {

            @JsonClass(generateAdapter = true)
            data class Result(val realFee: BigInteger)

            override val name: String = "checkDnsChangeWalletDraft"
            override val type: Type = Result::class.java
            override val arguments: String = ArgumentsBuilder()
                .string(accountId)
                .jsObject(nft, ApiNft::class.java)
                .string(address)
                .build()
        }

        class SubmitDnsChangeWallet(
            accountId: String,
            password: String,
            nft: ApiNft,
            address: String,
            realFee: BigInteger,
        ) : ApiMethod<Any>() {

            override val name: String = "submitDnsChangeWallet"
            override val type: Type = Any::class.java
            override val arguments: String = ArgumentsBuilder()
                .string(accountId)
                .string(password)
                .jsObject(nft, ApiNft::class.java)
                .string(address)
                .bigInt(realFee)
                .build()
        }
    }

    /* Nft */
    object Nft {
        class CheckNftTransferDraft(
            options: MApiCheckNftDraftOptions
        ) : ApiMethod<MApiCheckTransactionDraftResult>() {
            override val name: String = "checkNftTransferDraft"
            override val type: Type = MApiCheckTransactionDraftResult::class.java
            override val arguments: String = ArgumentsBuilder()
                .jsObject(options, MApiCheckNftDraftOptions::class.java)
                .build()
        }

        class SubmitNftTransfer(
            accountId: String,
            passcode: String,
            nft: ApiNft,
            address: String,
            comment: String?,
            fee: BigInteger
        ) : ApiMethod<ApiSubmitTransfersResult>() {
            override val name: String = "submitNftTransfers"
            override val type: Type = ApiSubmitTransfersResult::class.java
            override val arguments: String = ArgumentsBuilder()
                .string(accountId)
                .string(passcode)
                .jsObject(arrayOf(nft.toDictionary()), Array<JSONObject>::class.java)
                .string(address)
                .string(comment)
                .bigInt(fee)
                .build()
        }

        class CheckNftOwnership(
            accountId: String,
            nftAddress: String,
        ) : ApiMethod<Any>() {
            override val name: String = "checkNftOwnership"
            override val type: Type = Boolean::class.java
            override val arguments: String = ArgumentsBuilder()
                .string(accountId)
                .string(nftAddress)
                .build()
        }

        class FetchNftsFromCollection(
            accountId: String,
            collectionAddress: String,
        ) : ApiMethod<Any>() {
            override val name: String = "fetchNftsFromCollection"
            override val type: Type = Boolean::class.java
            override val arguments: String = ArgumentsBuilder()
                .string(accountId)
                .string(collectionAddress)
                .build()
        }
    }

    /* Staking */
    object Staking {
        class CheckStakeDraft(
            accountId: String,
            amount: BigInteger,
            state: StakingState
        ) : ApiMethod<MApiCheckStakeDraftResult>() {
            override val name: String = "checkStakeDraft"
            override val type: Type = MApiCheckStakeDraftResult::class.java
            override val arguments: String = ArgumentsBuilder()
                .string(accountId)
                .bigInt(amount)
                .jsObject(state, StakingState::class.java)
                .build()
        }

        class CheckUnstakeDraft(
            accountId: String,
            amount: BigInteger,
            state: StakingState
        ) : ApiMethod<MApiCheckStakeDraftResult>() {
            override val name: String = "checkUnstakeDraft"
            override val type: Type = MApiCheckStakeDraftResult::class.java
            override val arguments: String = ArgumentsBuilder()
                .string(accountId)
                .bigInt(amount)
                .jsObject(state, StakingState::class.java)
                .build()
        }

        class SubmitStakingClaimOrUnlock(
            accountId: String,
            password: String,
            state: StakingState,
            realFee: BigInteger
        ) : ApiMethod<Any>() {
            override val name: String = "submitStakingClaimOrUnlock"
            override val type: Type = Any::class.java
            override val arguments: String = ArgumentsBuilder()
                .string(accountId)
                .string(password)
                .jsObject(state, StakingState::class.java)
                .bigInt(realFee)
                .build()
        }
    }

    /* Notifications */
    object Notifications {
        class SubscribeNotifications(props: Props) : ApiMethod<JSONObject>() {

            @JsonClass(generateAdapter = true)
            data class Props(
                val userToken: String,
                val addresses: List<ApiNotificationAddress>,
                val platform: String = "android",
            )

            override val name: String = "subscribeNotifications"
            override val type: Type = JSONObject::class.java
            override val arguments: String = ArgumentsBuilder()
                .jsObject(props, Props::class.java)
                .build()
        }

        class UnsubscribeNotifications(props: Props) : ApiMethod<Any>() {

            @JsonClass(generateAdapter = true)
            data class Props(
                val userToken: String,
                val addresses: List<ApiNotificationAddress>
            )

            override val name: String = "unsubscribeNotifications"
            override val type: Type = Any::class.java
            override val arguments: String = ArgumentsBuilder()
                .jsObject(props, Props::class.java)
                .build()
        }
    }
}
