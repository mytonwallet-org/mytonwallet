package org.mytonwallet.app_air.uitonconnect.viewControllers.send.commonViews

import android.annotation.SuppressLint
import android.content.Context
import android.text.TextUtils
import android.view.Gravity
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import android.widget.LinearLayout
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.image.Content
import org.mytonwallet.app_air.uicomponents.image.WCustomImageView
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.uicomponents.widgets.WView
import org.mytonwallet.app_air.uicomponents.widgets.passcode.headers.PasscodeHeaderSendView
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color

@SuppressLint("ViewConstructor")
class SignDataPasscodeHeaderView(context: Context, dappName: String, dappIconUrl: String?) :
    WView(context),
    WThemedView {

    companion object {
        private const val SUBTITLE_ICON_SIZE = 18
    }

    private val titleLabel = WLabel(context).apply {
        id = generateViewId()
        setStyle(PasscodeHeaderSendView.TEXT_TITLE_SIZE_SP, WFont.Balance)
        setLineHeight(36f)
        includeFontPadding = false
        gravity = Gravity.CENTER
        maxLines = 2
        ellipsize = TextUtils.TruncateAt.END
        text = LocaleController.getString("Sign Data")
    }

    private val subtitlePrefixLabel = WLabel(context).apply {
        setStyle(16f)
        gravity = Gravity.CENTER
        maxLines = 1
        text = LocaleController.getString("\$dapp_sign_data_for_prefix")
    }

    private val subtitleIconView = WCustomImageView(context).apply {
        defaultRounding = Content.Rounding.Radius(4f.dp)
        defaultPlaceholder = Content.Placeholder.Color(WColor.SecondaryBackground)
        chainSize = 0
        set(Content.ofUrl(dappIconUrl ?: ""))
    }

    private val subtitleLabel = WLabel(context).apply {
        setStyle(16f)
        gravity = Gravity.CENTER
        maxLines = 1
        ellipsize = TextUtils.TruncateAt.END
        text = dappName
    }

    private val subtitleRow = LinearLayout(context).apply {
        id = generateViewId()
        orientation = LinearLayout.HORIZONTAL
        gravity = Gravity.CENTER
        addView(
            subtitlePrefixLabel,
            LinearLayout.LayoutParams(WRAP_CONTENT, WRAP_CONTENT).apply {
                marginEnd = 4.dp
            }
        )
        addView(
            subtitleIconView,
            LinearLayout.LayoutParams(SUBTITLE_ICON_SIZE.dp, SUBTITLE_ICON_SIZE.dp).apply {
                marginEnd = 4.dp
            }
        )
        addView(subtitleLabel, LinearLayout.LayoutParams(WRAP_CONTENT, WRAP_CONTENT))
    }

    init {
        addView(titleLabel, LayoutParams(0, WRAP_CONTENT))
        addView(subtitleRow, LayoutParams(0, WRAP_CONTENT))
        setConstraints {
            toTop(titleLabel, 24f)
            toCenterX(titleLabel, 20f)
            topToBottom(subtitleRow, titleLabel, 10f)
            toCenterX(subtitleRow, 20f)
            toBottom(subtitleRow, 24f)
        }
        updateTheme()
    }

    override fun updateTheme() {
        titleLabel.setTextColor(WColor.PrimaryText.color)
        subtitlePrefixLabel.setTextColor(WColor.PrimaryText.color)
        subtitleLabel.setTextColor(WColor.SecondaryText.color)
    }
}
