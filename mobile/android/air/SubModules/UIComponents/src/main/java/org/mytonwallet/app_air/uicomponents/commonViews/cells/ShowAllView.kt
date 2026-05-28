package org.mytonwallet.app_air.uicomponents.commonViews.cells

import android.content.Context
import android.graphics.Color
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.uicomponents.widgets.WView
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color

class ShowAllView(
    context: Context,
) : WView(context), WThemedView {

    var onTap: (() -> Unit)? = null

    val titleLabel: WLabel by lazy {
        val lbl = WLabel(context)
        lbl.setStyle(16f, WFont.Medium)
        lbl
    }

    init {
        layoutParams.apply {
            height = 56.dp
        }
        addView(titleLabel)
        setConstraints {
            toCenterY(titleLabel)
            toStart(titleLabel, 20f)
        }

        setOnClickListener {
            onTap?.invoke()
        }

        updateTheme()
    }

    override val isTinted = true
    override fun updateTheme() {
        setBackgroundColor(Color.TRANSPARENT)
        addRippleEffect(WColor.TintRipple.color)
        titleLabel.setTextColor(WColor.Tint.color)
    }

}
