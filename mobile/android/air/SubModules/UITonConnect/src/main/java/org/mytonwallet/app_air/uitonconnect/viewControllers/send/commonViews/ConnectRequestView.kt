package org.mytonwallet.app_air.uitonconnect.viewControllers.send.commonViews

import android.content.Context
import android.text.SpannableStringBuilder
import android.text.Spanned
import android.text.TextUtils
import android.text.method.LinkMovementMethod
import android.text.style.ClickableSpan
import android.util.TypedValue
import android.view.Gravity
import android.view.View
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import android.widget.LinearLayout
import androidx.appcompat.widget.AppCompatTextView
import androidx.core.content.ContextCompat
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.extensions.setPaddingDp
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.helpers.typeface
import org.mytonwallet.app_air.uicomponents.widgets.WImageView
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletbasecontext.utils.ApplicationContextHolder
import org.mytonwallet.app_air.walletcontext.utils.VerticalImageSpan
import org.mytonwallet.app_air.walletcore.moshi.ApiDapp

class ConnectRequestView(context: Context) : LinearLayout(context), WThemedView {
    private val imageView = WImageView(context, 20.dp)

    var onShowUnverifiedSourceWarning: (() -> Unit)? = null
    private val titleTextView = AppCompatTextView(context).apply {
        id = generateViewId()
        setTextSize(TypedValue.COMPLEX_UNIT_SP, 22f)
        setLineHeight(TypedValue.COMPLEX_UNIT_SP, 28f)
        ellipsize = TextUtils.TruncateAt.END
        gravity = Gravity.CENTER
        typeface = WFont.Medium.typeface
        maxLines = 1
    }

    private val linkTextView = AppCompatTextView(context).apply {
        id = generateViewId()
        setTextSize(TypedValue.COMPLEX_UNIT_SP, 16f)
        setLineHeight(TypedValue.COMPLEX_UNIT_SP, 24f)
        ellipsize = TextUtils.TruncateAt.END
        gravity = Gravity.CENTER
        typeface = WFont.Regular.typeface
        maxLines = 1
        movementMethod = LinkMovementMethod.getInstance()
        highlightColor = android.graphics.Color.TRANSPARENT
    }

    private val infoTextView = AppCompatTextView(context).apply {
        id = generateViewId()
        setTextSize(TypedValue.COMPLEX_UNIT_SP, 16f)
        setLineHeight(TypedValue.COMPLEX_UNIT_SP, 24f)
        ellipsize = TextUtils.TruncateAt.END
        gravity = Gravity.CENTER
        typeface = WFont.Regular.typeface
        maxWidth = 300.dp
    }

    init {
        setPaddingDp(20, 14, 20, 24)
        orientation = VERTICAL

        addView(imageView, LayoutParams(80.dp, 80.dp).apply { gravity = Gravity.CENTER })
        addView(titleTextView, LayoutParams(MATCH_PARENT, WRAP_CONTENT).apply { topMargin = 24.dp })
        addView(linkTextView, LayoutParams(MATCH_PARENT, WRAP_CONTENT).apply { topMargin = 8.dp })
        addView(infoTextView, LayoutParams(WRAP_CONTENT, WRAP_CONTENT).apply {
            gravity = Gravity.CENTER
            topMargin = 8.dp
        })
        updateTheme()
    }

    fun configure(dApp: ApiDapp) {
        titleTextView.text = dApp.name
        updateLinkText(dApp)
        infoTextView.text = LocaleController.getString("\$dapps_init_info")
        dApp.iconUrl?.let { iconUrl ->
            imageView.loadUrl(iconUrl)
        } ?: run {
            imageView.setImageDrawable(null)
        }
    }

    private fun updateLinkText(dApp: ApiDapp) {
        val builder = SpannableStringBuilder()

        if (dApp.isUrlEnsured != true) {
            ContextCompat.getDrawable(
                ApplicationContextHolder.applicationContext,
                org.mytonwallet.app_air.walletcontext.R.drawable.ic_warning
            )?.let { drawable ->
                val width = 14.dp
                val height = 26.dp
                drawable.setBounds(0, 0, width, height)
                val imageSpan = VerticalImageSpan(drawable)
                val start = builder.length
                builder.append("\u00A0", imageSpan, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)

                val clickableSpan = object : ClickableSpan() {
                    override fun onClick(widget: View) {
                        onShowUnverifiedSourceWarning?.invoke()
                    }
                }
                builder.setSpan(
                    clickableSpan,
                    start,
                    builder.length,
                    Spanned.SPAN_EXCLUSIVE_EXCLUSIVE
                )
            }
            builder.append(" ")
        }

        builder.append(dApp.host)
        linkTextView.text = builder
    }

    override fun updateTheme() {
        titleTextView.setTextColor(WColor.PrimaryText.color)
        linkTextView.setTextColor(WColor.Tint.color)
        infoTextView.setTextColor(WColor.PrimaryText.color)
    }
}
