package org.mytonwallet.app_air.uiagent.viewControllers.agent

import android.animation.ValueAnimator
import android.os.Build
import android.view.View
import android.view.ViewTreeObserver
import androidx.dynamicanimation.animation.FloatValueHolder
import androidx.dynamicanimation.animation.SpringAnimation
import androidx.dynamicanimation.animation.SpringForce
import androidx.recyclerview.widget.RecyclerView
import org.mytonwallet.app_air.uiagent.viewControllers.agent.views.AgentPreDrawBinding
import org.mytonwallet.app_air.walletbasecontext.DEBUG_MODE
import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage

/**
 * Glides the rows under a change of the timeline to the places it moves them to, on the spring a
 * row comes in on, while the rows above the change keep theirs. [start] notes where the rows show
 * before the change, and the frames that lay it out find how far it moved each row, which sets off
 * from where it showed. A move that starts while another runs adds to it.
 */
internal class AgentRowGlide(
    private val recyclerView: RecyclerView,
    private val findRowKey: (position: Int) -> Any?,
    private val findRow: (key: Any) -> Int,
    private val restoreRowsAbove: (shift: Int, firstGlidingRow: Int) -> Unit
) {
    private class RowMove(var offset: Float, var velocity: Float) {
        var animation: SpringAnimation? = null
    }

    private val moves = mutableMapOf<Any, RowMove>()

    // The rows under the changes being laid out, and the first of them under each change
    private val glidingKeys = mutableSetOf<Any>()
    private val firstGlidingKeys = mutableSetOf<Any>()

    // Where the rows on screen are laid out, as of the change or the last frame that laid it out
    private val shownTops = mutableMapOf<Any, Int>()
    private var scrolled = 0
    private var absorbingFrames = 0
    private var awaitedFrames = 0
    private val movedViews = mutableSetOf<View>()
    private var frameBinding: AgentPreDrawBinding? = null

    private val frameListener = ViewTreeObserver.OnPreDrawListener {
        onFrame()
        true
    }

    private val scrollListener = object : RecyclerView.OnScrollListener() {
        override fun onScrolled(recyclerView: RecyclerView, dx: Int, dy: Int) {
            scrolled += dy
        }
    }

    private val detachListener = object : RecyclerView.OnChildAttachStateChangeListener {
        override fun onChildViewAttachedToWindow(view: View) = Unit

        override fun onChildViewDetachedFromWindow(view: View) {
            if (movedViews.remove(view)) view.translationY = 0f
        }
    }

    // Debug builds land the rows at once while system animations are off, to keep E2E runs fast
    private val canGlide: Boolean
        get() = WGlobalStorage.getAreAnimationsActive() &&
            (!DEBUG_MODE || areSystemAnimatorsEnabled)

    private val areSystemAnimatorsEnabled: Boolean
        get() = Build.VERSION.SDK_INT < Build.VERSION_CODES.O || ValueAnimator.areAnimatorsEnabled()

    /** Notes where the rows show before a change above [firstPosition]'s row and those under it */
    fun start(firstPosition: Int) {
        val firstKey = findRowKey(firstPosition)
        if (firstKey == null || !canGlide || !recyclerView.isAttachedToWindow) return
        noteShownTops()
        for (index in 0 until recyclerView.childCount) {
            val child = recyclerView.getChildAt(index)
            val position = recyclerView.getChildAdapterPosition(child)
            if (position >= firstPosition) findRowKey(position)?.let(glidingKeys::add)
        }
        firstGlidingKeys.add(firstKey)
        awaitedFrames = 0
        absorbingFrames = ABSORBED_FRAMES
        if (frameBinding != null) return
        recyclerView.addOnScrollListener(scrollListener)
        recyclerView.addOnChildAttachStateChangeListener(detachListener)
        frameBinding = AgentPreDrawBinding(recyclerView, frameListener)
    }

    /** The rows land where the list lays them out */
    fun finish() {
        val running = moves.values.toList()
        moves.clear()
        running.forEach { it.animation?.cancel() }
        frameBinding?.release()
        frameBinding = null
        recyclerView.removeOnScrollListener(scrollListener)
        recyclerView.removeOnChildAttachStateChangeListener(detachListener)
        movedViews.forEach { it.translationY = 0f }
        movedViews.clear()
        stopAbsorbing()
    }

    private fun onFrame() {
        if (!canGlide) {
            finish()
            return
        }
        if (absorbingFrames > 0) {
            // A list that holds back adapter updates lays the change out a frame or two later
            if (!recyclerView.hasPendingAdapterUpdates()) {
                absorbShifts()
            } else if (++awaitedFrames > MAX_AWAITED_FRAMES) {
                stopAbsorbing()
            }
        }
        applyOffsets()
        if (absorbingFrames == 0 && moves.isEmpty()) finish()
    }

    // The frames that lay the change out. In the first, the rows above go back where they showed if
    // the list moved them down to fill its end, and each row under the change sets off from where
    // it showed. The second takes in the step a row that comes in starts its own growth with.
    private fun absorbShifts() {
        val scrolledBefore = scrolled
        if (absorbingFrames == ABSORBED_FRAMES) restoreRowsAboveChange(scrolledBefore)
        for (index in 0 until recyclerView.childCount) {
            val child = recyclerView.getChildAt(index)
            val key = findRowKey(recyclerView.getChildAdapterPosition(child)) ?: continue
            val shownTop = shownTops[key]
            if (shownTop == null || key !in glidingKeys) continue
            val shift = child.top - (shownTop - scrolledBefore)
            if (shift != 0) moveRow(key, shift)
        }
        noteShownTops()
        if (--absorbingFrames == 0) stopAbsorbing()
    }

    private fun restoreRowsAboveChange(scrolledBefore: Int) {
        val firstPosition = firstGlidingKeys.map(findRow).filter { it >= 0 }.minOrNull() ?: return
        var shift = 0
        var shiftPosition = firstPosition
        for (index in 0 until recyclerView.childCount) {
            val child = recyclerView.getChildAt(index)
            val position = recyclerView.getChildAdapterPosition(child)
            if (position < 0 || position >= shiftPosition) continue
            val shownTop = findRowKey(position)?.let(shownTops::get) ?: continue
            shift = child.top - (shownTop - scrolledBefore)
            shiftPosition = position
        }
        if (shift > 0) restoreRowsAbove(shift, firstPosition)
    }

    private fun moveRow(key: Any, shift: Int) {
        val previous = moves.remove(key)
        previous?.animation?.cancel()
        val move = RowMove((previous?.offset ?: 0f) - shift, previous?.velocity ?: 0f)
        moves[key] = move
        move.animation = SpringAnimation(FloatValueHolder(move.offset)).apply {
            spring = SpringForce(0f).apply {
                stiffness = ROW_STIFFNESS
                dampingRatio = SpringForce.DAMPING_RATIO_NO_BOUNCY
            }
            setStartVelocity(move.velocity)
            addUpdateListener { _, value, velocity ->
                move.offset = value
                move.velocity = velocity
                recyclerView.invalidate()
            }
            addEndListener { _, canceled, _, _ ->
                if (!canceled && moves[key] === move) {
                    moves.remove(key)
                    recyclerView.invalidate()
                }
            }
            start()
        }
    }

    private fun applyOffsets() {
        for (index in 0 until recyclerView.childCount) {
            val child = recyclerView.getChildAt(index)
            val move = findRowKey(recyclerView.getChildAdapterPosition(child))?.let(moves::get)
            if (move != null) {
                child.translationY = move.offset
                movedViews.add(child)
            } else if (movedViews.remove(child)) {
                child.translationY = 0f
            }
        }
    }

    private fun noteShownTops() {
        shownTops.clear()
        for (index in 0 until recyclerView.childCount) {
            val child = recyclerView.getChildAt(index)
            val key = findRowKey(recyclerView.getChildAdapterPosition(child)) ?: continue
            shownTops[key] = child.top
        }
        scrolled = 0
    }

    private fun stopAbsorbing() {
        absorbingFrames = 0
        awaitedFrames = 0
        glidingKeys.clear()
        firstGlidingKeys.clear()
        shownTops.clear()
        scrolled = 0
    }

    private companion object {
        // The stiffness rows come in on (`AgentMessageCell`, `AgentDateHeaderCell`)
        const val ROW_STIFFNESS = 500f

        // The frame that lays the change out, and the next, where a row coming in starts growing
        const val ABSORBED_FRAMES = 2
        const val MAX_AWAITED_FRAMES = 2
    }
}

