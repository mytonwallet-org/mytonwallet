package org.mytonwallet.app_air.uisettings.viewControllers.connectedApps.cells

import android.content.Context
import android.text.TextUtils
import android.util.TypedValue
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import androidx.appcompat.widget.AppCompatImageView
import androidx.appcompat.widget.AppCompatTextView
import org.mytonwallet.app_air.icons.R
import org.mytonwallet.app_air.uicomponents.drawable.WRippleDrawable
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.helpers.typeface
import org.mytonwallet.app_air.uicomponents.widgets.WCell
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.uicomponents.widgets.WView
import org.mytonwallet.app_air.uicomponents.widgets.setBackgroundColor
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.theme.ViewConstants
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletbasecontext.theme.colorStateList
import org.mytonwallet.app_air.walletcore.moshi.ApiDapp

class ConnectedHeaderCell(context: Context) :
    WCell(context, LayoutParams(MATCH_PARENT, WRAP_CONTENT)), WThemedView {

    private val ripple = WRippleDrawable.create(0f).apply {
        rippleColor = WColor.BackgroundRipple.color
    }

    private val imageView = AppCompatImageView(context).apply {
        id = generateViewId()
        layoutParams = LayoutParams(24.dp, 24.dp)
        setImageResource(R.drawable.ic_hand_stop_24)
    }

    private val titleLabel = AppCompatTextView(context).apply {
        id = generateViewId()
        setTextSize(TypedValue.COMPLEX_UNIT_SP, 16f)
        setLineHeight(TypedValue.COMPLEX_UNIT_SP, 24f)
        includeFontPadding = false
        ellipsize = TextUtils.TruncateAt.END
        typeface = WFont.Medium.typeface
        maxLines = 1
        text =
            LocaleController.getString("Logged in with MyTonWallet")
    }

    private val subtitleLabel = AppCompatTextView(context).apply {
        id = generateViewId()
        setTextSize(TypedValue.COMPLEX_UNIT_SP, 16f)
        setLineHeight(TypedValue.COMPLEX_UNIT_SP, 24f)
        includeFontPadding = false
        ellipsize = TextUtils.TruncateAt.END
        typeface = WFont.Medium.typeface
        maxLines = 1
        text =
            LocaleController.getString("Disconnect All Dapps")
    }

    val disconnectContainer = WView(context).apply {
        id = generateViewId()
        layoutParams = LayoutParams(0, WRAP_CONTENT)
        background = ripple
        setPadding(0, 0, 0, 1.dp)

        addView(imageView)
        addView(subtitleLabel, LayoutParams(0, WRAP_CONTENT))
        setConstraints {
            toCenterY(imageView, 16f)
            toStart(imageView, 20f)
            toCenterY(subtitleLabel, 16f)
            startToEnd(subtitleLabel, imageView, 24f)
            toEnd(subtitleLabel, 24f)
        }
    }

    init {
        addView(titleLabel, LayoutParams(0, WRAP_CONTENT))
        addView(disconnectContainer)
        setConstraints {
            toCenterX(titleLabel, 20f)
            toTop(titleLabel, 18f)
            toCenterX(disconnectContainer)
            topToBottom(disconnectContainer, titleLabel, 12f)
        }

        updateTheme()
    }

    override fun updateTheme() {
        ripple.rippleColor = WColor.BackgroundRipple.color
        setBackgroundColor(WColor.Background.color, ViewConstants.TOOLBAR_RADIUS.dp, 0f)
        titleLabel.setTextColor(WColor.Tint.color)
        subtitleLabel.setTextColor(WColor.Red.color)
        imageView.imageTintList = WColor.Red.colorStateList
    }

    fun configure(exploreSite: ApiDapp) {
        titleLabel.text = exploreSite.name
    }
}
