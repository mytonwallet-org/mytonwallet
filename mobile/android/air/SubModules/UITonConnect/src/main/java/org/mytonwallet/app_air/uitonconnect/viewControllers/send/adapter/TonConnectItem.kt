package org.mytonwallet.app_air.uitonconnect.viewControllers.send.adapter

import org.mytonwallet.app_air.uicomponents.adapter.BaseListItem
import org.mytonwallet.app_air.walletcore.moshi.api.ApiUpdate

sealed class TonConnectItem(
    type: Type,
    key: String? = null
) : BaseListItem(type.value, key) {
    enum class Type {
        AMOUNT,
        SEND_HEADER;

        val value: Int
            get() = this.ordinal
    }

    data class CurrencyAmount(
        val text: CharSequence
    ) : TonConnectItem(Type.AMOUNT, text.toString())

    data class SendRequestHeader(
        val update: ApiUpdate.ApiUpdateDappSignRequest,
        val onShowUnverifiedSourceWarning: () -> Unit
    ) : TonConnectItem(Type.SEND_HEADER, update.dapp.url)
}
