package org.mytonwallet.app_air.uisend.sendNft.sendNftConfirm

import org.mytonwallet.app_air.ledger.screens.ledgerConnect.LedgerConnectVC
import org.mytonwallet.app_air.uisend.sendNft.sendNftConfirm.ConfirmNftVC.Mode
import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.models.MBridgeError
import org.mytonwallet.app_air.walletcore.models.blockchain.MBlockchain
import org.mytonwallet.app_air.walletcore.moshi.ApiNft
import org.mytonwallet.app_air.walletcore.moshi.MApiCheckNftDraftOptions
import org.mytonwallet.app_air.walletcore.moshi.MApiCheckTransactionDraftResult
import org.mytonwallet.app_air.walletcore.moshi.api.ApiMethod
import org.mytonwallet.app_air.walletcore.stores.AccountStore
import java.lang.ref.WeakReference
import java.math.BigInteger

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

    fun requestFee(nft: ApiNft, isNftBurn: Boolean, comment: String?) {
        WalletCore.call(
            ApiMethod.Nft.CheckNftTransferDraft(
                nft.chain ?: MBlockchain.ton,
                MApiCheckNftDraftOptions(
                    AccountStore.activeAccountId!!,
                    listOf(nft.toDictionary()),
                    toAddress,
                    comment,
                    isNftBurn
                )
            ),
            callback = { res, err ->
                resolvedAddress = res?.resolvedAddress
                feeValue = res?.fee
                delegate.get()?.feeUpdated(
                    (res ?: err?.parsedResult as? MApiCheckTransactionDraftResult)?.fee,
                    err?.parsed
                )
            }
        )
    }

    fun submitTransferNft(nft: ApiNft, isNftBurn: Boolean, comment: String?, passcode: String, onSent: () -> Unit) {
        if (resolvedAddress == null)
            return
        WalletCore.call(
            ApiMethod.Nft.SubmitNftTransfer(
                chain = nft.chain ?: MBlockchain.ton,
                accountId = AccountStore.activeAccountId!!,
                passcode = passcode,
                nft = nft,
                address = resolvedAddress!!,
                comment = comment,
                fee = feeValue ?: BigInteger.ZERO,
                isNftBurn = isNftBurn
            )
        ) { _, err ->
            if (err != null) {
                delegate.get()?.showError(err.parsed)
            } else {
                onSent()
            }
        }
    }

    fun signNftTransferData(
        nft: ApiNft,
        isNftBurn: Boolean,
        comment: String?
    ): LedgerConnectVC.SignData.SignNftTransfer {
        return LedgerConnectVC.SignData.SignNftTransfer(
            accountId = AccountStore.activeAccountId!!,
            nft = nft,
            toAddress = resolvedAddress!!,
            comment = comment,
            realFee = feeValue,
            isNftBurn = isNftBurn
        )
    }
}
