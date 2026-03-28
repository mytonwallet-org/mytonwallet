package org.mytonwallet.app_air.uicomponents.widgets

import android.content.Context
import android.view.Gravity
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.extensions.setPaddingDp
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.image.Content
import org.mytonwallet.app_air.uicomponents.image.WCustomImageView
import org.mytonwallet.app_air.walletbasecontext.theme.ViewConstants
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color

class WTagView(context: Context) : WFrameLayout(context), WThemedView {

    private val icon = WCustomImageView(context).apply {
        defaultRounding = Content.Rounding.Radius(0f)
    }

    private val title: WLabel = WLabel(context).apply {
        setStyle(14f, WFont.Regular)
        setTextColor(WColor.PrimaryText)
        setSingleLine()
        setPaddingDp(6f, 0f, 6f, 0f)
        gravity = Gravity.CENTER_VERTICAL
    }

    init {
        addView(icon, LayoutParams(28.dp, 28.dp))
        addView(title, LayoutParams(LayoutParams.WRAP_CONTENT, 28.dp).apply {
            setMargins(28.dp, 0, 0, 0)
        })
        updateTheme()
    }

    fun configure(
        image: Content?,
        title: CharSequence?
    ) {
        image?.let {
            icon.set(image)
        } ?: run {
            icon.clear()
        }
        this.title.text = title
    }

    override fun updateTheme() {
        title.updateTheme()
        setBackgroundColor(
            WColor.SecondaryBackground.color,
            ViewConstants.TAG_RADIUS.dp,
            clipToBounds = true
        )
    }
}
