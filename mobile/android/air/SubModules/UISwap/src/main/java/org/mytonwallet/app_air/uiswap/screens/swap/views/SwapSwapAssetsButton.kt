package org.mytonwallet.app_air.uiswap.screens.swap.views

import android.content.Context
import androidx.appcompat.widget.AppCompatImageView
import com.facebook.drawee.drawable.RoundedColorDrawable
import org.mytonwallet.app_air.icons.R
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.helpers.ViewHelpers
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletbasecontext.theme.colorStateList

class SwapSwapAssetsButton(context: Context) : AppCompatImageView(context), WThemedView {
    init {
        updateTheme()

        setImageResource(R.drawable.ic_switch_24)
        imageTintList = WColor.Tint.colorStateList
        scaleType = ScaleType.CENTER
    }

    override fun updateTheme() {
        background = ViewHelpers.roundedRippleDrawable(
            RoundedColorDrawable(WColor.SecondaryBackground.color).apply {
                setRadius(16f.dp)
            },
            WColor.tintRippleColor, 16f.dp
        )
    }
}
