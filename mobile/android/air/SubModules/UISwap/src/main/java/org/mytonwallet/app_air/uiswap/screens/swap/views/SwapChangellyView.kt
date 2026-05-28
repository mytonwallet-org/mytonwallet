package org.mytonwallet.app_air.uiswap.screens.swap.views

import android.content.Context
import android.text.method.LinkMovementMethod
import android.util.AttributeSet
import android.util.TypedValue
import android.widget.LinearLayout
import android.widget.LinearLayout.VERTICAL
import androidx.appcompat.widget.AppCompatTextView
import androidx.core.content.ContextCompat
import org.mytonwallet.app_air.icons.R
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.extensions.setPaddingDp
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.helpers.typeface
import org.mytonwallet.app_air.uicomponents.widgets.ExpandableFrameLayout
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.uiinappbrowser.span.InAppBrowserUrlSpan
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletcontext.helpers.SpanHelpers
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color

class SwapChangellyView @JvmOverloads constructor(
    context: Context,
    attrs: AttributeSet? = null,
    defStyle: Int = 0,
) : ExpandableFrameLayout(context, attrs, defStyle), WThemedView {

    private val linearLayout = LinearLayout(context).apply {
        setPaddingDp(20, 16, 20, 16)
        layoutParams = LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.WRAP_CONTENT)
        orientation = VERTICAL
    }
    private val titleTextView = AppCompatTextView(context).apply {
        setLineHeight(TypedValue.COMPLEX_UNIT_SP, 24f)
        setTextSize(TypedValue.COMPLEX_UNIT_SP, 16f)
        typeface = WFont.Medium.typeface

    }
    private val infoTextView = AppCompatTextView(context).apply {
        setLineHeight(TypedValue.COMPLEX_UNIT_SP, 20f)
        setTextSize(TypedValue.COMPLEX_UNIT_SP, 14f)
        typeface = WFont.Regular.typeface
    }
    private val titleLogoDrawable =
        ContextCompat.getDrawable(context, R.drawable.ic_changelly_logo_20)

    init {
        titleTextView.text = LocaleController.getSpannableStringWithKeyValues(
            "Cross-chain exchange provided by Changelly", listOf(
                Pair(
                    "Changelly",
                    SpanHelpers.buildSpannableImage(titleLogoDrawable)
                )
            )
        )

        infoTextView.text = LocaleController.getSpannableStringWithKeyValues(
            "\$swap_changelly_agreement_message",
            listOf(
                Pair(
                    "%terms%",
                    SpanHelpers.buildSpannable(
                        LocaleController.getString("\$swap_changelly_terms_of_use"),
                        InAppBrowserUrlSpan("https://changelly.com/terms-of-use", null)
                    )
                ),
                Pair(
                    "%policy%",
                    SpanHelpers.buildSpannable(
                        LocaleController.getString("\$swap_changelly_privacy_policy"),
                        InAppBrowserUrlSpan("https://changelly.com/privacy-policy", null)
                    )
                ),
                Pair(
                    "%kyc%",
                    SpanHelpers.buildSpannable(
                        LocaleController.getString("AML/KYC"),
                        InAppBrowserUrlSpan("https://changelly.com/aml-kyc", null)
                    )
                )
            )
        )
        infoTextView.movementMethod = LinkMovementMethod.getInstance()

        linearLayout.addView(titleTextView)
        linearLayout.addView(
            infoTextView,
            LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.WRAP_CONTENT).apply {
                topMargin = 4.dp
            })

        addView(linearLayout)

        updateTheme()
    }

    override fun updateTheme() {
        titleLogoDrawable?.setTint(WColor.PrimaryText.color)
        titleTextView.setTextColor(WColor.PrimaryText.color)

        infoTextView.setTextColor(WColor.PrimaryText.color)
        infoTextView.setLinkTextColor(WColor.Tint.color)
        infoTextView.highlightColor = WColor.tintRippleColor
    }
}
