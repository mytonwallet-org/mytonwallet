package org.mytonwallet.app_air.uiagent.viewControllers.agent.cells

import android.annotation.SuppressLint
import android.content.Context
import android.text.SpannableStringBuilder
import android.text.Spanned
import android.text.format.DateFormat
import android.view.Gravity
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import androidx.dynamicanimation.animation.FloatValueHolder
import androidx.dynamicanimation.animation.SpringAnimation
import androidx.dynamicanimation.animation.SpringForce
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.helpers.ClipboardHelpers
import org.mytonwallet.app_air.uicomponents.helpers.HapticType
import org.mytonwallet.app_air.uicomponents.helpers.Haptics
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.helpers.spans.WTypefaceSpan
import org.mytonwallet.app_air.uicomponents.widgets.WCell
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.uicomponents.widgets.frameAsPath
import org.mytonwallet.app_air.uicomponents.widgets.menu.WMenuPopup
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletcontext.utils.AnimUtils.Companion.lerp

/** A message's time, as the device's clock shows it */
private const val CUTOUT_RADIUS = 12f
private const val CUTOUT_HORIZONTAL_INSET = 10
private const val CUTOUT_VERTICAL_INSET = 4

internal fun formatAgentChatTime(context: Context, date: Date): String {
    val pattern = if (DateFormat.is24HourFormat(context)) "H:mm" else "h:mm\u00A0a"
    return SimpleDateFormat(pattern, Locale.getDefault()).format(date)
}

/**
 * The day and time over the messages that follow a pause, the day in the heavier weight. A long
 * press offers to copy it.
 */
@SuppressLint("ViewConstructor")
class AgentDateHeaderCell(context: Context) :
    WCell(
        context,
        LayoutParams(MATCH_PARENT, WRAP_CONTENT)
    ),
    WThemedView {
    private val label = WLabel(context).apply {
        setStyle(14f)
        setLineHeight(20f)
        setTextColor(WColor.SecondaryText.color)
        gravity = Gravity.CENTER
        isSingleLine = true
    }

    var onPopupVisibilityChanged: ((Boolean) -> Unit)? = null

    /** How the chat opens the menu, which may wait for the keyboard to go */
    var menuPresenter: AgentMenuPresenter? = null

    /** Rows where the menu leaves the bubble undimmed */
    var menuRows: AgentMenuRows = { getAgentListRows(this) }

    init {
        addView(label)
        label.isHapticFeedbackEnabled = true
        label.setOnLongClickListener {
            presentAgentMenu(menuPresenter, label, null, { isAttachedToWindow }) { showCopyMenu() }
            true
        }
        setConstraints {
            toTop(label, 8f)
            toBottom(label, 4f)
            toStart(label, 40f)
            toEnd(label, 40f)
        }
    }

    private var insertAnimation: SpringAnimation? = null

    override fun updateTheme() {
        label.setTextColor(WColor.SecondaryText.color)
    }

    fun configure(date: Date, animate: Boolean = false, isDayOnly: Boolean = false) {
        label.setUserFriendlyDate(date)
        val dayPart = label.text.toString()

        val ssb = SpannableStringBuilder()
        ssb.append(
            dayPart,
            WTypefaceSpan(WFont.Medium),
            Spanned.SPAN_EXCLUSIVE_EXCLUSIVE
        )
        if (!isDayOnly) ssb.append(" ${formatAgentChatTime(context, date)}")
        label.text = ssb
        updateTheme()

        if (animate) {
            startInsertAnimation()
        }
    }

    private fun showCopyMenu() {
        val text = label.text?.toString()?.takeIf { it.isNotBlank() } ?: return
        onPopupVisibilityChanged?.invoke(true)
        WMenuPopup.present(
            label,
            listOf(
                WMenuPopup.Item(
                    org.mytonwallet.app_air.icons.R.drawable.ic_copy_30,
                    LocaleController.getString("Copy")
                ) {
                    if (ClipboardHelpers.copyToClipboard(context, "Date", text)) {
                        Haptics.play(context, HapticType.LIGHT_TAP)
                    }
                }
            ),
            positioning = WMenuPopup.Positioning.BELOW,
            centerHorizontally = true,
            backdropStyle = WMenuPopup.BackdropStyle.Dimmed,
            windowBackgroundStyle = buildAgentMenuBackdrop(
                label.frameAsPath(
                    roundRadius = CUTOUT_RADIUS.dp,
                    horizontalOffset = CUTOUT_HORIZONTAL_INSET.dp.toFloat(),
                    verticalOffset = CUTOUT_VERTICAL_INSET.dp.toFloat()
                ),
                menuRows()
            ),
            onWillDismiss = { onPopupVisibilityChanged?.invoke(false) }
        )
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
