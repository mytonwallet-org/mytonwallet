package org.mytonwallet.app_air.uiagent.viewControllers.threadList

import android.view.View
import android.view.ViewPropertyAnimator
import android.view.animation.AccelerateDecelerateInterpolator
import androidx.recyclerview.widget.RecyclerView
import androidx.recyclerview.widget.SimpleItemAnimator
import org.mytonwallet.app_air.walletcontext.helpers.WInterpolator

/**
 * How the Agent list shows its changes. Changes that come with the data are applied at once, so rows stay where they
 * are. The first chats fade in over the placeholder. Pins, unpins and deletions move the rows on a critically damped
 * spring, as other rows make way.
 */
internal class AgentThreadListItemAnimator : SimpleItemAnimator() {
    enum class Mode { INSTANT, REVEAL, SPRING }

    var mode = Mode.INSTANT

    private class Move(val holder: RecyclerView.ViewHolder, val deltaY: Float)

    private val pendingRemovals = mutableListOf<RecyclerView.ViewHolder>()
    private val pendingMoves = mutableListOf<Move>()
    private val pendingAdditions = mutableListOf<RecyclerView.ViewHolder>()
    private val running = mutableSetOf<RecyclerView.ViewHolder>()

    init {
        supportsChangeAnimations = false
    }

    override fun animateRemove(holder: RecyclerView.ViewHolder): Boolean {
        if (mode != Mode.SPRING) {
            dispatchRemoveFinished(holder)
            return false
        }
        endAnimation(holder)
        pendingRemovals.add(holder)
        return true
    }

    override fun animateAdd(holder: RecyclerView.ViewHolder): Boolean {
        if (mode == Mode.INSTANT) {
            dispatchAddFinished(holder)
            return false
        }
        endAnimation(holder)
        holder.itemView.alpha = 0f
        pendingAdditions.add(holder)
        return true
    }

    override fun animateMove(
        holder: RecyclerView.ViewHolder,
        fromX: Int,
        fromY: Int,
        toX: Int,
        toY: Int
    ): Boolean {
        val view = holder.itemView
        val startY = fromY + view.translationY
        endAnimation(holder)
        val deltaY = toY - startY
        if (mode != Mode.SPRING || deltaY == 0f) {
            dispatchMoveFinished(holder)
            return false
        }
        view.translationY = -deltaY
        pendingMoves.add(Move(holder, deltaY))
        return true
    }

    override fun animateChange(
        oldHolder: RecyclerView.ViewHolder,
        newHolder: RecyclerView.ViewHolder?,
        fromLeft: Int,
        fromTop: Int,
        toLeft: Int,
        toTop: Int
    ): Boolean {
        // Rows rebind in place; a changed row that also moves moves like any other
        if (oldHolder === newHolder || newHolder == null) {
            return animateMove(oldHolder, fromLeft, fromTop, toLeft, toTop)
        }
        dispatchChangeFinished(oldHolder, true)
        dispatchChangeFinished(newHolder, false)
        return false
    }

    override fun runPendingAnimations() {
        pendingRemovals.forEach { holder ->
            start(holder, holder.itemView.animate().alpha(0f).setDuration(REMOVE_DURATION_MS)) {
                holder.itemView.alpha = 1f
                dispatchRemoveFinished(holder)
            }
        }
        pendingMoves.forEach { move ->
            val animation = move.holder.itemView.animate().translationY(0f)
                .setDuration(MOVE_DURATION_MS)
                .setInterpolator(WInterpolator.smooth)
            start(move.holder, animation) { dispatchMoveFinished(move.holder) }
        }
        pendingAdditions.forEach { holder ->
            val animation = holder.itemView.animate().alpha(1f)
                .setDuration(ADD_DURATION_MS)
                .setInterpolator(AccelerateDecelerateInterpolator())
            start(holder, animation) { dispatchAddFinished(holder) }
        }
        pendingRemovals.clear()
        pendingMoves.clear()
        pendingAdditions.clear()
    }

    private fun start(
        holder: RecyclerView.ViewHolder,
        animation: ViewPropertyAnimator,
        onEnd: () -> Unit
    ) {
        running.add(holder)
        animation.withEndAction {
            if (running.remove(holder)) {
                onEnd()
                if (running.isEmpty()) dispatchAnimationsFinished()
            }
        }.start()
    }

    override fun endAnimation(item: RecyclerView.ViewHolder) {
        val view = item.itemView
        view.animate().cancel()
        if (pendingRemovals.remove(item)) dispatchRemoveFinished(item)
        pendingMoves.firstOrNull { it.holder === item }?.let {
            pendingMoves.remove(it)
            view.translationY = 0f
            dispatchMoveFinished(item)
        }
        if (pendingAdditions.remove(item)) {
            view.alpha = 1f
            dispatchAddFinished(item)
        }
        if (running.remove(item)) {
            finish(view)
            dispatchAnimationFinished(item)
            if (running.isEmpty()) dispatchAnimationsFinished()
        }
    }

    override fun endAnimations() {
        val hasBeenRunning = running.isNotEmpty()
        (pendingRemovals + pendingMoves.map { it.holder } + pendingAdditions + running).toList()
            .forEach(::endAnimation)
        // Ending only pending animations leaves nothing running to report that they all finished
        if (!hasBeenRunning && !isRunning()) dispatchAnimationsFinished()
    }

    override fun isRunning(): Boolean = pendingRemovals.isNotEmpty() || pendingMoves.isNotEmpty() ||
        pendingAdditions.isNotEmpty() || running.isNotEmpty()

    private fun finish(view: View) {
        view.alpha = 1f
        view.translationY = 0f
    }

    private companion object {
        const val MOVE_DURATION_MS = 450L
        const val REMOVE_DURATION_MS = 200L
        const val ADD_DURATION_MS = 300L
    }
}
