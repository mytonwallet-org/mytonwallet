package org.mytonwallet.app_air.uitonconnect.viewControllers.send.commonViews

import android.content.Context
import android.text.TextUtils
import android.util.TypedValue
import android.view.Gravity
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import android.widget.LinearLayout
import androidx.appcompat.widget.AppCompatTextView
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.extensions.setPaddingDp
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.helpers.typeface
import org.mytonwallet.app_air.uicomponents.widgets.WImageView
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.walletcontext.helpers.LocaleController
import org.mytonwallet.app_air.walletcontext.theme.WColor
import org.mytonwallet.app_air.walletcontext.theme.color
import org.mytonwallet.app_air.walletcore.moshi.ApiDapp

class ConnectRequestView(context: Context) : LinearLayout(context), WThemedView {
    private val imageView = WImageView(context, 20.dp)

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
        linkTextView.text = dApp.host
        infoTextView.text = LocaleController.getString("\$dapps_init_info")
        dApp.iconUrl?.let { iconUrl ->
            imageView.loadUrl(iconUrl)
        } ?: run {
            imageView.setImageDrawable(null)
        }
    }

    override fun updateTheme() {
        titleTextView.setTextColor(WColor.PrimaryText.color)
        linkTextView.setTextColor(WColor.Tint.color)
        infoTextView.setTextColor(WColor.PrimaryText.color)
    }
}
