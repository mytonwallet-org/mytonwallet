package org.mytonwallet.app_air.uisend.sendNft.sendNftConfirm

import java.lang.ref.WeakReference
import java.math.BigInteger
import org.mytonwallet.app_air.ledger.screens.ledgerConnect.LedgerConnectVC
import org.mytonwallet.app_air.uisend.sendNft.sendNftConfirm.ConfirmNftVC.Mode
import org.mytonwallet.app_air.walletbasecontext.logger.Logger
import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.models.MBridgeError
import org.mytonwallet.app_air.walletcore.models.blockchain.MBlockchain
import org.mytonwallet.app_air.walletcore.moshi.ApiNft
import org.mytonwallet.app_air.walletcore.moshi.MApiCheckNftDraftOptions
import org.mytonwallet.app_air.walletcore.moshi.MApiCheckTransactionDraftResult
import org.mytonwallet.app_air.walletcore.moshi.api.ApiMethod
import org.mytonwallet.app_air.walletcore.stores.AccountStore

class ConfirmNftVM(mode: Mode, delegate: Delegate) {
    interface Delegate {
        fun showError(error: MBridgeError?)
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
            if (err != null) {
                delegate.get()?.showError(err.parsed)
            } else {
                val mfaHash = result?.mfaRequestHash
                if (mfaHash != null) {
                    onMfaRequested(mfaHash)
                } else {
                    onSent()
                }
            }
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
