package org.mytonwallet.app_air.uiagent.viewControllers.agent.views

import android.animation.Animator
import android.animation.AnimatorListenerAdapter
import android.animation.ValueAnimator
import android.graphics.RectF
import android.view.View
import android.view.ViewGroup
import android.view.animation.LinearInterpolator
import android.view.animation.PathInterpolator
import androidx.core.view.doOnPreDraw
import androidx.core.view.isGone
import androidx.recyclerview.widget.RecyclerView
import org.mytonwallet.app_air.uiagent.viewControllers.agent.agentIncomingBubbleColor
import org.mytonwallet.app_air.uiagent.viewControllers.agent.cells.AgentHintsCell
import org.mytonwallet.app_air.uiagent.viewControllers.agent.cells.AgentMessageCell
import org.mytonwallet.app_air.uiagent.viewControllers.agent.cells.AgentNewsPostCell
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage

private val REVEAL_CURVE = PathInterpolator(0.38f, 0.7f, 0.125f, 1f)

internal class AgentSkeletonReveal(
    private val skeleton: AgentMessagesSkeletonView,
    private val list: RecyclerView
) {
    var isShown = false
        private set
    private val morphCleanup = mutableMapOf<View, () -> Unit>()
    private var animator: ValueAnimator? = null

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
        list.alpha = 1f
        if (!hasRows || !WGlobalStorage.getAreAnimationsActive() || !skeleton.isAttachedToWindow) {
            skeleton.isGone = true
            return
        }
        list.doOnPreDraw {
            if (!isShown) {
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
        val remaining = placeholders.sortedByDescending { it.frame.top }.toMutableList()
        val listLocation = IntArray(2).also(list::getLocationInWindow)
        var sourceTop = list.height - list.paddingBottom.toFloat()
        var targetTop = list.paddingTop.toFloat()
        val updates = mutableListOf<(Float) -> Unit>()
        val surplus = mutableListOf<AgentBubbleDrawable>()
        val rows = (0 until list.childCount).map(list::getChildAt).sortedByDescending { it.bottom }
        for (row in rows) {
            if (row.bottom <= list.paddingTop || row.top >= list.height) continue
            if (row is AgentHintsCell) {
                row.reveal(delay = 360)
                continue
            }
            val bubble = when (row) {
                is AgentMessageCell -> row.skeletonRevealView
                is AgentNewsPostCell -> row.postView
                else -> null
            }
            if (bubble == null) {
                val alpha = row.alpha
                row.alpha = 0f
                morphCleanup[row] = { row.alpha = alpha }
                updates.add { time ->
                    if (morphCleanup.containsKey(row)) {
                        row.alpha =
                            alpha * ((time - 360) / 180).coerceIn(0f, 1f)
                    }
                }
                continue
            }
            val location = IntArray(2).also(bubble::getLocationInWindow)
            val target = RectF(
                (location[0] - listLocation[0]).toFloat(),
                (location[1] - listLocation[1]).toFloat(),
                (location[0] - listLocation[0] + bubble.width).toFloat(),
                (location[1] - listLocation[1] + bubble.height).toFloat()
            )
            if (target.width() <= 0 || target.height() <= 0) continue
            val placeholder = remaining.removeFirstOrNull()
            val source = placeholder?.let {
                RectF(it.frame).apply {
                    offset(-listLocation[0].toFloat(), -listLocation[1].toFloat())
                }
            } ?: run {
                val width = minOf(target.width(), list.width * 0.86f)
                val left = if (LocaleController.isRTL) {
                    list.width - 16.dp - width
                } else {
                    16.dp.toFloat()
                }
                RectF(left, sourceTop - 184.dp, left + width, sourceTop)
            }
            sourceTop = source.top - 10.dp
            targetTop = minOf(targetTop, target.top)
            val cover = AgentBubbleDrawable(isOutgoing = placeholder?.isOutgoing ?: false).apply {
                setBubbleColor(agentIncomingBubbleColor)
                tailProgress = 1f
                setBounds(0, 0, bubble.width, bubble.height)
            }
            bubble.overlay.add(cover)
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
                    for (index in 0 until view.childCount) collectAuxiliary(view.getChildAt(index))
                } else {
                    auxiliaryViews.add(view to view.alpha)
                    view.alpha = 0f
                }
            }
            collectAuxiliary(row)
            val startScaleX = source.width() / target.width()
            val startScaleY = source.height() / target.height()
            morphCleanup[row] = {
                bubble.overlay.remove(cover)
                bubble.translationX = 0f
                bubble.translationY = 0f
                bubble.scaleX = 1f
                bubble.scaleY = 1f
                auxiliaryViews.forEach { (view, alpha) -> view.alpha = alpha }
                clippedParents.forEach { (view, clipped) -> view.clipChildren = clipped }
            }
            updates.add { time ->
                if (morphCleanup.containsKey(row)) {
                    val progress = REVEAL_CURVE.getInterpolation((time / 360).coerceIn(0f, 1f))
                    bubble.translationX = (source.centerX() - target.centerX()) * (1 - progress)
                    bubble.translationY = (source.centerY() - target.centerY()) * (1 - progress)
                    bubble.scaleX = 1 + (startScaleX - 1) * (1 - progress)
                    bubble.scaleY = 1 + (startScaleY - 1) * (1 - progress)
                    cover.alpha = (255 * (1 - ((time - 140) / 220).coerceIn(0f, 1f))).toInt()
                    bubble.invalidate()
                    auxiliaryViews.forEach { (view, alpha) ->
                        view.alpha = alpha * ((time - 360) / 180).coerceIn(0f, 1f)
                    }
                }
            }
        }
        for (placeholder in remaining) {
            val source = RectF(placeholder.frame).apply {
                offset(-listLocation[0].toFloat(), -listLocation[1].toFloat())
            }
            val destinationTop = targetTop - 10.dp - source.height()
            targetTop = destinationTop
            val cover = AgentBubbleDrawable(isOutgoing = placeholder.isOutgoing).apply {
                setBubbleColor(agentIncomingBubbleColor)
                tailProgress = 1f
            }
            surplus.add(cover)
            list.overlay.add(cover)
            updates.add { time ->
                val progress = REVEAL_CURVE.getInterpolation((time / 360).coerceIn(0f, 1f))
                val top = source.top + (destinationTop - source.top) * progress
                cover.setBounds(
                    source.left.toInt(),
                    top.toInt(),
                    source.right.toInt(),
                    (
                        top +
                            source.height()
                        ).toInt()
                )
                cover.alpha = (255 * (1 - progress)).toInt()
                cover.invalidateSelf()
            }
        }
        updates.forEach { it(0f) }
        animator = ValueAnimator.ofFloat(0f, 540f).apply {
            duration = 540
            interpolator = LinearInterpolator()
            addUpdateListener { value -> updates.forEach { it(value.animatedValue as Float) } }
            addListener(object : AnimatorListenerAdapter() {
                override fun onAnimationEnd(animation: Animator) {
                    morphCleanup.keys.toList().forEach(::finishRow)
                    surplus.forEach(list.overlay::remove)
                }
            })
            start()
        }
    }
}

private fun View.isDescendantOf(ancestor: ViewGroup): Boolean {
    var current = parent
    while (current is View) {
        if (current === ancestor) return true
        current = current.parent
    }
    return false
}
