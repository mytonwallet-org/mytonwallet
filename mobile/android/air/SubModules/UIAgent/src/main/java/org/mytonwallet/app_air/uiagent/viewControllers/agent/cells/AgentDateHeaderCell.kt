package org.mytonwallet.app_air.uiagent.viewControllers.agent.cells

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Color
import android.text.SpannableStringBuilder
import android.text.Spanned
import android.text.format.DateFormat
import android.view.Gravity
import android.view.ViewGroup
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import androidx.core.view.isInvisible
import androidx.dynamicanimation.animation.FloatValueHolder
import androidx.dynamicanimation.animation.SpringAnimation
import androidx.dynamicanimation.animation.SpringForce
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import kotlin.math.roundToInt
import org.mytonwallet.app_air.uiagent.viewControllers.threadList.AgentThreadDateFormatting
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.glass.GlassFlavor
import org.mytonwallet.app_air.uicomponents.glass.GlassProvider
import org.mytonwallet.app_air.uicomponents.glass.WGlassView
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
import org.mytonwallet.app_air.walletbasecontext.theme.ThemeManager
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletcontext.utils.AnimUtils.Companion.lerp
import org.mytonwallet.app_air.walletcontext.utils.colorWithAlpha

private const val CUTOUT_RADIUS = 12f
private const val CUTOUT_HORIZONTAL_INSET = 10
private const val CUTOUT_VERTICAL_INSET = 4

// Telegram's date bubble: a 17 sp line of 14 sp text, 3 dp above and below it and 8 dp at its sides,
// 11 dp corners and 4 dp around it
private const val CAPSULE_LINE_HEIGHT = 17f
private const val CAPSULE_HORIZONTAL_PADDING = 8
private const val CAPSULE_VERTICAL_PADDING = 3
private const val CAPSULE_RADIUS = 11f
internal const val AGENT_DAY_CAPSULE_MARGIN = 4f

// Denser than iOS's `AgentDateCapsuleView` (white at 80% by day, black at 20% by night), whose blur material darkens
// on its own: over the app's plain frosted glass the posts' pictures scrolling under a thinner fill flash through it
private const val FLOATING_CAPSULE_LIGHT_ALPHA = 0.9f
private const val FLOATING_CAPSULE_DARK_ALPHA = 0.6f

/** A message's time, as the device's clock shows it */
internal fun formatAgentChatTime(context: Context, date: Date): String {
    val pattern = if (DateFormat.is24HourFormat(context)) "H:mm" else "h:mm\u00A0a"
    return SimpleDateFormat(pattern, Locale.getDefault()).format(date)
}

/**
 * The day and time over the messages that follow a pause, the day in the heavier weight, or with [isDayCapsule] the
 * News feed's day alone in a capsule, as Telegram's date bubbles in a chat. The capsule in the list shows its text
 * alone on the feed's own background, and only the one pinned over the list ([isFloating]) has a fill: a little
 * see-through over a blur of the posts scrolling under it. A long press offers to copy it, except on the
 * pinned capsule, which takes no touches.
 */
