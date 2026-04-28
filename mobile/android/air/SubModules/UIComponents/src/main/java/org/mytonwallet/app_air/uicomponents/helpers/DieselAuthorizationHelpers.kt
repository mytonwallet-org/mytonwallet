package org.mytonwallet.app_air.uicomponents.helpers

import android.content.Context
import android.content.Intent
import android.net.Uri
import org.mytonwallet.app_air.walletbasecontext.R as BaseR
import org.mytonwallet.app_air.walletcore.stores.AccountStore

class DieselAuthorizationHelpers {
    companion object {
        fun authorizeDiesel(context: Context) {
            val tonAddress = AccountStore.activeAccount?.tonAddress ?: ""
            val botUsername = context.getString(BaseR.string.bot_username)
            val telegramURLString = "https://t.me/$botUsername?start=auth-$tonAddress"
            val telegramURL = Uri.parse(telegramURLString)

            val intent = Intent(Intent.ACTION_VIEW, telegramURL)
            context.startActivity(intent)
        }
    }
}
