package org.mytonwallet.app_air.uicomponents.widgets.dialog

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Color
import android.view.Gravity
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.drawable.WRippleDrawable
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletcontext.utils.colorWithAlpha

@SuppressLint("ViewConstructor")
class WDialogButton(
    context: Context,
    private val config: Config
) : WLabel(context), WThemedView {
    data class Config(
        val title: CharSequence,
        val onTap: (() -> Unit)?,
        val style: Style = Style.TINT
    ) {
        enum class Style {
            NORMAL,
            TINT,
            PREFERRED,
            DANGER
        }
    }

    private val ripple = WRippleDrawable.create(20f.dp)

    init {
        setStyle(16f, WFont.Medium)
        setPadding(12.dp, 0, 12.dp, 0)
        text = config.title
        gravity = Gravity.CENTER
        background = ripple
        updateTheme()
    }

    override fun updateTheme() {
        super.updateTheme()
        when (config.style) {
            Config.Style.TINT -> {
                setTextColor(WColor.Tint.color)
                ripple.backgroundColor = Color.TRANSPARENT
                ripple.rippleColor = WColor.TintRipple.color
            }

            Config.Style.PREFERRED -> {
                setTextColor(WColor.TextOnTint.color)
                ripple.backgroundColor = WColor.Tint.color
                ripple.rippleColor = WColor.TintRipple.color
            }

            Config.Style.DANGER -> {
                setTextColor(WColor.White.color)
                ripple.backgroundColor = WColor.Red.color
                ripple.rippleColor = Color.BLACK.colorWithAlpha(25)
            }

            Config.Style.NORMAL -> {
                setTextColor(WColor.PrimaryText.color)
                ripple.backgroundColor = Color.TRANSPARENT
                ripple.rippleColor = WColor.SecondaryBackground.color
            }
        }
    }
}
