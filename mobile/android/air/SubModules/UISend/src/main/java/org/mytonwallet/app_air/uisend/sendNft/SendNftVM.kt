package org.mytonwallet.app_air.uisend.sendNft

import android.annotation.SuppressLint
import android.os.Handler
import android.os.Looper
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
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

@SuppressLint("ViewConstructor")
class SendNftVM(delegate: Delegate, val nft: ApiNft) {
    interface Delegate {
        fun showError(error: MBridgeError?)
        fun feeUpdated(fee: BigInteger?, err: MBridgeError?)
    }

    // Input values
    var inputAddress: String = ""
        private set
    var inputComment: String = ""
        private set

    // Estimate response
    private val handler = Handler(Looper.getMainLooper())
    private val feeRequestRunnable = Runnable { requestFee() }

    var resolvedAddress: String? = null
        private set
    var feeValue: BigInteger? = null
        private set
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
                nft.chain ?: MBlockchain.ton,
                MApiCheckNftDraftOptions(
                    AccountStore.activeAccountId!!,
                    listOf(nft.toDictionary()),
                    inputAddress,
                    inputComment,
                    false
                )
            ),
            callback = { res, err ->
                resolvedAddress = res?.resolvedAddress
                feeValue = res?.fee
                if (err?.parsed?.errorName == MBridgeError.UNKNOWN.errorName)
                    err?.parsed?.customMessage =
                        LocaleController.getString("Invalid address")
                delegate.get()?.feeUpdated(
                    (res ?: err?.parsedResult as? MApiCheckTransactionDraftResult)?.fee,
                    err?.parsed
                )
            }
        )
    }
}
