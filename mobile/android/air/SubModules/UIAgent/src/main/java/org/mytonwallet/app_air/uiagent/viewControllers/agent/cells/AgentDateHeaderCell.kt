package org.mytonwallet.app_air.uiagent.viewControllers.agent.cells

import android.annotation.SuppressLint
import android.content.Context
import android.text.SpannableStringBuilder
import android.text.Spanned
import android.view.Gravity
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import androidx.dynamicanimation.animation.FloatValueHolder
import androidx.dynamicanimation.animation.SpringAnimation
import androidx.dynamicanimation.animation.SpringForce
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.helpers.spans.WTypefaceSpan
import org.mytonwallet.app_air.uicomponents.widgets.WCell
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletcontext.utils.AnimUtils.Companion.lerp
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

@SuppressLint("ViewConstructor")
class AgentDateHeaderCell(context: Context) : WCell(
    context, LayoutParams(MATCH_PARENT, WRAP_CONTENT)
) {
    private val timeFormat = SimpleDateFormat("H:mm", Locale.getDefault())

    private val label = WLabel(context).apply {
        setStyle(14f)
        setTextColor(WColor.SecondaryText.color)
        gravity = Gravity.CENTER
        isSingleLine = true
    }

    init {
        addView(label)
        setConstraints {
            toTop(label, 8f)
            toBottom(label, 4f)
            toStart(label, 40f)
            toEnd(label, 40f)
        }
    }

    private var insertAnimation: SpringAnimation? = null

    fun configure(date: Date, animate: Boolean = false) {
        label.setUserFriendlyDate(date)
        val dayPart = label.text.toString()
        val timePart = timeFormat.format(date)

        val ssb = SpannableStringBuilder()
        ssb.append(
            dayPart,
            WTypefaceSpan(WFont.SemiBold),
            Spanned.SPAN_EXCLUSIVE_EXCLUSIVE
        )
        ssb.append(" $timePart")
        label.text = ssb

        if (animate) {
            startInsertAnimation()
        }
    }

    private fun startInsertAnimation() {
        insertAnimation?.cancel()
        label.alpha = 0f
        label.scaleX = 0.8f
        label.scaleY = 0.8f

        insertAnimation = SpringAnimation(FloatValueHolder()).apply {
            setStartValue(0f)
            spring = SpringForce(1f).apply {
                stiffness = 500f
                dampingRatio = SpringForce.DAMPING_RATIO_NO_BOUNCY
            }
            addUpdateListener { _, value, _ ->
                label.alpha = lerp(0f, 1f, value)
                label.scaleX = lerp(0.8f, 1f, value)
                label.scaleY = label.scaleX
            }
            addEndListener { _, canceled, _, _ ->
                if (canceled) {
                    label.alpha = 1f
                    label.scaleX = 1f
                    label.scaleY = 1f
                }
            }
            start()
        }
    }
}
