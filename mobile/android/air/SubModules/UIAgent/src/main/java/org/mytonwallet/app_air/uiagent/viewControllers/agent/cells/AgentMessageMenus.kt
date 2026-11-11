package org.mytonwallet.app_air.uiagent.viewControllers.agent.cells

import android.content.Context
import android.graphics.Path
import android.graphics.Rect
import android.graphics.RectF
import android.graphics.drawable.Drawable
import android.os.SystemClock
import android.text.Spanned
import android.text.style.ClickableSpan
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import android.widget.FrameLayout
import android.widget.TextView
import androidx.core.view.ViewCompat
import androidx.core.view.WindowInsetsCompat
import java.util.Date
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt
import org.mytonwallet.app_air.uicomponents.R as UIComponentsR
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.extensions.getLocationInWindow
import org.mytonwallet.app_air.uicomponents.helpers.PopupHelpers
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.helpers.spans.ExtraHitLinkMovementMethod
import org.mytonwallet.app_air.uicomponents.helpers.spans.WClickableSpan
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.uicomponents.widgets.menu.WMenuPopup
import org.mytonwallet.app_air.uicomponents.widgets.menu.WMenuPopupView
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.utils.ApplicationContextHolder
import org.mytonwallet.app_air.walletbasecontext.utils.Vec2i
import org.mytonwallet.app_air.walletbasecontext.utils.vec2i
import org.mytonwallet.app_air.walletbasecontext.utils.x
import org.mytonwallet.app_air.walletbasecontext.utils.y

private const val HEADER_HEIGHT = 40
private const val HEADER_MIN_WIDTH = 144
private const val HEADER_INSET = 16
private const val HEADER_TEXT_SHIFT = 3f

/** The head of a message's menu: the day and time it was sent, in the accent */
internal fun buildAgentMessageMenuHeader(context: Context, date: Date): WMenuPopup.Item =
    WMenuPopup.Item(
        WMenuPopup.Item.Config.CustomView(
            FrameLayout(context).apply {
                minimumWidth = HEADER_MIN_WIDTH.dp
                addView(
                    WLabel(context).apply {
                        setStyle(14f, WFont.Medium)
                        setTextColor(WColor.Tint)
                        translationY = HEADER_TEXT_SHIFT.dp
                        setUserFriendlyDate(date)
                        text = "$text, ${formatAgentChatTime(context, date)}"
                        setSingleLine()
                    },
                    FrameLayout.LayoutParams(WRAP_CONTENT, WRAP_CONTENT).apply {
                        gravity = Gravity.CENTER_VERTICAL or Gravity.START
                        marginStart = HEADER_INSET.dp
                        marginEnd = HEADER_INSET.dp
                    }
                )
            },
            height = HEADER_HEIGHT.dp
        )
    )

// The menu keeps this far under the list's top, as Telegram's chat menu does
private const val MENU_LIST_TOP_INSET = 24

// A click lands right after the finger lifts; one later, as from TalkBack or a key, has no finger to open at
private const val CLICK_AFTER_LIFT_MS = 300L

/** Where the finger went down on a message's views, for the message's menu to open there */
internal class AgentMenuTouch {
    private var point: Vec2i? = null
    private var isFingerDown = false
    private var liftTime = 0L

    private val currentPoint: Vec2i?
        get() = point.takeIf {
            isFingerDown || SystemClock.uptimeMillis() - liftTime < CLICK_AFTER_LIFT_MS
        }

    /** Follows a touch event that [cell] dispatches */
    fun track(cell: View, event: MotionEvent) {
        when (event.actionMasked) {
            MotionEvent.ACTION_DOWN -> {
                point = cell.getWindowPoint(event)
                isFingerDown = true
            }

            MotionEvent.ACTION_UP -> {
                isFingerDown = false
                liftTime = event.eventTime
            }

            MotionEvent.ACTION_CANCEL -> {
                point = null
                isFingerDown = false
            }
        }
    }

