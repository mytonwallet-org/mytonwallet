package org.mytonwallet.app_air.uicomponents.helpers

import androidx.recyclerview.widget.DefaultItemAnimator
import androidx.recyclerview.widget.RecyclerView
import org.mytonwallet.app_air.uicomponents.AnimationConstants

class SelectiveItemAnimator : DefaultItemAnimator() {

    var enableAdd: Boolean = false
    var enableRemove: Boolean = false
    var enableMove: Boolean = false
    var enableChange: Boolean = false

    fun setAll(enabled: Boolean) {
        enableAdd = enabled
        enableRemove = enabled
        enableMove = enabled
        enableChange = enabled
    }

    init {
        supportsChangeAnimations = false
        changeDuration = 0
        addDuration = AnimationConstants.SUPER_QUICK_ANIMATION
        removeDuration = AnimationConstants.SUPER_QUICK_ANIMATION
        moveDuration = AnimationConstants.VERY_VERY_QUICK_ANIMATION
    }

    override fun animateAdd(holder: RecyclerView.ViewHolder): Boolean {
        if (!enableAdd) {
            dispatchAddFinished(holder)
            return false
        }
        return super.animateAdd(holder)
    }

    override fun animateRemove(holder: RecyclerView.ViewHolder): Boolean {
        if (!enableRemove) {
            dispatchRemoveFinished(holder)
            return false
        }
        return super.animateRemove(holder)
    }

    override fun animateMove(
        holder: RecyclerView.ViewHolder,
        fromX: Int,
        fromY: Int,
        toX: Int,
        toY: Int
    ): Boolean {
        if (!enableMove) {
            dispatchMoveFinished(holder)
            return false
        }
        return super.animateMove(holder, fromX, fromY, toX, toY)
    }

    override fun animateChange(
        oldHolder: RecyclerView.ViewHolder,
        newHolder: RecyclerView.ViewHolder?,
        fromX: Int,
        fromY: Int,
        toX: Int,
        toY: Int
    ): Boolean {
        if (!enableChange) {
            dispatchChangeFinished(oldHolder, true)
            if (newHolder != null) {
                dispatchChangeFinished(newHolder, false)
            }
            return false
        }
        return super.animateChange(oldHolder, newHolder, fromX, fromY, toX, toY)
    }

    inline fun with(
        recyclerView: RecyclerView,
        add: Boolean = enableAdd,
        remove: Boolean = enableRemove,
        move: Boolean = enableMove,
        change: Boolean = enableChange,
        block: () -> Unit
    ) {
        val prevAdd = enableAdd
        val prevRemove = enableRemove
        val prevMove = enableMove
        val prevChange = enableChange

        enableAdd = add
        enableRemove = remove
        enableMove = move
        enableChange = change

        block()

        recyclerView.post {
            isRunning {
                enableAdd = prevAdd
                enableRemove = prevRemove
                enableMove = prevMove
                enableChange = prevChange
            }
        }
    }
}
