package org.mytonwallet.app_air.walletcontext.models

enum class MToolbarItem(val value: String) {
    SEARCH("search"),
    ACCOUNTS("accounts"),
    SCAN("scan"),
    ACTIONS("actions"),
    BUY("buy"),
    FUND("fund"),
    TRADE("trade"),
    SELL("sell"),
    SEND("send"),
    EARN("earn");

    val isHideable: Boolean
        get() = this != SEARCH && this != ACTIONS

    val isAction: Boolean
        get() = this in ACTION_ITEMS

    companion object {
        val ACTION_ITEMS = listOf(BUY, FUND, TRADE, SELL, SEND, EARN, SCAN)

        fun fromValue(value: String?): MToolbarItem? = entries.firstOrNull { it.value == value }
    }
}
