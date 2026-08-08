package org.mytonwallet.app_air.uitonconnect.viewControllers.send.requestSend

import android.annotation.SuppressLint
import android.content.Context
import android.view.Gravity
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import java.math.BigInteger
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.widgets.WAlertLabel
import org.mytonwallet.app_air.uicomponents.widgets.WButton
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.uicomponents.widgets.WView
import org.mytonwallet.app_air.uicomponents.widgets.dialog.WDialog
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletbasecontext.utils.smartDecimalsCount
import org.mytonwallet.app_air.walletbasecontext.utils.toBoldSpannableStringBuilder
import org.mytonwallet.app_air.walletbasecontext.utils.toProcessedSpannableStringBuilder
import org.mytonwallet.app_air.walletbasecontext.utils.toString
import org.mytonwallet.app_air.walletcore.moshi.IApiToken
import org.mytonwallet.app_air.walletcore.moshi.explainedFee.IExplainedFee

class DappFeeDetailsDialog {
    companion object {
        fun create(
            context: Context,
            token: IApiToken,
            feeDetails: IExplainedFee,
            onClosePressed: () -> Unit
        ): WDialog = WDialog(
            DappFeeDetailsContentView(context, token, feeDetails, onClosePressed),
            WDialog.Config(
                title = LocaleController.getString("App Fee Details")
            )
        )
    }
}

@SuppressLint("ViewConstructor")
private class DappFeeDetailsContentView(
    context: Context,
    private val token: IApiToken,
    private val feeDetails: IExplainedFee,
    private val onClosePressed: () -> Unit
) : WView(context),
    WThemedView {

    private val detailsLabel = WLabel(context).apply {
        setStyle(15f, WFont.Regular)
        setLineHeight(22f)
        gravity = Gravity.START
    }

    private val warningLabel = WAlertLabel(
        context,
        LocaleController.getString("\$dapp_return_disclaimer"),
        coloredText = true
    )

    private val okButton = WButton(context).apply {
        text = LocaleController.getString("Got It")
    }

    override fun setupViews() {
        super.setupViews()

        addView(detailsLabel, LayoutParams(0, WRAP_CONTENT))
        addView(warningLabel, LayoutParams(0, WRAP_CONTENT))
        addView(okButton, LayoutParams(240.dp, WRAP_CONTENT))

        setConstraints {
            toTop(detailsLabel, 20f)
            toCenterX(detailsLabel, 24f)

            topToBottom(warningLabel, detailsLabel, 24f)
            toCenterX(warningLabel, 24f)

            topToBottom(okButton, warningLabel, 32f)
            toCenterX(okButton)
            toBottom(okButton)
        }

        detailsLabel.text = buildDetailsText()
        okButton.setOnClickListener {
            onClosePressed()
        }
        updateTheme()
    }

    override fun updateTheme() {
        detailsLabel.setTextColor(WColor.SecondaryText.color)
    }

    private fun buildDetailsText(): CharSequence {
        val nativeToken = token.nativeToken ?: return ""
        val fullFee = feeDetails.fullFee?.nativeSum ?: BigInteger.ZERO
        val fullFeeText = fullFee.toString(
            nativeToken.decimals,
            nativeToken.symbol,
            fullFee.smartDecimalsCount(nativeToken.decimals),
            false,
            roundUp = true
        )
        val excessFeeText = "~\u202F" + feeDetails.excessFee.toString(
            nativeToken.decimals,
            nativeToken.symbol,
            feeDetails.excessFee.smartDecimalsCount(nativeToken.decimals),
            false,
            roundUp = false
        )
        return LocaleController.getSpannableStringWithKeyValues(
            "\$dapp_return_details",
            listOf(
                Pair("%fee_amount%", fullFeeText.toBoldSpannableStringBuilder()),
                Pair("%received_amount%", excessFeeText.toBoldSpannableStringBuilder())
            )
        ).trim().toProcessedSpannableStringBuilder()
    }
}
