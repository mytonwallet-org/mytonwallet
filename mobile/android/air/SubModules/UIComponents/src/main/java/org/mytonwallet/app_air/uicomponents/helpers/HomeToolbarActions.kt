package org.mytonwallet.app_air.uicomponents.helpers

import org.mytonwallet.app_air.icons.R
import org.mytonwallet.app_air.uicomponents.commonViews.HeaderActionsView
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletcontext.models.MToolbarItem
import org.mytonwallet.app_air.walletcore.models.MAccount

object HomeToolbarActions {
    fun getIdentifier(item: MToolbarItem): HeaderActionsView.Identifier = when (item) {
        MToolbarItem.BUY -> HeaderActionsView.Identifier.BUY

        MToolbarItem.FUND -> HeaderActionsView.Identifier.RECEIVE

        MToolbarItem.TRADE -> HeaderActionsView.Identifier.SWAP

        MToolbarItem.SELL -> HeaderActionsView.Identifier.SELL

        MToolbarItem.SEND -> HeaderActionsView.Identifier.SEND

        MToolbarItem.EARN -> HeaderActionsView.Identifier.EARN

        MToolbarItem.SCAN -> HeaderActionsView.Identifier.SCAN_QR

        MToolbarItem.SEARCH, MToolbarItem.ACCOUNTS, MToolbarItem.ACTIONS ->
            throw IllegalArgumentException("$item is not an action")
    }

    fun getTitle(item: MToolbarItem): String = LocaleController.getString(
        when (item) {
            MToolbarItem.BUY -> "Buy"

            MToolbarItem.FUND -> "Fund"

            MToolbarItem.TRADE -> "Trade"

            MToolbarItem.SELL -> "Sell"

            MToolbarItem.SEND -> "Send"

            MToolbarItem.EARN -> "Earn"

            MToolbarItem.SCAN -> "Scan"

            MToolbarItem.SEARCH, MToolbarItem.ACCOUNTS, MToolbarItem.ACTIONS ->
                throw IllegalArgumentException("$item is not an action")
        }
    )

    fun getIconRes(item: MToolbarItem): Int = when (item) {
        MToolbarItem.BUY -> R.drawable.ic_action_buy

        MToolbarItem.FUND -> R.drawable.ic_action_fund

        MToolbarItem.TRADE -> R.drawable.ic_action_trade

        MToolbarItem.SELL -> R.drawable.ic_action_sell

        MToolbarItem.SEND -> R.drawable.ic_action_send

        MToolbarItem.EARN -> R.drawable.ic_action_earn

        MToolbarItem.SCAN -> R.drawable.ic_action_scan

        MToolbarItem.SEARCH, MToolbarItem.ACCOUNTS, MToolbarItem.ACTIONS ->
            throw IllegalArgumentException("$item is not an action")
    }

    fun getToolbarIconRes(item: MToolbarItem): Int = when (item) {
        MToolbarItem.BUY -> R.drawable.ic_toolbar_buy

        MToolbarItem.FUND -> R.drawable.ic_toolbar_fund

        MToolbarItem.TRADE -> R.drawable.ic_toolbar_trade

        MToolbarItem.SELL -> R.drawable.ic_toolbar_sell

        MToolbarItem.SEND -> R.drawable.ic_toolbar_send

        MToolbarItem.EARN -> R.drawable.ic_toolbar_earn

        MToolbarItem.SCAN -> R.drawable.ic_qr_code_scan_18_24

        MToolbarItem.SEARCH, MToolbarItem.ACCOUNTS, MToolbarItem.ACTIONS ->
            throw IllegalArgumentException("$item is not an action")
    }

    fun isAvailable(item: MToolbarItem, account: MAccount?): Boolean {
        if (account?.isViewOnly != true) return true
        return when (item) {
            MToolbarItem.FUND -> !account.isTemporary
            MToolbarItem.SCAN -> true
            else -> false
        }
    }
}
