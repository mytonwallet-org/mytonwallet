package org.mytonwallet.app_air.uicomponents.widgets

import android.content.Context
import android.content.res.ColorStateList
import android.graphics.Color
import androidx.appcompat.widget.AppCompatImageButton
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color

open class WImageButton(context: Context) : AppCompatImageButton(context), WThemedView {

    private var rippleColor = WColor.SecondaryBackground
    private var tintColors = listOf(
        WColor.PrimaryText,
        WColor.SecondaryText
    )

    init {
        id = generateViewId()
        setBackgroundColor(Color.TRANSPARENT)
        updateTheme()
    }

    override val isTinted = true
    fun updateColors(tint: WColor, rippleColor: WColor? = null) {
        rippleColor?.let {
            this.rippleColor = rippleColor
        }
        this.tintColors = listOf(tint, tint)
        updateTheme()
    }

    override fun updateTheme() {
        val states = arrayOf(
            intArrayOf(android.R.attr.state_checked),
            intArrayOf(-android.R.attr.state_checked)
        )
        val colors = tintColors.map {
            it.color
        }.toIntArray()
        val colorStateList = ColorStateList(states, colors)
        imageTintList = colorStateList
        background = null
        addRippleEffect(rippleColor.color, 100f)
    }

}
