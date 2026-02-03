package org.mytonwallet.app_air.uicomponents.widgets

import android.content.Context
import android.content.res.ColorStateList
import android.graphics.Color
import androidx.appcompat.widget.AppCompatImageButton
import org.mytonwallet.app_air.uicomponents.drawable.WRippleDrawable
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color

open class WImageButton(context: Context) : AppCompatImageButton(context), WThemedView {

    private val ripple = WRippleDrawable.create(100f.dp)
    private var rippleWColor = WColor.SecondaryBackground
    private var tintColors = listOf(
        WColor.PrimaryText,
        WColor.SecondaryText
    )

    init {
        id = generateViewId()
        background = ripple
        updateTheme()
    }

    override val isTinted = true
    fun updateColors(tint: WColor, rippleColor: WColor? = null) {
        rippleColor?.let {
            this.rippleWColor = rippleColor
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
        ripple.backgroundColor = Color.TRANSPARENT
        ripple.rippleColor = rippleWColor.color
    }

}
