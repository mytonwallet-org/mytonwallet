package org.mytonwallet.uihome.tabs

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Canvas
import android.graphics.Matrix
import android.graphics.Rect
import android.view.MotionEvent
import android.view.View
import android.view.ViewTreeObserver
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt
import org.mytonwallet.app_air.uicomponents.base.WNavigationController

/**
 * Lies over a band of the root's chrome, the tabs or the toolbar, and draws there the screens pushed over the Agent
 * list, so that chrome shows as part of the list: a chat coming in covers it and one going away uncovers it, dimmed
 * with the list. The covers of one stack share a [group], which keeps the stack from drawing those screens in the
 * bands they cover.
 */
@SuppressLint("ViewConstructor")
internal class AgentListCoverView(
    context: Context,
    private val group: AgentListCoverGroup,
    // The Agent tab's stack while the chrome under the band shows
    private val listNavigation: () -> WNavigationController?
) : View(context) {
    init {
        id = generateViewId()
        importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_NO
        setWillNotDraw(false)
    }

    /** Called before every frame drawn */
    var onFrame: (() -> Unit)? = null

    private val ownLocation = IntArray(2)
    private val navigationLocation = IntArray(2)
    private var wasCovering = false

    // The screens over the list move on their own, so the cover draws anew on every frame while there are any
    private val preDrawListener = ViewTreeObserver.OnPreDrawListener {
        val covering = isCovering
        if (covering || wasCovering) invalidate()
        wasCovering = covering
        onFrame?.invoke()
        group.update()
        true
    }

    override fun onAttachedToWindow() {
        super.onAttachedToWindow()
        group.add(this)
        viewTreeObserver.addOnPreDrawListener(preDrawListener)
    }

    override fun onDetachedFromWindow() {
        viewTreeObserver.removeOnPreDrawListener(preDrawListener)
        group.remove(this)
        super.onDetachedFromWindow()
    }

    /** The stack whose screens over the list the cover draws, while the list shows with screens over it */
    val coveredNavigation: WNavigationController?
        get() = listNavigation()?.takeIf { agentListIndex(it) >= 0 }

    /** Whether the list shows with screens over it, coming in or going away */
    val isCovering: Boolean
        get() = coveredNavigation != null

    override fun onDraw(canvas: Canvas) {
        val navigation = listNavigation() ?: return
        val start = agentListIndex(navigation)
        if (start < 0) return
        getLocationInWindow(ownLocation)
        navigation.getLocationInWindow(navigationLocation)
        val offsetX = navigationLocation[0] - ownLocation[0]
        val offsetY = navigationLocation[1] - ownLocation[1]
        canvas.save()
        canvas.clipRect(0, 0, width, height)
        // `View.draw` leaves out the clip the group sets for the stack, so the band shows what the stack leaves out
        for (index in start + 1 until navigation.childCount) {
            val child = navigation.getChildAt(index)
            if (child.visibility != VISIBLE || child.alpha <= 0f) continue
            val count = canvas.save()
            canvas.translate((offsetX + child.left).toFloat(), (offsetY + child.top).toFloat())
            canvas.concat(child.matrix)
            if (child.alpha < 1f) {
                canvas.saveLayerAlpha(
                    0f,
                    0f,
                    child.width.toFloat(),
                    child.height.toFloat(),
                    (child.alpha * 255).roundToInt()
                )
            }
            child.draw(canvas)
            canvas.restoreToCount(count)
        }
        canvas.restore()
    }

    // The chrome under a screen takes no taps
    @SuppressLint("ClickableViewAccessibility")
    override fun onTouchEvent(event: MotionEvent): Boolean = isCovering
}

/**
 * The covers lying over one Agent stack's chrome. While they cover, the stack draws the screens over its list only
 * between their bands, so in a band the dim and a screen fading in fall on the list once, as the cover draws them over
 * the chrome, the same as everywhere else
 */
internal class AgentListCoverGroup {
    private val covers = ArrayList<AgentListCoverView>()

    // The screens the stack draws clipped, this frame and the last
    private var clippedViews = ArrayList<View>()
    private var lastClippedViews = ArrayList<View>()
    private val coverLocation = IntArray(2)
    private val navigationLocation = IntArray(2)
    private val inverse = Matrix()
    private val points = FloatArray(4)
    private val clip = Rect()

    fun add(cover: AgentListCoverView) {
        if (cover !in covers) covers.add(cover)
    }

    fun remove(cover: AgentListCoverView) {
        covers.remove(cover)
        update()
    }

    /** Clips the screens over the list to the rows between the covering bands, and releases those no longer over it */
    fun update() {
        var navigation: WNavigationController? = null
        // The rows of the window the stack keeps drawing the screens in
        var keptTop = Int.MIN_VALUE
        var keptBottom = Int.MAX_VALUE
        for (cover in covers) {
            val covered = cover.coveredNavigation ?: continue
            if (cover.height <= 0 || (navigation != null && covered !== navigation)) continue
            navigation = covered
            cover.getLocationInWindow(coverLocation)
            covered.getLocationInWindow(navigationLocation)
            val top = coverLocation[1]
            val bottom = top + cover.height
            // A band in the stack's upper half covers its top edge, one in its lower half its bottom edge
            if (top + bottom < 2 * navigationLocation[1] + covered.height) {
                keptTop = max(keptTop, bottom)
            } else {
                keptBottom = min(keptBottom, top)
            }
        }
        if (navigation != null) {
            navigation.getLocationInWindow(navigationLocation)
            for (index in agentListIndex(navigation) + 1 until navigation.childCount) {
                val child = navigation.getChildAt(index)
                clipChild(child, keptTop, keptBottom)
                clippedViews.add(child)
            }
        }
        for (view in lastClippedViews) {
            if (view !in clippedViews) view.clipBounds = null
        }
        lastClippedViews.clear()
        val swap = lastClippedViews
        lastClippedViews = clippedViews
        clippedViews = swap
    }

    // Keeps the child's rows that lie between the window rows `top` and `bottom`, in its own coordinates
    private fun clipChild(child: View, top: Int, bottom: Int) {
        val originY = navigationLocation[1] + child.top
        points[0] = 0f
        points[1] = if (top == Int.MIN_VALUE) 0f else (top - originY).toFloat()
        points[2] = 0f
        points[3] = if (bottom == Int.MAX_VALUE) 0f else (bottom - originY).toFloat()
        if (child.matrix.invert(inverse)) inverse.mapPoints(points)
        val clipTop = if (top == Int.MIN_VALUE) {
            0
        } else {
            points[1].roundToInt().coerceIn(0, child.height)
        }
        val clipBottom = if (bottom == Int.MAX_VALUE) {
            child.height
        } else {
            points[3].roundToInt().coerceIn(clipTop, child.height)
        }
        clip.set(0, clipTop, child.width, clipBottom)
        child.clipBounds = clip
    }
}

// Where the list's own view lies among the stack's children, while views lie over it
internal fun agentListIndex(navigation: WNavigationController): Int {
    val listView = navigation.viewControllers.firstOrNull()?.view ?: return -1
    val index = navigation.indexOfChild(listView)
    return if (index >= 0 && index < navigation.childCount - 1) index else -1
}
