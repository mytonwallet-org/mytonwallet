package org.mytonwallet.app_air.uicomponents.widgets

import android.content.Context
import android.util.AttributeSet
import android.view.ViewGroup
import android.widget.FrameLayout
import androidx.core.view.children
import me.vkryl.android.animatorx.BoolAnimator
import org.mytonwallet.app_air.uicomponents.AnimationConstants
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.extensions.exactly
import org.mytonwallet.app_air.uicomponents.extensions.unspecified
import org.mytonwallet.app_air.walletcontext.helpers.WInterpolator

open class ExpandableFrameLayout @JvmOverloads constructor(
    context: Context,
    attrs: AttributeSet? = null,
    defStyleAttr: Int = 0
) : FrameLayout(context, attrs, defStyleAttr) {
    private val animator = BoolAnimator(
        AnimationConstants.DIALOG_PRESENT,
        WInterpolator.emphasized,
        initialValue = false
    ) { _, _, _, _ ->
        requestLayout()
        if (!children.toList().isEmpty())
            (children.first() as? ViewGroup)?.let { container ->
                container.children.forEach {
                    it.apply {
                        if (container.height == 0) {
                            alpha = 1f
                        } else {
                            val t = top
                            alpha =
                                ((container.height - t) / (internalHeight - t).toFloat())
                                    .coerceIn(0f, 1f)
                        }
                        translationY = -(1 - alpha) * 10.dp
                    }
                }
            }
    }

    var expanded: Boolean
        get() = animator.value
        set(value) {
            setExpandedValue(value, true)
        }

    fun setExpandedValue(expanded: Boolean, animated: Boolean) {
        animator.changeValue(expanded, animated && isAttachedToWindow)
    }

    var internalHeight: Int = 0
    override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
        val child = children.first()
        child.measure(widthMeasureSpec, 0.unspecified)

        val expansion = animator.floatValue
        internalHeight = child.measuredHeight
        super.onMeasure(widthMeasureSpec, (internalHeight * expansion).toInt().exactly)
    }
}