    /** Whether the finger is, or just was, on [view] */
    fun isOn(view: View): Boolean = view.isUnderWindowPoint(currentPoint)

    /** Whether the finger is, or just was, on one of [label]'s links */
    fun isOnLink(label: TextView): Boolean = label.hasLinkAt(currentPoint)

    fun linkAt(label: TextView): String? {
        val point = currentPoint ?: return null
        val text = label.text as? Spanned ?: return null
        val movement = label.movementMethod as? ExtraHitLinkMovementMethod ?: return null
        val origin = label.getLocationInWindow()
        return movement.findLinks(
            label,
            text,
            (point.x - origin.x).toFloat(),
            (point.y - origin.y).toFloat()
        )
            .filterIsInstance<WClickableSpan>().firstOrNull()?.url
    }

    /** The finger's window point for one menu while it lies on [bubble]; null opens the menu at the bubble */
    fun take(bubble: View): Vec2i? {
        val touch = currentPoint?.takeIf(bubble::isUnderWindowPoint)
        point = null
        return touch
    }
}

/**
 * How the chat opens a row's menu: at once, or once the keyboard has gone, so that the chat settles under the menu
 * before it opens
 */
internal typealias AgentMenuPresenter = (open: () -> Unit) -> Unit

/**
 * Opens a row's menu through [presenter], from the finger at [touch], a window point that moves with [bubble] while
 * the menu waits. The menu doesn't open when [isStillShown] says the row has gone or shows another message.
 */
internal fun presentAgentMenu(
    presenter: AgentMenuPresenter?,
    bubble: View,
    touch: Vec2i?,
    isStillShown: () -> Boolean,
    open: (touch: Vec2i?) -> Unit
) {
    val start = bubble.getLocationInWindow()
    val offset = touch?.let { vec2i(it.x - start.x, it.y - start.y) }
    val show = {
        if (isStillShown()) {
            val location = bubble.getLocationInWindow()
            open(offset?.let { vec2i(location.x + it.x, location.y + it.y) })
        }
    }
    presenter?.invoke(show) ?: show()
}

/** Makes a tap on this view open its message's menu, and tells the chat's tap-to-dismiss that it isn't a button */
internal fun View.setMessageMenuTapListener(listener: View.OnClickListener) {
    setOnClickListener(listener)
    setTag(UIComponentsR.id.agent_message_menu_tap, true)
}

/** Whether a tap on this view opens its message's menu */
internal val View.isMessageMenuTapTarget: Boolean
    get() = getTag(UIComponentsR.id.agent_message_menu_tap) == true

/** The window point of [event], a touch in this view's own coordinates */
private fun View.getWindowPoint(event: MotionEvent): Vec2i {
    val location = getLocationInWindow()
    return vec2i(location.x + event.x.roundToInt(), location.y + event.y.roundToInt())
}

/** Whether a finger at [point], a window point, lands on one of this text's links */
private fun TextView.hasLinkAt(point: Vec2i?): Boolean {
    if (point == null) return false
    val spanned = text as? Spanned ?: return false
    val location = getLocationInWindow()
    val x = (point.x - location.x).toFloat()
    val y = (point.y - location.y).toFloat()
    (movementMethod as? ExtraHitLinkMovementMethod)?.let {
        return it.findLinks(this, spanned, x, y).isNotEmpty()
    }
    val layout = layout ?: return false
    val line = layout.getLineForVertical((y - totalPaddingTop + scrollY).toInt())
    val offset = layout.getOffsetForHorizontal(line, x - totalPaddingLeft + scrollX)
    return spanned.getSpans(offset, offset, ClickableSpan::class.java).isNotEmpty()
}

/** Whether [point], a window point, is inside this view */
private fun View.isUnderWindowPoint(point: Vec2i?): Boolean {
    if (point == null || !isShown) return false
    val location = getLocationInWindow()
    return point.x in location.x until location.x + width &&
        point.y in location.y until location.y + height
}

