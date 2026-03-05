package org.mytonwallet.app_air.uisend.sendNft

import android.annotation.SuppressLint
import android.os.Handler
import android.os.Looper
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import kotlinx.coroutines.withTimeoutOrNull
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletcontext.helpers.DNSHelpers
import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.models.MBridgeError
import org.mytonwallet.app_air.walletcore.models.blockchain.MBlockchain
import org.mytonwallet.app_air.walletcore.moshi.ApiNft
import org.mytonwallet.app_air.walletcore.moshi.MApiAnyDisplayError
import org.mytonwallet.app_air.walletcore.moshi.MApiCheckNftDraftOptions
import org.mytonwallet.app_air.walletcore.moshi.MApiCheckTransactionDraftResult
import org.mytonwallet.app_air.walletcore.moshi.api.ApiMethod
import org.mytonwallet.app_air.walletcore.stores.AccountStore
import org.mytonwallet.app_air.walletcore.stores.AddressStore
import java.lang.ref.WeakReference
import java.math.BigInteger

@SuppressLint("ViewConstructor")
class SendNftVM(delegate: Delegate, val nft: ApiNft) {
    interface Delegate {
        fun showError(error: MBridgeError?)
        fun feeUpdated(fee: BigInteger?, err: MBridgeError?)
        fun addressInfoUpdated(info: AddressInfo?)
    }

    data class AddressInfo(
        val chain: MBlockchain,
        val input: String,
        val resolvedAddress: String? = null,
        val addressName: String? = null,
        val isScam: Boolean? = null,
        val error: MApiAnyDisplayError? = null,
    )

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
    var addressInfo: AddressInfo? = null
        private set
    var addressName: String? = null
        private set
    var isScam: Boolean = false
        private set
    var feeValue: BigInteger? = null
        private set
    val delegate: WeakReference<Delegate> = WeakReference(delegate)
    private val vmScope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
    private var addressInfoJob: Job? = null

    fun onInputDestination(destination: String) {
        if (inputAddress == destination) {
            return
        }
        inputAddress = destination
        scheduleFeeRequest()
    }

    fun onInputComment(comment: String) {
        if (inputComment == comment) {
            return
        }
        inputComment = comment
        scheduleFeeRequest()
    }

    private fun scheduleFeeRequest() {
        delegate.get()?.feeUpdated(null, null)
        handler.removeCallbacks(feeRequestRunnable)
        handler.postDelayed(feeRequestRunnable, 1000)
    }

    fun onDestinationEntered(address: String) {
        val destination = address.trim()
        if (destination.isEmpty()) {
            addressInfo = null
            addressInfoJob?.cancel()
            delegate.get()?.addressInfoUpdated(null)
            return
        }

        val chain = nft.chain ?: MBlockchain.ton
        addressInfoJob?.cancel()
        addressInfoJob = vmScope.launch {
            applyAddressInfo(fetchAddressInfo(chain, destination))
        }
    }

    private suspend fun fetchAddressInfo(chain: MBlockchain, destination: String): AddressInfo? {
        val savedName = AddressStore.getSavedAddress(destination, chain.name)
            ?.name
            ?.trim()
            ?.takeIf { it.isNotEmpty() }
        if (savedName != null) {
            return AddressInfo(
                chain = chain,
                input = destination,
                resolvedAddress = destination,
                addressName = savedName,
            )
        }

        val isValid =
            chain.isValidAddress(destination) || (chain == MBlockchain.ton && DNSHelpers.isDnsDomain(destination))
        if (!isValid) {
            return null
        }

        val network = AccountStore.activeAccount?.network ?: return AddressInfo(
            chain = chain,
            input = destination
        )

        return try {
            val result = withTimeoutOrNull(100) {
                WalletCore.call(
                    ApiMethod.WalletData.GetAddressInfo(
                        chain = chain,
                        network = network,
                        addressOrDomain = destination
                    )
                )
            }
            AddressInfo(
                chain = chain,
                input = destination,
                resolvedAddress = result?.resolvedAddress,
                addressName = result?.addressName,
                isScam = result?.isScam,
                error = result?.error,
            )
        } catch (_: Throwable) {
            AddressInfo(chain, destination)
        }
    }

    private fun applyAddressInfo(info: AddressInfo?) {
        addressInfo = info
        delegate.get()?.addressInfoUpdated(info)
    }

    fun onDestroy() {
        handler.removeCallbacks(feeRequestRunnable)
        addressInfoJob?.cancel()
        vmScope.cancel()
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
                addressName = res?.addressName
                isScam = res?.isScam == true
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
