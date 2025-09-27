package org.mytonwallet.app_air.uiswap.screens.swap.views

import android.content.Context
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.Paint.Style
import android.graphics.Path
import android.util.AttributeSet
import android.util.TypedValue
import androidx.appcompat.widget.AppCompatTextView
import me.vkryl.android.AnimatorUtils
import me.vkryl.android.animatorx.BoolAnimator
import org.mytonwallet.app_air.uicomponents.AnimationConstants
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.extensions.setPaddingDpLocalized
import org.mytonwallet.app_air.uicomponents.helpers.ViewHelpers
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.helpers.typeface
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color


class SwapEstimatedHeader @JvmOverloads constructor(
    context: Context,
    attrs: AttributeSet? = null,
    defStyle: Int = 0,
) : AppCompatTextView(context, attrs, defStyle), WThemedView {
    companion object {
        private const val DURATION = AnimationConstants.VERY_QUICK_ANIMATION
    }

    private val path = Path().apply {
        val cx = 0f
        val cy = 0f
        val r = 5.dp
        moveTo(cx - r, cy)
        lineTo(cx, cy + r)
        lineTo(cx + r, cy)
    }

    private val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Style.STROKE
        strokeWidth = 2f.dp
        strokeJoin = Paint.Join.ROUND
        strokeCap = Paint.Cap.ROUND
    }

    val isExpanded = BoolAnimator(
        DURATION, AnimatorUtils.DECELERATE_INTERPOLATOR,
        initialValue = false
    ) { _, _, _, _ ->
        invalidate()
    }

    init {
        setTextSize(TypedValue.COMPLEX_UNIT_SP, 16f)
        setLineHeight(TypedValue.COMPLEX_UNIT_SP, 24f)
        setPaddingDpLocalized(20, 16, 48, 16)
        typeface = WFont.Medium.typeface
        text = LocaleController.getString("Swap Details")

        updateTheme()
    }

    override fun draw(canvas: Canvas) {
        super.draw(canvas)

        val cx = if (LocaleController.isRTL) {
            28f.dp
        } else {
            measuredWidth - 28f.dp
        }
        val cy = measuredHeight / 2f

        canvas.save()
        canvas.translate(cx, cy)
        canvas.rotate(180 * isExpanded.floatValue)
        canvas.drawPath(path, paint)
        canvas.restore()
    }

    override fun updateTheme() {
        background = ViewHelpers.roundedRippleDrawable(null, WColor.backgroundRippleColor, 0f)
        paint.color = WColor.SecondaryText.color
        setTextColor(WColor.PrimaryText.color)
    }
}