internal typealias AgentMenuRows = () -> IntRange

internal fun getAgentListRows(row: View): IntRange {
    val list = row.parent as? View ?: return 0 until Int.MAX_VALUE
    val top = list.getLocationInWindow().y
    return top + list.paddingTop until top + list.height - list.paddingBottom
}

/** The surface of the menu that holds this view, which moves as the menu appears and goes */
internal fun View.findMenuSurface(): View? = generateSequence(parent) { it.parent }
    .filterIsInstance<WMenuPopupView>()
    .firstOrNull()
    ?.parent as? View

/** Dims the whole window except [cutoutPath] within [rows], with [lifted] drawn over the dim */
internal fun buildAgentMenuBackdrop(
    cutoutPath: Path,
    rows: IntRange,
    lifted: Drawable? = null
): WMenuPopup.BackgroundStyle = WMenuPopup.BackgroundStyle.Cutout(
    cutoutPath.clipToRows(rows.first.toFloat(), (rows.last + 1).toFloat()),
    lifted
)

/** The part of the window that popups keep inside, above the keyboard */
internal fun getAgentPopupArea(): Rect {
    val host = PopupHelpers.popupHost
        ?: return Rect(0, 0, ApplicationContextHolder.screenWidth, Int.MAX_VALUE)
    val location = host.getLocationInWindow()
    val area = host.getContentAreaBounds().apply { offset(location.x, location.y) }
    val keyboard = ViewCompat.getRootWindowInsets(host)
        ?.getInsets(WindowInsetsCompat.Type.ime())?.bottom ?: 0
    if (keyboard > 0) area.bottom = min(area.bottom, host.rootView.height - keyboard)
    return area
}

/**
 * Places a message's menu from the finger at [touch], a window point, with [placeAgentMenu]; without a touch, as from
 * TalkBack, it hangs from [bubble]'s centre. The menu keeps [MENU_LIST_TOP_INSET] dp under the top of [row]'s list.
 * With [hasCloud], the reaction cloud rides over the menu and keeps under [visibleTop], the list's top under the
 * header; [onPlaced] gets where both go.
 */
internal fun buildAgentMenuPlacement(
    row: View,
    bubble: View,
    touch: Vec2i?,
    hasCloud: Boolean = false,
    visibleTop: Int = 0,
    onPlaced: (AgentMenuPlacement) -> Unit = {}
): (width: Int, height: Int) -> Vec2i = { width, height ->
    val area = getAgentPopupArea()
    val point = touch ?: bubble.getLocationInWindow().let {
        vec2i(it.x + bubble.width / 2, it.y + bubble.height / 2)
    }
    val listTop = (row.parent as? View)?.getLocationInWindow()?.y ?: area.top
    val placement = placeAgentMenu(
        touchX = point.x,
        touchY = point.y,
        width = width,
        height = height,
        areaLeft = area.left,
        areaTop = area.top,
        areaRight = area.right,
        areaBottom = area.bottom,
        minTop = max(area.top, listTop + MENU_LIST_TOP_INSET.dp),
        cloudMinTop = visibleTop,
        hasCloud = hasCloud,
        isRtl = bubble.layoutDirection == View.LAYOUT_DIRECTION_RTL,
        density = bubble.resources.displayMetrics.density
    )
    onPlaced(placement)
    vec2i(placement.left, placement.top)
}

private fun Path.clipToRows(top: Float, bottom: Float): Path {
    val bounds = RectF().also { computeBounds(it, true) }
    if (bounds.top >= top && bounds.bottom <= bottom) return this
    val visible = Path().apply {
        addRect(bounds.left, top, bounds.right, bottom, Path.Direction.CW)
    }
    return Path(this).apply { op(visible, Path.Op.INTERSECT) }
}
