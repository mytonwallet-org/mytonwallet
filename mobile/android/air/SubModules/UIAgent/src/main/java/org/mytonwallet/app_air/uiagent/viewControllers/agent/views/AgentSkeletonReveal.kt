package org.mytonwallet.app_air.uiagent.viewControllers.agent.views

import android.animation.Animator
import android.animation.AnimatorListenerAdapter
import android.animation.ValueAnimator
import android.graphics.Rect
import android.view.View
import android.view.ViewGroup
import android.view.animation.LinearInterpolator
import android.view.animation.PathInterpolator
import androidx.core.graphics.ColorUtils
import androidx.core.view.children
import androidx.core.view.doOnPreDraw
import androidx.core.view.isGone
import androidx.recyclerview.widget.RecyclerView
import kotlin.math.roundToInt
import org.mytonwallet.app_air.uiagent.viewControllers.agent.agentIncomingBubbleColor
import org.mytonwallet.app_air.uiagent.viewControllers.agent.cells.AgentHintsCell
import org.mytonwallet.app_air.uiagent.viewControllers.agent.cells.AgentMessageCell
import org.mytonwallet.app_air.uiagent.viewControllers.agent.cells.AgentNewsPostCell
import org.mytonwallet.app_air.uiagent.viewControllers.news.AgentNewsDigestCell
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage

// iOS's AgentSkeletonReveal: the column moves in 360 ms on Telegram's curve. A bubble's fill turns from the
// placeholder's over the same time, its contents appear from 140 ms and everything outside the bubbles once the column
// settles, each fade 220 ms long on Core Animation's ease-in-ease-out.
private val REVEAL_CURVE = PathInterpolator(0.38f, 0.7f, 0.125f, 1f)
private val FADE_CURVE = PathInterpolator(0.42f, 0f, 0.58f, 1f)
private const val MORPH_MS = 360f
private const val CONTENTS_DELAY_MS = 140f
private const val FADE_MS = 220f
private const val ROW_SPACING = 6
private const val SYNTHESIZED_SIDE_INSET = 16
private const val SYNTHESIZED_HEIGHT = 184
private const val SYNTHESIZED_WIDTH_FRACTION = 0.86f

private fun fadeProgress(time: Float, delay: Float): Float =
    FADE_CURVE.getInterpolation(agentRevealFadeFraction(time, delay))

