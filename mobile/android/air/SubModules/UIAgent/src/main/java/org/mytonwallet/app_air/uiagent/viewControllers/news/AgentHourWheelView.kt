package org.mytonwallet.app_air.uiagent.viewControllers.news

import android.animation.ValueAnimator
import android.annotation.SuppressLint
import android.content.Context
import android.os.Build
import android.os.Bundle
import android.view.Gravity
import android.view.HapticFeedbackConstants
import android.view.MotionEvent
import android.view.View
import android.view.ViewGroup
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.widget.FrameLayout
import android.widget.LinearLayout
import androidx.core.view.AccessibilityDelegateCompat
import androidx.core.view.ViewCompat
import androidx.core.view.accessibility.AccessibilityNodeInfoCompat
import androidx.core.view.accessibility.AccessibilityNodeInfoCompat.AccessibilityActionCompat
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.LinearSnapHelper
import androidx.recyclerview.widget.RecyclerView
import kotlin.math.abs
import kotlin.math.min
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.uicomponents.widgets.setBackgroundColor
import org.mytonwallet.app_air.walletbasecontext.DEBUG_MODE
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage
import org.mytonwallet.app_air.walletcore.pushNotifications.AGENT_NEWS_DIGEST_MINUTES

/**
 * The digest's time on a wheel, as iOS's time wheel: the hours and, beside them, the minutes 00, 15, 30 and 45 turn past
 * a band that marks the chosen time. A turn picks the time it settles on; TalkBack moves it 15 minutes at a time.
 */
