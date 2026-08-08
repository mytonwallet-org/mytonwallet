package org.mytonwallet.app_air.uitonconnect.viewControllers.send.adapter

import org.mytonwallet.app_air.uicomponents.adapter.BaseListItem
import org.mytonwallet.app_air.walletcore.moshi.IApiToken
import org.mytonwallet.app_air.walletcore.moshi.api.ApiUpdate
import org.mytonwallet.app_air.walletcore.moshi.explainedFee.IExplainedFee

sealed class TonConnectItem(type: Type, key: String? = null) : BaseListItem(type.value, key) {
    enum class Type {
        AMOUNT,
        ADDRESS,
        SEND_HEADER,
        PREVIEW_FEE;

        val value: Int
            get() = this.ordinal
    }

    data class CurrencyAmount(val text: CharSequence) : TonConnectItem(Type.AMOUNT, text.toString())

    data class Address(
        val accountId: String,
        val chain: String,
        val address: String,
        val addressName: String? = null
    ) : TonConnectItem(Type.ADDRESS, "${accountId}_${chain}_$address")

    data class SendRequestHeader(
        val update: ApiUpdate.ApiUpdateDappSignRequest,
        val onShowUnverifiedSourceWarning: () -> Unit
    ) : TonConnectItem(Type.SEND_HEADER, update.dapp.url)

    data class PreviewFee(
        val text: CharSequence,
        val token: IApiToken,
        val feeDetails: IExplainedFee?
    ) : TonConnectItem(Type.PREVIEW_FEE, text.toString())
}
