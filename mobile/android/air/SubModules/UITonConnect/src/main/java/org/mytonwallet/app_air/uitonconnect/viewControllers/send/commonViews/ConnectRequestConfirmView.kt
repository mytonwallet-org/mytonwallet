package org.mytonwallet.app_air.uitonconnect.viewControllers.send.commonViews

import android.content.Context
import android.text.TextUtils
import android.util.TypedValue
import android.view.Gravity
import androidx.appcompat.widget.AppCompatTextView
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.extensions.setPaddingDp
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.helpers.typeface
import org.mytonwallet.app_air.uicomponents.widgets.WImageView
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.uicomponents.widgets.WView
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletcore.moshi.ApiDapp

class ConnectRequestConfirmView(context: Context) : WView(context), WThemedView {
    private val imageView = WImageView(context, 20.dp)

    private val titleTextView = AppCompatTextView(context).apply {
        id = generateViewId()
        setTextSize(TypedValue.COMPLEX_UNIT_SP, 36f)
        setLineHeight(TypedValue.COMPLEX_UNIT_SP, 44f)
        ellipsize = TextUtils.TruncateAt.END
        gravity = Gravity.CENTER
        typeface = WFont.Medium.typeface
        maxLines = 1
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
        setPaddingDp(20, 24, 20, 24)

        addView(imageView, LayoutParams(80.dp, 80.dp).apply {
            topToTop = LayoutParams.PARENT_ID
            startToStart = LayoutParams.PARENT_ID
            endToEnd = LayoutParams.PARENT_ID
        })

        addView(
            titleTextView,
            LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.WRAP_CONTENT).apply {
                topToBottom = imageView.id
                topMargin = 24.dp
                startToStart = LayoutParams.PARENT_ID
                endToEnd = LayoutParams.PARENT_ID
            })

        addView(
            infoTextView,
            LayoutParams(LayoutParams.WRAP_CONTENT, LayoutParams.WRAP_CONTENT).apply {
                topToBottom = titleTextView.id
                topMargin = 12.dp
                startToStart = LayoutParams.PARENT_ID
                endToEnd = LayoutParams.PARENT_ID
            })

        updateTheme()
    }

    fun configure(dApp: ApiDapp) {
        titleTextView.text = dApp.name
        infoTextView.text = LocaleController.getString("Connecting your wallet")
        dApp.iconUrl?.let { iconUrl ->
            imageView.loadUrl(iconUrl)
        } ?: run {
            imageView.setImageDrawable(null)
        }
    }

    override fun updateTheme() {
        titleTextView.setTextColor(WColor.PrimaryText.color)
        infoTextView.setTextColor(WColor.PrimaryText.color)
    }
}