/**
 * The first row of [previous] under the rows that change on the way to [items] when a question
 * waits under them: the rows from it down glide to their new places while those above stay. -1
 * when no question waits under the change, or when only answers being written change, as they
 * grow line by line.
 */
internal fun agentWaitingRowsGlideStart(
    previous: List<AgentTimelineItem>,
    items: List<AgentTimelineItem>,
    isQueued: (messageId: String) -> Boolean
): Int {
    val shared = minOf(previous.size, items.size)
    val prefix = (0 until shared).firstOrNull { previous[it] != items[it] } ?: shared
    var suffix = 0
    while (prefix + suffix < shared &&
        previous[previous.lastIndex - suffix] == items[items.lastIndex - suffix]
    ) {
        suffix++
    }
    val unchangedStart = items.size - suffix
    val isQuestionWaiting = (unchangedStart until items.size).any { index ->
        val message = (items[index] as? AgentTimelineItem.Message)?.message
        message != null && isQueued(message.id)
    }
    if (!isQuestionWaiting || isOnlyWriting(previous, items, prefix until unchangedStart)) return -1
    return previous.size - suffix
}

// Answers being written grow line by line, which the rows under them follow as they grow
private fun isOnlyWriting(
    previous: List<AgentTimelineItem>,
    items: List<AgentTimelineItem>,
    changed: IntRange
): Boolean = previous.size == items.size && changed.all { index ->
    val message = (items[index] as? AgentTimelineItem.Message)?.message
    message != null && message.isStreaming &&
        (previous[index] as? AgentTimelineItem.Message)?.message?.id == message.id
}