@SuppressLint("ViewConstructor")
internal class AgentHourWheelView(context: Context) :
    FrameLayout(context),
    WThemedView {
    /** The time the wheel settled on after a turn of either column */
    var onTimeSelected: ((AgentDigestTime) -> Unit)? = null

    private val rowHeight = ROW_HEIGHT.dp
    private val band = View(context).apply { id = generateViewId() }
    private val hourColumn = WheelColumn(AgentDigestSettingsModel.HOURS.toList())
    private val minuteColumn = WheelColumn(AGENT_NEWS_DIGEST_MINUTES)

    /** Every time of the day the wheel can show, in order, which TalkBack steps through */
    private val times = AgentDigestSettingsModel.HOURS.flatMap { hour ->
        AGENT_NEWS_DIGEST_MINUTES.map { minute -> AgentDigestTime(hour, minute) }
    }

    init {
        id = generateViewId()
        importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_YES
        isFocusable = true
        contentDescription = LocaleController.getString("\$agent_digest_time")
        addView(
            band,
            LayoutParams(MATCH_PARENT, rowHeight, Gravity.CENTER_VERTICAL).apply {
                marginStart = BAND_INSET.dp
                marginEnd = BAND_INSET.dp
            }
        )
        // A clock reads hours before minutes in every language
        val columns = LinearLayout(context).apply {
            orientation = LinearLayout.HORIZONTAL
            layoutDirection = LAYOUT_DIRECTION_LTR
            addView(hourColumn, LinearLayout.LayoutParams(COLUMN_WIDTH.dp, MATCH_PARENT))
            addView(minuteColumn, LinearLayout.LayoutParams(COLUMN_WIDTH.dp, MATCH_PARENT))
        }
        addView(
            columns,
            LayoutParams(ViewGroup.LayoutParams.WRAP_CONTENT, MATCH_PARENT, Gravity.CENTER)
        )
        ViewCompat.setAccessibilityDelegate(
            this,
            object : AccessibilityDelegateCompat() {
                override fun onInitializeAccessibilityNodeInfo(
                    host: View,
                    info: AccessibilityNodeInfoCompat
                ) {
                    super.onInitializeAccessibilityNodeInfo(host, info)
                    info.addAction(AccessibilityActionCompat.ACTION_SCROLL_FORWARD)
                    info.addAction(AccessibilityActionCompat.ACTION_SCROLL_BACKWARD)
                }

                override fun performAccessibilityAction(
                    host: View,
                    action: Int,
                    args: Bundle?
                ): Boolean {
                    val step = when (action) {
                        AccessibilityNodeInfoCompat.ACTION_SCROLL_FORWARD -> 1
                        AccessibilityNodeInfoCompat.ACTION_SCROLL_BACKWARD -> -1
                        else -> return super.performAccessibilityAction(host, action, args)
                    }
                    val current = times.indexOf(findSelectedTime())
                    val time = times[(current + step).coerceIn(0, times.lastIndex)]
                    if (time == times[current]) return false
                    setTime(time, animated = false)
                    onTimeSelected?.invoke(time)
                    return true
                }
            }
        )
        updateTheme()
    }

    override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
        super.onMeasure(
            widthMeasureSpec,
            MeasureSpec.makeMeasureSpec(rowHeight * (SIDE_ROWS * 2 + 1), MeasureSpec.EXACTLY)
        )
    }

    /**
     * Turns the wheel to [time]. While the user turns a column it keeps to the finger, and a later settle reports the
     * time it lands on.
     */
    fun setTime(time: AgentDigestTime, animated: Boolean) {
        ViewCompat.setStateDescription(this, AgentDigestSettingsModel.formatTime(time))
        hourColumn.setValue(time.hour, animated)
        minuteColumn.setValue(time.minute, animated)
    }

    override fun updateTheme() {
        band.setBackgroundColor(WColor.SecondaryBackground.color, BAND_RADIUS.dp.toFloat())
        hourColumn.updateTheme()
        minuteColumn.updateTheme()
    }

    private fun findSelectedTime() =
        AgentDigestTime(hourColumn.reportedValue, minuteColumn.reportedValue)

    // A column that settles on a new value picks it with the other column's value as the wheel shows it
    private fun reportSettledTime() {
        val time = findSelectedTime()
        ViewCompat.setStateDescription(this, AgentDigestSettingsModel.formatTime(time))
        onTimeSelected?.invoke(time)
    }

    private val isMotionAllowed: Boolean
        get() {
            val isSystemMotionOn = !DEBUG_MODE ||
                Build.VERSION.SDK_INT < Build.VERSION_CODES.O ||
                ValueAnimator.areAnimatorsEnabled()
            return WGlobalStorage.getAreAnimationsActive() && isSystemMotionOn
        }

    /** A column of [values] that turns past the band and snaps to one of them */
    private inner class WheelColumn(private val values: List<Int>) : RecyclerView(context) {
        /** The value the column was last set to or settled on */
        var reportedValue = values.first()
            private set

        /** The value at the band, as the column last showed or settled on it */
        private var centeredValue: Int? = null
        private val columnLayoutManager = LinearLayoutManager(context)

        init {
            id = generateViewId()
            layoutManager = columnLayoutManager
            adapter = ValueAdapter()
            itemAnimator = null
            overScrollMode = OVER_SCROLL_NEVER
            isVerticalScrollBarEnabled = false
            // The first and last values reach the band
            clipToPadding = false
            setPadding(0, SIDE_ROWS * rowHeight, 0, SIDE_ROWS * rowHeight)
            importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_NO_HIDE_DESCENDANTS
            LinearSnapHelper().attachToRecyclerView(this)
            addOnScrollListener(object : OnScrollListener() {
                override fun onScrolled(recyclerView: RecyclerView, dx: Int, dy: Int) {
                    updateRows()
                }

                override fun onScrollStateChanged(recyclerView: RecyclerView, newState: Int) {
                    if (newState == SCROLL_STATE_IDLE) settle()
                }
            })
            // The wheel keeps a vertical drag from the scrolling sheet around it
            addOnItemTouchListener(object : SimpleOnItemTouchListener() {
                override fun onInterceptTouchEvent(rv: RecyclerView, e: MotionEvent): Boolean {
                    if (e.actionMasked == MotionEvent.ACTION_DOWN) {
                        rv.parent?.requestDisallowInterceptTouchEvent(true)
                    }
                    return false
                }
            })
            addOnLayoutChangeListener { _, _, _, _, _, _, _, _, _ -> updateRows() }
        }

        fun setValue(value: Int, animated: Boolean) {
            val position = values.indexOf(value).takeIf { it >= 0 } ?: return
            reportedValue = value
            if (scrollState != SCROLL_STATE_IDLE) return
            val centered = findCenteredChild()
            if (animated && isMotionAllowed && centered != null && isLaidOut) {
                val offset = centered.top + centered.height / 2 - height / 2
                val dy = (position - getChildAdapterPosition(centered)) * rowHeight + offset
                if (dy != 0) smoothScrollBy(0, dy)
            } else {
                columnLayoutManager.scrollToPositionWithOffset(position, 0)
                centeredValue = value
                post { updateRows() }
            }
        }

        fun updateTheme() {
            for (index in 0 until childCount) {
                (getChildAt(index) as? WLabel)?.setTextColor(WColor.PrimaryText)
            }
        }

        // Rows fade and shrink away from the band, as on a wheel; the band's row ticks as it changes
        private fun updateRows() {
            val center = height / 2f
            if (center <= 0f) return
            for (index in 0 until childCount) {
                val child = getChildAt(index)
                val distance = (child.top + child.height / 2f - center) / rowHeight
                val away = min(abs(distance), SIDE_ROWS + 1f)
                child.alpha = (1f - away * FADE_PER_ROW).coerceAtLeast(MIN_ALPHA)
                child.scaleX = 1f - away * SHRINK_PER_ROW
                child.scaleY = child.scaleX
                child.rotationX = -distance * TILT_PER_ROW
            }
            val value = findCenteredValue() ?: return
            if (value != centeredValue) {
                val isTurning = centeredValue != null && scrollState != SCROLL_STATE_IDLE
                centeredValue = value
                if (isTurning) performHapticFeedback(HapticFeedbackConstants.CLOCK_TICK)
            }
        }

        private fun settle() {
            val value = findCenteredValue() ?: return
            centeredValue = value
            if (value == reportedValue) return
            reportedValue = value
            reportSettledTime()
        }

        private fun findCenteredValue(): Int? =
            findCenteredChild()?.let { values.getOrNull(getChildAdapterPosition(it)) }

        private fun findCenteredChild(): View? {
            val center = height / 2f
            var closest: View? = null
            var closestDistance = Float.MAX_VALUE
            for (index in 0 until childCount) {
                val child = getChildAt(index)
                val distance = abs(child.top + child.height / 2f - center)
                if (distance < closestDistance) {
                    closest = child
                    closestDistance = distance
                }
            }
            return closest
        }

        private inner class ValueAdapter : Adapter<ViewHolder>() {
            override fun getItemCount() = values.size

            override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): ViewHolder {
                val label = WLabel(parent.context).apply {
                    setStyle(TEXT_SIZE)
                    gravity = Gravity.CENTER
                    layoutParams = LayoutParams(MATCH_PARENT, rowHeight)
                }
                return object : ViewHolder(label) {}
            }

            override fun onBindViewHolder(holder: ViewHolder, position: Int) {
                (holder.itemView as WLabel).apply {
                    text = AgentDigestSettingsModel.formatWheelValue(values[position])
                    setTextColor(WColor.PrimaryText)
                }
            }
        }
    }

    private companion object {
        // In dp and sp: five rows of 36, as iOS's wheel shows, the chosen one on a band 12 in from the sides
        const val ROW_HEIGHT = 36
        const val SIDE_ROWS = 2
        const val BAND_INSET = 12
        const val BAND_RADIUS = 10
        const val COLUMN_WIDTH = 64
        const val TEXT_SIZE = 22f
        const val FADE_PER_ROW = 0.3f
        const val MIN_ALPHA = 0.2f
        const val SHRINK_PER_ROW = 0.06f
        const val TILT_PER_ROW = 18f
    }
}
