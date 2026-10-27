package org.mytonwallet.app_air.uisend.sendNft.sendNftConfirm

import java.lang.ref.WeakReference
import java.math.BigInteger
import org.mytonwallet.app_air.ledger.screens.ledgerConnect.LedgerConnectVC
import org.mytonwallet.app_air.uisend.sendNft.sendNftConfirm.ConfirmNftVC.Mode
import org.mytonwallet.app_air.walletbasecontext.logger.Logger
import org.mytonwallet.app_air.walletcore.JSWebViewBridge
import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.models.MBridgeError
import org.mytonwallet.app_air.walletcore.models.blockchain.MBlockchain
import org.mytonwallet.app_air.walletcore.moshi.ApiNft
import org.mytonwallet.app_air.walletcore.moshi.ApiSubmitTransfersResult
import org.mytonwallet.app_air.walletcore.moshi.MApiCheckNftDraftOptions
import org.mytonwallet.app_air.walletcore.moshi.MApiCheckTransactionDraftResult
import org.mytonwallet.app_air.walletcore.moshi.api.ApiMethod
import org.mytonwallet.app_air.walletcore.stores.AccountStore

class ConfirmNftVM(mode: Mode, delegate: Delegate) {
    interface Delegate {
        fun showError(error: MBridgeError?)
        fun showPartialFailure(completedCount: Int, totalCount: Int)
        fun feeUpdated(fee: BigInteger?, err: MBridgeError?)
    }

    var toAddress: String
    var resolvedAddress: String? = null
    private var feeValue: BigInteger? = null

    init {
        when (mode) {
            is Mode.Burn -> {
                toAddress = mode.chain.burnAddress
            }

            is Mode.Send -> {
                toAddress = mode.toAddress
                resolvedAddress = mode.resolvedAddress
                feeValue = mode.fee
            }
        }
    }

    val delegate: WeakReference<Delegate> = WeakReference(delegate)

    fun requestFee(nfts: List<ApiNft>, isNftBurn: Boolean, comment: String?) {
        val accountId = AccountStore.activeAccountId ?: run {
            Logger.e(
                Logger.LogTag.SEND,
                "NFT confirmation fee request blocked: active account is missing"
            )
            delegate.get()?.showError(null)
            return
        }
        WalletCore.call(
            ApiMethod.Nft.CheckNftTransferDraft(
                nfts.first().chain ?: MBlockchain.ton,
                MApiCheckNftDraftOptions(
                    accountId,
                    nfts.map { it.toDictionary() },
                    toAddress,
                    comment,
                    isNftBurn
                )
            ),
            callback = { res, err ->
                resolvedAddress = res?.resolvedAddress
                feeValue = res?.realNativeFee
                delegate.get()?.feeUpdated(
                    (res ?: err?.parsedResult as? MApiCheckTransactionDraftResult)?.realNativeFee,
                    err?.parsed
                )
            }
        )
    }

    fun submitTransferNft(
        nfts: List<ApiNft>,
        isNftBurn: Boolean,
        comment: String?,
        enclaveToken: String,
        onSent: () -> Unit,
        onMfaRequested: (String) -> Unit = {}
    ) {
        val accountId = AccountStore.activeAccountId ?: run {
            Logger.e(Logger.LogTag.SEND, "NFT submission blocked: active account is missing")
            delegate.get()?.showError(null)
            return
        }
        val destination = resolvedAddress ?: run {
            Logger.e(Logger.LogTag.SEND, "NFT submission blocked: resolved destination is missing")
            delegate.get()?.showError(null)
            return
        }
        WalletCore.call(
            ApiMethod.Nft.SubmitNftTransfer(
                chain = nfts.first().chain ?: MBlockchain.ton,
                accountId = accountId,
                enclaveToken = enclaveToken,
                nfts = nfts,
                address = destination,
                comment = comment,
                fee = feeValue ?: BigInteger.ZERO,
                isNftBurn = isNftBurn
            )
        ) { result, err ->
            handleSubmitResult(result, err, nfts.size, onSent, onMfaRequested)
        }
    }

    internal fun handleSubmitResult(
        result: ApiSubmitTransfersResult?,
        err: JSWebViewBridge.ApiError?,
        totalCount: Int,
        onSent: () -> Unit,
        onMfaRequested: (String) -> Unit
    ) {
        val response = result ?: err?.parsedResult as? ApiSubmitTransfersResult
        val error = err?.parsed ?: response?.error?.let {
            MBridgeError.fromErrorName(it) ?: MBridgeError.Type.UNEXPECTED_ERROR
        }
        val mfaHash = response?.mfaRequestHash
        if (error != null) {
            val completedCount = response?.activityIds?.size ?: 0
            if (completedCount > 0) {
                delegate.get()?.showPartialFailure(completedCount, totalCount)
            } else {
                delegate.get()?.showError(error)
            }
        } else if (err != null || response == null) {
            delegate.get()?.showError(null)
        } else if (mfaHash != null) {
            onMfaRequested(mfaHash)
        } else if (response.activityIds.isNullOrEmpty()) {
            delegate.get()?.showError(MBridgeError.Type.UNEXPECTED_ERROR)
        } else {
            onSent()
        }
    }

    fun signNftTransferData(
        nfts: List<ApiNft>,
        isNftBurn: Boolean,
        comment: String?
    ): LedgerConnectVC.SignData.SignNftTransfer? {
        val accountId = AccountStore.activeAccountId ?: return null
        val destination = resolvedAddress ?: return null
        return LedgerConnectVC.SignData.SignNftTransfer(
            accountId = accountId,
            nfts = nfts,
            toAddress = destination,
            comment = comment,
            realFee = feeValue,
            isNftBurn = isNftBurn
        )
    }
}
