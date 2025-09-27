package org.mytonwallet.app_air.uicomponents.commonViews.feeDetailsDialog

import android.content.Context
import org.mytonwallet.app_air.uicomponents.widgets.dialog.WDialog
import org.mytonwallet.app_air.walletcore.models.explainedFee.IExplainedFee
import org.mytonwallet.app_air.walletcore.moshi.IApiToken
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController

class FeeDetailsDialog {
    companion object {
        fun create(
            context: Context,
            token: IApiToken,
            feeDetails: IExplainedFee,
            onClosePressed: () -> Unit
        ): WDialog {
            return WDialog(
                FeeDetailsContentView(context, token, feeDetails, onClosePressed),
                WDialog.Config(
                    title = LocaleController.getString("Blockchain Fee Details"),
                )
            )
        }
    }
}
