package org.mytonwallet.app_air.uisend.sendNft.sendNftConfirm

import org.mytonwallet.app_air.ledger.screens.ledgerConnect.LedgerConnectVC
import org.mytonwallet.app_air.uisend.sendNft.sendNftConfirm.ConfirmNftVC.Mode
import org.mytonwallet.app_air.walletcore.BURN_ADDRESS
import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.models.MBridgeError
import org.mytonwallet.app_air.walletcore.moshi.ApiNft
import org.mytonwallet.app_air.walletcore.moshi.MApiCheckNftDraftOptions
import org.mytonwallet.app_air.walletcore.moshi.MApiCheckTransactionDraftResult
import org.mytonwallet.app_air.walletcore.moshi.api.ApiMethod
import org.mytonwallet.app_air.walletcore.stores.AccountStore
import java.lang.ref.WeakReference
import java.math.BigInteger

class ConfirmNftVM(delegate: Delegate) {
    interface Delegate {
        fun showError(error: MBridgeError?)
        fun feeUpdated(result: MApiCheckTransactionDraftResult?, err: MBridgeError?)
    }

    var resolvedAddress: String? = null
    private var feeValue: BigInteger? = null
    val delegate: WeakReference<Delegate> = WeakReference(delegate)

    fun toAddress(mode: Mode): String {
        return when (mode) {
            is Mode.Burn -> {
                BURN_ADDRESS
            }

            is Mode.Send -> {
                mode.toAddress
            }
        }
    }

    fun requestFee(nft: ApiNft, mode: Mode, comment: String?) {
        WalletCore.call(
            ApiMethod.Nft.CheckNftTransferDraft(
                MApiCheckNftDraftOptions(
                    AccountStore.activeAccountId!!,
                    arrayOf(nft.toDictionary()),
                    toAddress(mode),
                    comment
                )
            ),
            callback = { res, err ->
                resolvedAddress = res?.resolvedAddress
                feeValue = res?.fee
                delegate.get()?.feeUpdated(
                    res ?: err?.parsedResult as? MApiCheckTransactionDraftResult,
                    err?.parsed
                )
            }
        )
    }

    fun submitTransferNft(nft: ApiNft, comment: String?, passcode: String, onSent: () -> Unit) {
        if (resolvedAddress == null)
            return
        WalletCore.call(
            ApiMethod.Nft.SubmitNftTransfer(
                AccountStore.activeAccountId!!,
                passcode,
                nft,
                resolvedAddress!!,
                comment,
                feeValue ?: BigInteger.ZERO
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
        comment: String?
    ): LedgerConnectVC.SignData.SignNftTransfer {
        return LedgerConnectVC.SignData.SignNftTransfer(
            accountId = AccountStore.activeAccountId!!,
            nft = nft,
            toAddress = resolvedAddress!!,
            comment = comment,
            realFee = feeValue
        )
    }
}
