package org.mytonwallet.app_air.uicomponents.widgets.dialog

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Color
import android.view.Gravity
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.uicomponents.widgets.addRippleEffect
import org.mytonwallet.app_air.uicomponents.widgets.setBackgroundColor
import org.mytonwallet.app_air.walletcontext.theme.WColor
import org.mytonwallet.app_air.walletcontext.theme.color
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

    init {
        setStyle(16f, WFont.Medium)
        setPadding(12.dp, 0, 12.dp, 0)
        text = config.title
        gravity = Gravity.CENTER
        updateTheme()
    }

    override fun updateTheme() {
        super.updateTheme()
        when (config.style) {
            Config.Style.TINT -> {
                setTextColor(WColor.Tint.color)
                addRippleEffect(WColor.TintRipple.color, 20f.dp)
            }

            Config.Style.PREFERRED -> {
                setBackgroundColor(WColor.Tint.color, 20f.dp)
                setTextColor(WColor.TextOnTint.color)
                addRippleEffect(WColor.TintRipple.color, 20f.dp)
            }

            Config.Style.DANGER -> {
                setTextColor(WColor.Red.color)
                addRippleEffect(Color.BLACK.colorWithAlpha(76), 20f.dp)
            }

            Config.Style.NORMAL -> {
                setTextColor(WColor.PrimaryText.color)
                addRippleEffect(WColor.SecondaryBackground.color, 20f.dp)
            }
        }
    }
}
