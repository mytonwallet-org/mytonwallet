package org.mytonwallet.app_air.uicomponents.commonViews.feeDetailsDialog

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Color
import android.view.Gravity
import android.view.ViewGroup
import android.widget.LinearLayout
import androidx.constraintlayout.widget.ConstraintLayout.LayoutParams.MATCH_PARENT
import androidx.constraintlayout.widget.ConstraintLayout.LayoutParams.WRAP_CONTENT
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.extensions.setPaddingLocalized
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.widgets.WButton
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.uicomponents.widgets.WView
import org.mytonwallet.app_air.uicomponents.widgets.setBackgroundColor
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletbasecontext.utils.smartDecimalsCount
import org.mytonwallet.app_air.walletbasecontext.utils.toBoldSpannableStringBuilder
import org.mytonwallet.app_air.walletbasecontext.utils.toProcessedSpannableStringBuilder
import org.mytonwallet.app_air.walletbasecontext.utils.toString
import org.mytonwallet.app_air.walletcore.models.MFee
import org.mytonwallet.app_air.walletcore.models.explainedFee.IExplainedFee
import org.mytonwallet.app_air.walletcore.moshi.IApiToken
import java.math.BigInteger
import kotlin.math.max

@SuppressLint("ViewConstructor")
class FeeDetailsContentView(
    context: Context,
    private val token: IApiToken,
    private val feeDetails: IExplainedFee,
    private val onClosePressed: () -> Unit
) : WView(context), WThemedView {

    private val finalFeeLabel = WLabel(context).apply {
        setStyle(14f, WFont.SemiBold)
        text = LocaleController.getString("Final Fee")
    }

    private val excessFeeLabel = WLabel(context).apply {
        setStyle(14f, WFont.SemiBold)
        text = LocaleController.getString("Excess")
    }

    private val finalFeeValueLabel = WLabel(context).apply {
        setStyle(14f, WFont.SemiBold)
        maxLines = 1
        gravity =
            Gravity.CENTER_VERTICAL or if (LocaleController.isRTL) Gravity.RIGHT else Gravity.LEFT
        setPaddingLocalized(10.dp, 0, 2.dp, 0)
    }

    private val excessFeeValueLabel = WLabel(context).apply {
        setStyle(14f, WFont.SemiBold)
        maxLines = 2
        gravity =
            Gravity.CENTER_VERTICAL or if (LocaleController.isRTL) Gravity.LEFT else Gravity.RIGHT
        setPaddingLocalized(2.dp, 0, 10.dp, 0)
    }

    private val feeValuesView = LinearLayout(context).apply {
        id = generateViewId()
        orientation = LinearLayout.HORIZONTAL
        addView(finalFeeValueLabel, LinearLayout.LayoutParams(0, MATCH_PARENT))
        addView(excessFeeValueLabel, LinearLayout.LayoutParams(0, MATCH_PARENT))
    }

    private val detailsLabel = WLabel(context).apply {
        setStyle(15f, WFont.Regular)
    }

    private val okButton = WButton(context).apply {
        text = LocaleController.getString("Got It")
    }

    @SuppressLint("SetTextI18n")
    override fun setupViews() {
        super.setupViews()

        addView(finalFeeLabel)
        addView(excessFeeLabel)
        addView(feeValuesView, ViewGroup.LayoutParams(MATCH_PARENT, 40.dp))
        addView(detailsLabel, LayoutParams(0, WRAP_CONTENT))
        addView(okButton, LayoutParams(0, WRAP_CONTENT))

        setConstraints {
            toTop(finalFeeLabel, 20f)
            toTop(excessFeeLabel, 20f)
            toStart(finalFeeLabel, 26f)
            toEnd(excessFeeLabel, 26f)
            topToBottom(feeValuesView, finalFeeLabel, 6f)
            toCenterX(feeValuesView, 24f)
            topToBottom(detailsLabel, feeValuesView, 32f)
            toCenterX(detailsLabel, 24f)
            topToBottom(okButton, detailsLabel, 32f)
            toBottom(okButton)
            toCenterX(okButton, 24f)
        }

        val finalFeeVal = feeDetails.realFee?.networkTerms?.native
            ?: feeDetails.realFee?.nativeSum
            ?: BigInteger.ZERO
        finalFeeValueLabel.text =
            feeDetails.realFee?.toString(token, appendNonNative = feeDetails.isGasless)
        finalFeeValueLabel.layoutParams =
            (finalFeeValueLabel.layoutParams as LinearLayout.LayoutParams).apply {
                weight =
                    max(
                        100f,
                        (finalFeeVal * BigInteger.valueOf(1000) / (finalFeeVal + feeDetails.excessFee)).toFloat()
                    ) / 1000f
            }
        val nativeToken = token.nativeToken!!
        excessFeeValueLabel.text = "~${
            feeDetails.excessFee.toString(
                nativeToken.decimals,
                nativeToken.symbol,
                feeDetails.excessFee.smartDecimalsCount(nativeToken.decimals),
                false
            )
        }"
        excessFeeValueLabel.layoutParams =
            (excessFeeValueLabel.layoutParams as LinearLayout.LayoutParams).apply {
                weight =
                    (feeDetails.excessFee * BigInteger.valueOf(1000) / (finalFeeVal + feeDetails.excessFee)).toFloat() / 1000f
                if (weight > 0) {
                    if (LocaleController.isRTL)
                        rightMargin = 3.dp
                    else
                        leftMargin = 3.dp
                }
            }
        finalFeeValueLabel.post {
            val paint = finalFeeValueLabel.paint
            val textWidth = paint.measureText(finalFeeValueLabel.text.toString()).toInt() + 42.dp
            if (finalFeeValueLabel.measuredWidth < textWidth) {
                val multiplier = textWidth / finalFeeValueLabel.measuredWidth.toFloat()
                finalFeeValueLabel.layoutParams =
                    (finalFeeValueLabel.layoutParams as LinearLayout.LayoutParams).apply {
                        weight *= multiplier
                    }
            }
        }

        fillDetailsLabel()

        okButton.setOnClickListener {
            onClosePressed()
        }

        updateTheme()
    }

    override fun updateTheme() {
        finalFeeLabel.setTextColor(WColor.Tint.color)
        excessFeeLabel.setTextColor(WColor.Green.color)
        finalFeeValueLabel.setTextColor(WColor.TextOnTint.color)
        finalFeeValueLabel.setBackgroundColor(WColor.Tint.color, 4f.dp)
        excessFeeValueLabel.setTextColor(Color.WHITE)
        excessFeeValueLabel.setBackgroundColor(WColor.Green.color, 4f.dp)
        feeValuesView.setBackgroundColor(Color.TRANSPARENT, 10f.dp, true)
        detailsLabel.setTextColor(WColor.SecondaryText.color)
    }

    @SuppressLint("SetTextI18n")
    private fun fillDetailsLabel() {
        val fee =
            feeDetails.fullFee?.apply { precision = MFee.FeePrecision.EXACT }
                ?.toString(token, appendNonNative = feeDetails.isGasless) ?: ""
        val nativeToken = token.nativeToken
        val symbol = nativeToken?.symbol?.uppercase() ?: ""
        val chain = LocaleController.getFormattedString(
            "%1$@",
            listOf(nativeToken?.chain?.uppercase() ?: "")
        )

        detailsLabel.text = (if (LocaleController.isRTL) "\u200F" else "") + "${
            LocaleController.getSpannableStringWithKeyValues(
                "\$fee_details",
                listOf(
                    Pair("%full_fee%", fee.toBoldSpannableStringBuilder()),
                    Pair("%excess_symbol%", symbol.toBoldSpannableStringBuilder()),
                    Pair("%chain_name%", chain.toBoldSpannableStringBuilder())
                )
            ).trim().toProcessedSpannableStringBuilder()
        }"
    }
}
