package org.mytonwallet.app_air.uisettings.viewControllers.subwallets.cells

import android.content.Context
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import androidx.dynamicanimation.animation.FloatValueHolder
import androidx.dynamicanimation.animation.SpringAnimation
import androidx.dynamicanimation.animation.SpringForce
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.widgets.WCell
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.uicomponents.widgets.setBackgroundColor
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage
import org.mytonwallet.app_air.walletbasecontext.theme.ViewConstants
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color

class EmptySubwalletsCell(context: Context) : WCell(context), WThemedView {

    private val label = WLabel(context).apply {
        text = LocaleController.getString("\$subwallets_none")
        setStyle(14f, WFont.Regular)
    }

    init {
        layoutParams.apply { height = 16.dp }
        addView(label, LayoutParams(WRAP_CONTENT, WRAP_CONTENT))
        setConstraints {
            toCenterX(label, 0f)
            toCenterY(label)
        }
        isClickable = false
        isFocusable = false
        updateTheme()
    }

    override fun onAttachedToWindow() {
        super.onAttachedToWindow()
        val targetHeight = 50.dp.toFloat()
        if (!WGlobalStorage.getAreAnimationsActive()) {
            layoutParams.height = targetHeight.toInt()
            label.alpha = 1f
            requestLayout()
            return
        }
        val startHeight = 16.dp.toFloat()
        layoutParams.height = startHeight.toInt()
        label.alpha = 0f
        requestLayout()
        SpringAnimation(FloatValueHolder()).apply {
            setStartValue(startHeight)
            spring = SpringForce(targetHeight).apply {
                stiffness = 500f
                dampingRatio = SpringForce.DAMPING_RATIO_NO_BOUNCY
            }
            addUpdateListener { _, value, _ ->
                layoutParams.height = value.toInt()
                label.alpha = ((value - 20.dp) / (targetHeight - 20.dp)).coerceIn(0f, 1f)
                requestLayout()
            }
            addEndListener { _, _, _, _ -> label.alpha = 1f }
            start()
        }
    }

    override fun updateTheme() {
        setBackgroundColor(WColor.Background.color, 0f, ViewConstants.BLOCK_RADIUS.dp)
        label.setTextColor(WColor.SecondaryText.color)
    }
}