internal class AgentSkeletonReveal(
    private val skeleton: AgentMessagesSkeletonView,
    private val list: RecyclerView
) {
    var isShown = false
        private set
    private val morphCleanup = mutableMapOf<View, () -> Unit>()
    private var animator: ValueAnimator? = null
    private var listCleanup: (() -> Unit)? = null

    fun show() {
        animator?.cancel()
        isShown = true
        skeleton.animate().cancel()
        skeleton.alpha = 1f
        skeleton.isGone = false
        list.alpha = 0f
    }

    fun reveal(hasRows: Boolean) {
        if (!isShown) return
        isShown = false
        val placeholders = skeleton.placeholdersInWindow()
        if (!hasRows || !WGlobalStorage.getAreAnimationsActive() || !skeleton.isAttachedToWindow) {
            list.alpha = 1f
            skeleton.isGone = true
            return
        }
        // The rows come in, at their placeholders, in the frame the placeholders go
        list.doOnPreDraw {
            if (!isShown) {
                list.alpha = 1f
                skeleton.isGone = true
                animateRows(placeholders)
            }
        }
    }

    fun hide() {
        animator?.cancel()
        isShown = false
        list.alpha = 1f
        skeleton.animate().cancel()
        skeleton.isGone = true
    }

    /** Rebinding a row ends only that row's animation; the rest of the column continues. */
    fun finishRow(row: View) {
        morphCleanup.remove(row)?.invoke()
    }

    private fun animateRows(placeholders: List<AgentMessagesSkeletonView.Placeholder>) {
        animator?.cancel()
        val listLocation = IntArray(2).also(list::getLocationInWindow)
        val updates = mutableListOf<(Float) -> Unit>()
        val surplus = mutableListOf<AgentBubbleDrawable>()
        val bubbleRows = mutableListOf<Pair<View, View>>()
        val targets = mutableListOf<AgentRevealFrame>()
        val rows = (0 until list.childCount).map(list::getChildAt).sortedByDescending { it.bottom }
        for (row in rows) {
            if (row.bottom <= list.paddingTop || row.top >= list.height) continue
            if (row is AgentHintsCell) {
                row.reveal(delay = MORPH_MS.toLong())
                continue
            }
            val bubble = when (row) {
                is AgentMessageCell -> row.skeletonRevealView
                is AgentNewsPostCell -> row.postView
                is AgentNewsDigestCell -> row.postView
                else -> null
            }
            if (bubble == null) {
                val alpha = row.alpha
                row.alpha = 0f
                morphCleanup[row] = { row.alpha = alpha }
                updates.add { time ->
                    if (morphCleanup.containsKey(row)) {
                        row.alpha = alpha * fadeProgress(time, MORPH_MS)
                    }
                }
                continue
            }
            val location = IntArray(2).also(bubble::getLocationInWindow)
            val left = (location[0] - listLocation[0]).toFloat()
            val top = (location[1] - listLocation[1]).toFloat()
            if (bubble.width <= 0 || bubble.height <= 0) continue
            bubbleRows.add(row to bubble)
            targets.add(AgentRevealFrame(left, top, left + bubble.width, top + bubble.height))
        }
        val plan = planAgentSkeletonReveal(
            placeholders.map { placeholder ->
                val frame = placeholder.frame
                AgentRevealPlaceholder(
                    AgentRevealFrame(
                        frame.left - listLocation[0],
                        frame.top - listLocation[1],
                        frame.right - listLocation[0],
                        frame.bottom - listLocation[1]
                    ),
                    placeholder.isOutgoing
                )
            },
            targets,
            viewportTop = list.paddingTop.toFloat(),
            viewportBottom = list.height - list.paddingBottom.toFloat(),
            listWidth = list.width.toFloat(),
            isRtl = LocaleController.isRTL,
            dp = 1.dp.toFloat()
        )
        // A bubble starts at its placeholder, often outside its own row, which the list would clip it to
        val wasClippingRows = list.clipChildren
        list.clipChildren = false
        listCleanup = { list.clipChildren = wasClippingRows }
        bubbleRows.forEachIndexed { index, (row, bubble) ->
            val target = targets[index]
            val match = plan.sources[index]
            // A message's own bubble turns from the placeholder's color under its fading-in contents; any other
            // surface lies under a placeholder bubble that fades out
            val fill = bubble.background as? AgentBubbleDrawable
            val fillColor = fill?.bubbleColor
            val contents = if (fill != null && bubble is ViewGroup) {
                bubble.children.map { it to it.alpha }.toList()
            } else {
                emptyList()
            }
            contents.forEach { (view, _) -> view.alpha = 0f }
            val cover = if (fill == null) {
                AgentBubbleDrawable(isOutgoing = match.isOutgoing).apply {
                    setBubbleColor(agentIncomingBubbleColor)
                    tailProgress = 1f
                }.also(bubble.overlay::add)
            } else {
                null
            }
            // The bubble keeps its layout and size: its shape is drawn at the frame that moves from the placeholder's
            // to its own, with its corners and tail as they are, and the rest of it is cut to that frame
            val sourceFrame = match.frame.offsetBy(-target.left, -target.top)
            val ownFrame = AgentRevealFrame(0f, 0f, bubble.width.toFloat(), bubble.height.toFloat())
            val frameBounds = Rect()
            val clippedParents = mutableListOf<Pair<ViewGroup, Boolean>>()
            var parent = bubble.parent as? ViewGroup
            while (parent != null && parent !== list) {
                clippedParents.add(parent to parent.clipChildren)
                parent.clipChildren = false
                parent = parent.parent as? ViewGroup
            }
            val auxiliaryViews = mutableListOf<Pair<View, Float>>()
            fun collectAuxiliary(view: View) {
                if (view === bubble) return
                if (view is ViewGroup && bubble.isDescendantOf(view)) {
                    for (childIndex in 0 until view.childCount) {
                        collectAuxiliary(view.getChildAt(childIndex))
                    }
                } else {
                    auxiliaryViews.add(view to view.alpha)
                    view.alpha = 0f
                }
            }
            collectAuxiliary(row)
            morphCleanup[row] = {
                cover?.let(bubble.overlay::remove)
                if (fill != null && fillColor != null) fill.setBubbleColor(fillColor)
                fill?.lockedBounds = null
                fill?.setBounds(0, 0, bubble.width, bubble.height)
                bubble.clipBounds = null
                contents.forEach { (view, alpha) -> view.alpha = alpha }
                auxiliaryViews.forEach { (view, alpha) -> view.alpha = alpha }
                clippedParents.forEach { (view, clipped) -> view.clipChildren = clipped }
            }
            updates.add { time ->
                if (morphCleanup.containsKey(row)) {
                    val progress = REVEAL_CURVE.getInterpolation(agentRevealMorphFraction(time))
                    val frame = agentRevealMorphFrame(sourceFrame, ownFrame, progress)
                    frameBounds.set(
                        frame.left.roundToInt(),
                        frame.top.roundToInt(),
                        frame.right.roundToInt(),
                        frame.bottom.roundToInt()
                    )
                    // Locked, as the view sets its background's bounds to its own size once laid out
                    fill?.lockedBounds = frameBounds
                    cover?.bounds = frameBounds
                    bubble.clipBounds = frameBounds
                    val fillProgress = FADE_CURVE.getInterpolation(agentRevealMorphFraction(time))
                    if (fill != null && fillColor != null) {
                        fill.setBubbleColor(
                            ColorUtils.blendARGB(agentIncomingBubbleColor, fillColor, fillProgress)
                        )
                    }
                    cover?.alpha = (255 * (1 - fillProgress)).toInt()
                    bubble.invalidate()
                    contents.forEach { (view, alpha) ->
                        view.alpha = alpha * fadeProgress(time, CONTENTS_DELAY_MS)
                    }
                    auxiliaryViews.forEach { (view, alpha) ->
                        view.alpha = alpha * fadeProgress(time, MORPH_MS)
                    }
                }
            }
        }
        // Placeholders no bubble takes slide out above the column as they fade
        for ((placeholder, destination) in plan.surplus) {
            val source = placeholder.frame
            val cover = AgentBubbleDrawable(isOutgoing = placeholder.isOutgoing).apply {
                setBubbleColor(agentIncomingBubbleColor)
                tailProgress = 1f
            }
            surplus.add(cover)
            list.overlay.add(cover)
            updates.add { time ->
                val linear = agentRevealMorphFraction(time)
                val progress = REVEAL_CURVE.getInterpolation(linear)
                val top = source.top + (destination.top - source.top) * progress
                cover.setBounds(
                    source.left.toInt(),
                    top.toInt(),
                    source.right.toInt(),
                    (top + source.height).toInt()
                )
                cover.alpha = (255 * (1 - linear)).toInt()
                cover.invalidateSelf()
            }
        }
        updates.forEach { it(0f) }
        val end = MORPH_MS + FADE_MS
        animator = ValueAnimator.ofFloat(0f, end).apply {
            duration = end.toLong()
            interpolator = LinearInterpolator()
            addUpdateListener { value -> updates.forEach { it(value.animatedValue as Float) } }
            addListener(object : AnimatorListenerAdapter() {
                override fun onAnimationEnd(animation: Animator) {
                    morphCleanup.keys.toList().forEach(::finishRow)
                    surplus.forEach(list.overlay::remove)
                    listCleanup?.invoke()
                    listCleanup = null
                }
            })
            start()
        }
    }
}