@SuppressLint("ViewConstructor")
class AgentDateHeaderCell(
    context: Context,
    private val isDayCapsule: Boolean = false,
    isFloating: Boolean = false
) : WCell(context, LayoutParams(MATCH_PARENT, WRAP_CONTENT)),
    WThemedView {
    private val label = WLabel(context).apply {
        setStyle(14f)
        setLineHeight(if (isDayCapsule) CAPSULE_LINE_HEIGHT else 20f)
        // Dates read in the text's own colour on every platform and theme
        setTextColor(WColor.PrimaryText.color)
        gravity = Gravity.CENTER
        isSingleLine = true
        if (isDayCapsule) {
            setPadding(
                CAPSULE_HORIZONTAL_PADDING.dp,
                CAPSULE_VERTICAL_PADDING.dp,
                CAPSULE_HORIZONTAL_PADDING.dp,
                CAPSULE_VERTICAL_PADDING.dp
            )
        }
    }

    // The app's plain frosted glass under the pinned capsule, which blurs nothing until [setupBlurWith] names the list
    private val floatingCapsuleGlass: WGlassView?

    var onPopupVisibilityChanged: ((Boolean) -> Unit)? = null

    /** How the chat opens the menu, which may wait for the keyboard to go */
    var menuPresenter: AgentMenuPresenter? = null

    /** Rows where the menu leaves the bubble undimmed */
    var menuRows: AgentMenuRows = { getAgentListRows(this) }

    init {
        addView(label)
        floatingCapsuleGlass = if (isFloating) createFloatingCapsuleGlass() else null
        // A pill: its ends are half its height round, whatever the text's metrics make that height
        floatingCapsuleGlass?.let { glass ->
            label.addOnLayoutChangeListener { _, _, top, _, bottom, _, _, _, _ ->
                glass.setRadius((bottom - top) / 2f)
            }
        }
        if (!isFloating) {
            label.isHapticFeedbackEnabled = true
            label.setOnLongClickListener {
                presentAgentMenu(menuPresenter, label, null, { isAttachedToWindow }) {
                    showCopyMenu()
                }
                true
            }
        }
        setConstraints {
            toTop(label, if (isDayCapsule) AGENT_DAY_CAPSULE_MARGIN else 8f)
            // The pinned capsule's glass reaches past the capsule and makes its cell taller, so the capsule hangs from
            // the top alone there and stands as far down from the cell's top as the list's own capsule does
            if (!isFloating) toBottom(label, if (isDayCapsule) AGENT_DAY_CAPSULE_MARGIN else 4f)
            toStart(label, 40f)
            toEnd(label, 40f)
        }
    }

    // The glass under the pinned capsule takes the capsule's frame in the capsule's own layout pass, so a day of another
    // width never shows over the last one's glass
    override fun onLayout(changed: Boolean, left: Int, top: Int, right: Int, bottom: Int) {
        super.onLayout(changed, left, top, right, bottom)
        val glass = floatingCapsuleGlass ?: return
        val padding = WGlassView.GLASS_PADDING_DP.dp
        glass.layout(
            label.left - padding,
            label.top - padding,
            label.right + padding,
            label.bottom + padding
        )
    }

    private fun createFloatingCapsuleGlass() = WGlassView.attachTo(
        label,
        CAPSULE_RADIUS.dp,
        GlassProvider(
            panelColor = { if (ThemeManager.isDark) Color.BLACK else Color.WHITE },
            panelAlpha = { getFloatingCapsuleAlpha() },
            rim = false,
            shadow = false
        ),
        null,
        flavor = GlassFlavor.FROSTED_PLAIN
    ).apply {
        liquidGlass = false
        noBlurColor = getFloatingCapsuleColor()
    }

    private var insertAnimation: SpringAnimation? = null

    override fun updateTheme() {
        label.setTextColor(WColor.PrimaryText.color)
        floatingCapsuleGlass?.let {
            it.noBlurColor = getFloatingCapsuleColor()
            it.updateTheme()
        }
    }

    /** Blurs [root], the list that scrolls under the pinned capsule */
    fun setupBlurWith(root: ViewGroup) {
        floatingCapsuleGlass?.setupWith(root)
    }

    /** The height of a day's row in the list: the capsule and the space above and below it */
    val capsuleRowHeight: Int
        get() = (label.height + 2 * AGENT_DAY_CAPSULE_MARGIN.dp).roundToInt()

    private val capsuleLocation = IntArray(2)

    /**
     * Where the capsule's top shows on screen, every parent's position and transform included, for the pinned one to
     * take its place exactly
     */
    fun getCapsuleScreenTop(): Int {
        label.getLocationOnScreen(capsuleLocation)
        return capsuleLocation[1]
    }

    /** Hides the capsule while the one pinned over the feed stands in for it */
    fun setCapsuleHidden(isHidden: Boolean) {
        label.isInvisible = isHidden
    }

    fun configure(date: Date, animate: Boolean = false) {
        val dayPart = AgentThreadDateFormatting.formatDayText(
            date,
            Date(),
            today = LocaleController.getString("Today"),
            yesterday = LocaleController.getString("Yesterday"),
            langCode = LocaleController.activeLanguage.langCode
        )

        val ssb = SpannableStringBuilder()
        ssb.append(
            dayPart,
            WTypefaceSpan(WFont.Medium),
            Spanned.SPAN_EXCLUSIVE_EXCLUSIVE
        )
        if (!isDayCapsule) ssb.append(" ${formatAgentChatTime(context, date)}")
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
                if (isDayCapsule) {
                    label.frameAsPath(roundRadius = label.height / 2f)
                } else {
                    label.frameAsPath(
                        roundRadius = CUTOUT_RADIUS.dp,
                        horizontalOffset = CUTOUT_HORIZONTAL_INSET.dp.toFloat(),
                        verticalOffset = CUTOUT_VERTICAL_INSET.dp.toFloat()
                    )
                },
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

private fun getFloatingCapsuleAlpha(): Float =
    if (ThemeManager.isDark) FLOATING_CAPSULE_DARK_ALPHA else FLOATING_CAPSULE_LIGHT_ALPHA

// The fill without the blur, where the app's glass does not blur
private fun getFloatingCapsuleColor(): Int {
    val color = if (ThemeManager.isDark) Color.BLACK else Color.WHITE
    return color.colorWithAlpha((getFloatingCapsuleAlpha() * 255).roundToInt())
}
