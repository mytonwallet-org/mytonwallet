package org.mytonwallet.app_air.uiswap.screens.swap.views

import android.content.Context
import android.text.SpannableStringBuilder
import android.text.Spanned
import android.text.method.LinkMovementMethod
import android.util.AttributeSet
import android.util.TypedValue
import android.widget.LinearLayout
import android.widget.LinearLayout.VERTICAL
import androidx.appcompat.widget.AppCompatTextView
import androidx.core.content.ContextCompat
import org.mytonwallet.app_air.icons.R
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.extensions.setBoundsFitMin
import org.mytonwallet.app_air.uicomponents.extensions.setPaddingDp
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.helpers.adaptiveFontSize
import org.mytonwallet.app_air.uicomponents.helpers.typeface
import org.mytonwallet.app_air.uicomponents.widgets.ExpandableFrameLayout
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.uicomponents.widgets.setBackgroundColor
import org.mytonwallet.app_air.uiinappbrowser.span.InAppBrowserUrlSpan
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletcontext.helpers.SpanHelpers
import org.mytonwallet.app_air.walletcontext.utils.VerticalImageSpan

class SwapCexProviderInfoView @JvmOverloads constructor(
    context: Context,
    attrs: AttributeSet? = null,
    defStyle: Int = 0
) : ExpandableFrameLayout(context, attrs, defStyle),
    WThemedView {

    private val linearLayout = LinearLayout(context).apply {
        setPaddingDp(20, 16, 20, 16)
        layoutParams = LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.WRAP_CONTENT)
        orientation = VERTICAL
    }
    private val titleTextView = AppCompatTextView(context).apply {
        setLineHeight(TypedValue.COMPLEX_UNIT_SP, 24f)
        setTextSize(TypedValue.COMPLEX_UNIT_SP, adaptiveFontSize())
        typeface = WFont.Medium.typeface
    }
    private val infoTextView = AppCompatTextView(context).apply {
        setLineHeight(TypedValue.COMPLEX_UNIT_SP, 20f)
        setTextSize(TypedValue.COMPLEX_UNIT_SP, 14f)
        typeface = WFont.Regular.typeface
        movementMethod = LinkMovementMethod.getInstance()
    }

    init {
        linearLayout.addView(
            titleTextView,
            LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.WRAP_CONTENT).apply {
                topMargin = 1.dp
            }
        )
        linearLayout.addView(
            infoTextView,
            LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.WRAP_CONTENT).apply {
                topMargin = 6.dp
            }
        )

        addView(linearLayout)

        updateTheme()
    }

    fun setProviderInfo(
        providerName: String?,
        cexLabel: String?,
        termsOfUseUrl: String?,
        privacyPolicyUrl: String?,
        amlKycPolicyUrl: String?
    ) {
        val template = LocaleController.getString(
            "Cross-chain exchange provided by %provider%"
        )
        val placeholder = "%provider%"
        val startIndex = template.indexOf(placeholder)

        val (providerIconRes, providerIconHeightDp) = when (cexLabel) {
            "changelly" -> R.drawable.ic_cex_changelly to 20
            "near-intents" -> R.drawable.ic_cex_near_intents to 12
            else -> null to 0
        }
        titleTextView.text = if (startIndex != -1 && providerIconRes != null) {
            val builder = SpannableStringBuilder(template)
            builder.replace(startIndex, startIndex + placeholder.length, " ")
            val drawable = ContextCompat.getDrawable(context, providerIconRes)
            drawable?.let {
                drawable.setBoundsFitMin(providerIconHeightDp.dp)
                builder.setSpan(
                    VerticalImageSpan(it),
                    startIndex,
                    startIndex + 1,
                    Spanned.SPAN_EXCLUSIVE_EXCLUSIVE
                )
            }
            titleTextView.contentDescription = template.replace(placeholder, providerName ?: "")
            builder
        } else {
            template.replace(placeholder, providerName ?: "")
        }

        if (termsOfUseUrl != null && privacyPolicyUrl != null) {
            val replacements = mutableListOf(
                Pair(
                    "%terms%",
                    SpanHelpers.buildSpannable(
                        LocaleController.getString("\$swap_cex_terms_of_use"),
                        InAppBrowserUrlSpan(termsOfUseUrl, null)
                    )
                ),
                Pair(
                    "%policy%",
                    SpanHelpers.buildSpannable(
                        LocaleController.getString("\$swap_cex_privacy_policy"),
                        InAppBrowserUrlSpan(privacyPolicyUrl, null)
                    )
                )
            )
            val messageKey = if (amlKycPolicyUrl != null) {
                replacements.add(
                    Pair(
                        "%aml%",
                        SpanHelpers.buildSpannable(
                            providerName + " " +
                                LocaleController.getString($$"$swap_cex_aml_kyc_policy"),
                            InAppBrowserUrlSpan(amlKycPolicyUrl, null)
                        )
                    )
                )
                "\$swap_cex_legal_message_with_aml"
            } else {
                "\$swap_cex_legal_message"
            }

            infoTextView.text =
                LocaleController.getSpannableStringWithKeyValues(messageKey, replacements)
            infoTextView.visibility = VISIBLE
        } else {
            infoTextView.text = null
            infoTextView.visibility = GONE
        }
    }

    override fun updateTheme() {
        setBackgroundColor(WColor.Background.color, 24f.dp)

        titleTextView.setTextColor(WColor.PrimaryText.color)

        infoTextView.setTextColor(WColor.PrimaryText.color)
        infoTextView.setLinkTextColor(WColor.Tint.color)
        infoTextView.highlightColor = WColor.tintRippleColor
    }
}