internal fun AgentRevealFrame.offsetBy(dx: Float, dy: Float) =
    AgentRevealFrame(left + dx, top + dy, right + dx, bottom + dy)

/** The frame [progress] of the way from [source] to [target], each edge moving on its own */
internal fun agentRevealMorphFrame(
    source: AgentRevealFrame,
    target: AgentRevealFrame,
    progress: Float
): AgentRevealFrame = AgentRevealFrame(
    source.left + (target.left - source.left) * progress,
    source.top + (target.top - source.top) * progress,
    source.right + (target.right - source.right) * progress,
    source.bottom + (target.bottom - source.bottom) * progress
)

/** A rectangle in the list's coordinates */
internal data class AgentRevealFrame(
    val left: Float,
    val top: Float,
    val right: Float,
    val bottom: Float
) {
    val width: Float get() = right - left
    val height: Float get() = bottom - top
}

internal data class AgentRevealPlaceholder(val frame: AgentRevealFrame, val isOutgoing: Boolean)

/**
 * Where each bubble comes from: [sources] holds one placeholder per target, in the targets' order, and [surplus] each
 * placeholder no bubble takes with where it slides to
 */
internal class AgentRevealPlan(
    val sources: List<AgentRevealPlaceholder>,
    val surplus: List<Pair<AgentRevealPlaceholder, AgentRevealFrame>>
)

