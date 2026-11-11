package org.mytonwallet.app_air.uicomponents.helpers

import android.content.Context
import android.view.View
import androidx.core.view.updateLayoutParams
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.walletcontext.models.MToolbarItem

/**
 * Places the toolbar buttons' glass backgrounds from the buttons' drawn bounds; with a shared background, neighbours
 * blend into one as their gap closes. The host adds [views] back to front, anchored to the parent's left edge.
 */
class HomeToolbarBackgrounds(context: Context, private val getButton: (MToolbarItem) -> View) {
    private companion object {
        const val MERGE_DISTANCE = 8
        const val MERGED = 0.999f
    }

    private val size = MToolbarItem.entries.size

    private val forming = Array(size) { Slot(View(context)) }
    private val own = Array(size) { Slot(View(context)) }
    private val merged = Array(size) { Slot(View(context)) }
    private val slots = listOf(forming, own, merged).flatMap { it.asList() }

    val views: List<View> = listOf(forming, own, merged).flatMap { slots ->
        MToolbarItem.entries.filter { it != MToolbarItem.SEARCH }.map { slots[it.ordinal].view }
    }

    fun getOwnBackground(item: MToolbarItem): View = own[item.ordinal].view

    private val sequence = IntArray(size)
    private val pairMerge = FloatArray(size)
    private val left = FloatArray(size)
    private val right = FloatArray(size)
    private val slotLeft = FloatArray(size)
    private val slotRight = FloatArray(size)

    /** Returns whether a background was shown or hidden */
    fun sync(
        order: List<MToolbarItem>,
        isShared: Boolean,
        liftedItem: MToolbarItem? = null,
        liftProgress: Float = 0f
    ): Boolean {
        var count = 0
        var isToolbarShown = false
        for (item in order) {
            if (item == MToolbarItem.SEARCH) {
                sequence[count++] = SEARCH_BREAK
            } else if (getButton(item).let { it.visibility != View.GONE && it.alpha > 0f }) {
                isToolbarShown = isToolbarShown || getButton(item).visibility == View.VISIBLE
                measure(item)
                sequence[count++] = item.ordinal
            }
        }
        for (index in 0 until count - 1) {
            pairMerge[index] = getMerge(
                sequence[index],
                sequence[index + 1],
                isShared,
                liftedItem,
                liftProgress
            )
        }
        for (slot in slots) slot.reset()
        placeOwn(count)
        placeGroups(count, isMerged = true)
        placeGroups(count, isMerged = false)
        var isToggled = false
        for (slot in slots) isToggled = slot.apply(isToolbarShown) || isToggled
        return isToggled
    }

    private fun measure(item: MToolbarItem) {
        val button = getButton(item)
        val width = button.width * button.scaleX
        left[item.ordinal] = button.x + (button.width - width) / 2
        right[item.ordinal] = left[item.ordinal] + width
        slotLeft[item.ordinal] = button.x
        slotRight[item.ordinal] = button.x + button.width
    }

    private fun getMerge(
        first: Int,
        second: Int,
        isShared: Boolean,
        liftedItem: MToolbarItem?,
        liftProgress: Float
    ): Float {
        if (!isShared || first == SEARCH_BREAK || second == SEARCH_BREAK) return 0f
        // Unscaled, so a fading button keeps its neighbours merged; either order for RTL
        // A button off the row, such as one settling into it, stays apart
        val gap = max(
            max(slotLeft[second] - slotRight[first], slotLeft[first] - slotRight[second]),
            abs(
                getButton(MToolbarItem.entries[first]).translationY -
                    getButton(MToolbarItem.entries[second]).translationY
            )
        ).coerceAtLeast(0f)
        val closeness = (1 - gap / MERGE_DISTANCE.dp).coerceIn(0f, 1f)
        val isLifted = liftedItem?.ordinal == first || liftedItem?.ordinal == second
        return closeness * (1 - if (isLifted) liftProgress else 0f)
    }

