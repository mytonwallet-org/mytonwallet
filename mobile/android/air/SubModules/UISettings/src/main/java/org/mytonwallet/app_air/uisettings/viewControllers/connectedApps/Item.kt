package org.mytonwallet.app_air.uisettings.viewControllers.connectedApps

import org.mytonwallet.app_air.uicomponents.adapter.BaseListItem
import org.mytonwallet.app_air.walletcore.moshi.ApiDapp

sealed class Item(
    type: Int,
    key: String? = null
) : BaseListItem(type, key) {
    enum class Type {
        HEADER,
        DAPP;

        val value: Int
            get() = this.ordinal
    }

    data class DApp(
        val app: ApiDapp,
        val isLastItem: Boolean
    ) : Item(Type.DAPP.value, app.manifestUrl)

    data class Header(val walletName: String) : Item(Type.HEADER.value)
}