/**
 * iOS's matching: the bubbles from the bottom up, [targets], take the placeholders from the bottom up, so that two
 * answers in a row don't trade places. Bubbles beyond the placeholders come from synthesized ones above them, and
 * placeholders beyond the bubbles slide out above the column, each above the last and none of them down.
 */
internal fun planAgentSkeletonReveal(
    placeholders: List<AgentRevealPlaceholder>,
    targets: List<AgentRevealFrame>,
    viewportTop: Float,
    viewportBottom: Float,
    listWidth: Float,
    isRtl: Boolean,
    dp: Float
): AgentRevealPlan {
    val remaining = placeholders.sortedByDescending { it.frame.top }.toMutableList()
    var sourceTop = viewportBottom
    var columnTop = viewportTop
    val sources = targets.map { target ->
        val source = remaining.removeFirstOrNull() ?: run {
            val width = minOf(target.width, listWidth * SYNTHESIZED_WIDTH_FRACTION)
            val inset = SYNTHESIZED_SIDE_INSET * dp
            val left = if (isRtl) listWidth - inset - width else inset
            AgentRevealPlaceholder(
                AgentRevealFrame(
                    left,
                    sourceTop - SYNTHESIZED_HEIGHT * dp,
                    left + width,
                    sourceTop
                ),
                isOutgoing = false
            )
        }
        sourceTop = source.frame.top - ROW_SPACING * dp
        columnTop = minOf(columnTop, target.top)
        source
    }
    val surplus = remaining.map { placeholder ->
        val frame = placeholder.frame
        val top = minOf(columnTop - ROW_SPACING * dp - frame.height, frame.top)
        columnTop = top
        placeholder to AgentRevealFrame(frame.left, top, frame.right, top + frame.height)
    }
    return AgentRevealPlan(sources, surplus)
}

/** How far the column's move, a bubble's fill and the surplus placeholders' fade have gone, before their curves */
internal fun agentRevealMorphFraction(timeMs: Float): Float = (timeMs / MORPH_MS).coerceIn(0f, 1f)

/** How far a fade that starts [delayMs] into the reveal has gone, before its curve */
internal fun agentRevealFadeFraction(timeMs: Float, delayMs: Float): Float =
    ((timeMs - delayMs) / FADE_MS).coerceIn(0f, 1f)

private fun View.isDescendantOf(ancestor: ViewGroup): Boolean {
    var current = parent
    while (current is View) {
        if (current === ancestor) return true
        current = current.parent
    }
    return false
}