    private fun placeOwn(count: Int) {
        for (index in 0 until count) {
            val ordinal = sequence[index]
            if (ordinal == SEARCH_BREAK) continue
            val merge = max(
                if (index > 0) pairMerge[index - 1] else 0f,
                if (index < count - 1) pairMerge[index] else 0f
            )
            if (merge >= MERGED) continue
            val button = getButton(MToolbarItem.entries[ordinal])
            own[ordinal].place(
                left[ordinal],
                right[ordinal],
                button.scaleY,
                button.translationY,
                alpha = button.alpha * (1 - merge * merge),
                rotation = button.rotation,
                isVisible = button.visibility == View.VISIBLE
            )
        }
    }

    private fun placeGroups(count: Int, isMerged: Boolean) {
        var start = 0
        while (start < count - 1) {
            if (!isGrouped(pairMerge[start], isMerged)) {
                start++
                continue
            }
            var end = start
            var minMerge = 1f
            while (end < count - 1 && isGrouped(pairMerge[end], isMerged)) {
                minMerge = min(minMerge, pairMerge[end])
                end++
            }
            val isForming = minMerge < MERGED
            if (isMerged || isForming) placeGroup(start, end, if (isMerged) 1f else minMerge)
            start = end
        }
    }

    private fun isGrouped(merge: Float, isMerged: Boolean): Boolean =
        if (isMerged) merge >= MERGED else merge > 0f

    private fun placeGroup(start: Int, end: Int, strength: Float) {
        var groupLeft = Float.MAX_VALUE
        var groupRight = -Float.MAX_VALUE
        var alpha = 0f
        var scale = 0f
        var translationY = 0f
        var isVisible = false
        for (index in start..end) {
            val ordinal = sequence[index]
            val button = getButton(MToolbarItem.entries[ordinal])
            translationY += button.translationY / (end - start + 1)
            groupLeft = min(groupLeft, left[ordinal])
            groupRight = max(groupRight, right[ordinal])
            alpha = max(alpha, button.alpha)
            scale = max(scale, button.scaleY)
            isVisible = isVisible || button.visibility == View.VISIBLE
        }
        val groupSlots = if (strength >= MERGED) merged else forming
        groupSlots[sequence[start]].place(
            groupLeft,
            groupRight,
            scale,
            translationY,
            alpha * strength,
            rotation = 0f,
            isVisible = isVisible
        )
    }

    private class Slot(val view: View) {
        private var isShown = false
        private var left = 0f
        private var right = 0f
        private var scale = 1f
        private var alpha = 0f
        private var rotation = 0f
        private var translationY = 0f
        private var isVisible = false

        fun reset() {
            isShown = false
        }

        fun place(
            left: Float,
            right: Float,
            scale: Float,
            translationY: Float,
            alpha: Float,
            rotation: Float,
            isVisible: Boolean
        ) {
            isShown = true
            this.left = left
            this.right = right
            this.scale = scale
            this.translationY = translationY
            this.alpha = alpha
            this.rotation = rotation
            this.isVisible = isVisible
        }

        // Unused slots stay shown at no alpha: a glass shown again draws blank for a frame
        fun apply(isToolbarShown: Boolean): Boolean {
            if (!isShown || alpha <= 0f) {
                if (view.alpha != 0f) view.alpha = 0f
                val visibility = if (isToolbarShown) View.VISIBLE else View.GONE
                if (view.visibility == visibility) return false
                view.visibility = visibility
                return true
            }
            val width = if (scale > 0f) ((right - left) / scale).roundToInt() else 0
            if (view.layoutParams.width != width) {
                view.updateLayoutParams { this.width = width }
                // Resize now; the next layout would lag a frame
                view.layout(view.left, view.top, view.left + width, view.bottom)
            }
            view.scaleX = scale
            view.scaleY = scale
            view.translationX = left - width * (1 - scale) / 2 - view.left
            view.translationY = translationY
            view.rotation = rotation
            view.alpha = alpha
            val visibility = if (isVisible) View.VISIBLE else View.INVISIBLE
            if (view.visibility == visibility) return false
            view.visibility = visibility
            return true
        }
    }
}

private const val SEARCH_BREAK = -1
