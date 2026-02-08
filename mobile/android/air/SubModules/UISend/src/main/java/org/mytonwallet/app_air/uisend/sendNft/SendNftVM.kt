package org.mytonwallet.app_air.uisend.sendNft

import android.annotation.SuppressLint
import android.os.Handler
import android.os.Looper
import org.mytonwallet.app_air.ledger.screens.ledgerConnect.LedgerConnectVC
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.models.MBridgeError
import org.mytonwallet.app_air.walletcore.moshi.ApiNft
import org.mytonwallet.app_air.walletcore.moshi.MApiCheckNftDraftOptions
import org.mytonwallet.app_air.walletcore.moshi.MApiCheckTransactionDraftResult
import org.mytonwallet.app_air.walletcore.moshi.api.ApiMethod
import org.mytonwallet.app_air.walletcore.stores.AccountStore
import java.lang.ref.WeakReference
import java.math.BigInteger

@SuppressLint("ViewConstructor")
class SendNftVM(delegate: Delegate, val nft: ApiNft) {
    interface Delegate {
        fun showError(error: MBridgeError?)
        fun feeUpdated(result: MApiCheckTransactionDraftResult?, err: MBridgeError?)
    }

    // Input values
    private var inputAddress: String = ""
    private var inputComment: String = ""

    // Estimate response
    private val handler = Handler(Looper.getMainLooper())
    private val feeRequestRunnable = Runnable { requestFee() }

    var resolvedAddress: String? = null
    private var feeValue: BigInteger? = null
    val delegate: WeakReference<Delegate> = WeakReference(delegate)

    fun inputChanged(address: String? = null, comment: String? = null) {
        address?.let {
            inputAddress = it
        }
        comment?.let {
            inputComment = it
        }
        delegate.get()?.feeUpdated(null, null)
        handler.removeCallbacks(feeRequestRunnable)
        handler.postDelayed(feeRequestRunnable, 1000)
    }

    private fun requestFee() {
        delegate.get()?.feeUpdated(null, null)
        WalletCore.call(
            ApiMethod.Nft.CheckNftTransferDraft(
                MApiCheckNftDraftOptions(
                    AccountStore.activeAccountId!!,
                    arrayOf(nft.toDictionary()),
                    inputAddress,
                    inputComment
                )
            ),
            callback = { res, err ->
                resolvedAddress = res?.resolvedAddress
                feeValue = res?.fee
                if (err?.parsed?.errorName == MBridgeError.UNKNOWN.errorName)
                    err?.parsed?.customMessage =
                        LocaleController.getString("Invalid address")
                delegate.get()?.feeUpdated(
                    res ?: err?.parsedResult as? MApiCheckTransactionDraftResult,
                    err?.parsed
                )
            }
        )
    }

    fun submitTransferNft(nft: ApiNft, passcode: String, onSent: () -> Unit) {
        if (resolvedAddress == null)
            return
        WalletCore.call(
            ApiMethod.Nft.SubmitNftTransfer(
                AccountStore.activeAccountId!!,
                passcode,
                nft,
                resolvedAddress!!,
                inputComment,
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

    fun signNftTransferData(): LedgerConnectVC.SignData.SignNftTransfer {
        return LedgerConnectVC.SignData.SignNftTransfer(
            accountId = AccountStore.activeAccountId!!,
            nft = nft,
            toAddress = resolvedAddress!!,
            comment = inputComment,
            realFee = feeValue
        )
    }
}
