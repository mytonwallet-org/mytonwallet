package org.mytonwallet.app_air.uicomponents.helpers

import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.walletbasecontext.theme.ViewConstants
import org.mytonwallet.app_air.walletcontext.models.MToolbarConfiguration
import org.mytonwallet.app_air.walletcontext.models.MToolbarItem

object HomeToolbarLayout {
    const val HEIGHT = 48
    private const val BUTTON_GAP = 8
    private const val FIELD_GAP = 12

    const val MIN_FIELD_WIDTH = 96

    val margin: Int
        get() = (ViewConstants.HORIZONTAL_PADDINGS + 6).dp

    fun canHold(
        configuration: MToolbarConfiguration,
        item: MToolbarItem,
        screenWidth: Int
    ): Boolean {
        if (configuration.isShown(item)) return true
        val fieldWidth = layout(
            configuration.order,
            screenWidth - 2 * margin,
            configuration.isSharedBackground,
            { if (it == item || configuration.isShown(it)) 1f else 0f },
            FloatArray(MToolbarItem.entries.size)
        )
        return fieldWidth >= MIN_FIELD_WIDTH.dp
    }

    /** Writes leading offsets into [starts] by ordinal and returns the field's width */
    fun layout(
        order: List<MToolbarItem>,
        width: Int,
        isSharedBackground: Boolean,
        visibility: (MToolbarItem) -> Float,
        starts: FloatArray
    ): Float {
        val button = HEIGHT.dp.toFloat()
        var buttonsSpan = 0f
        var fieldGap = 0f
        for (index in order.indices) {
            val item = order[index]
            val gap = getGapAfter(order, index, isSharedBackground, visibility)
            if (item == MToolbarItem.SEARCH) {
                fieldGap = gap
            } else {
                buttonsSpan += (button + gap) * visibility(item)
            }
        }
        val fieldWidth = (width - buttonsSpan - fieldGap).coerceAtLeast(button)
        var start = 0f
        for (index in order.indices) {
            val item = order[index]
            starts[item.ordinal] = start
            start += if (item == MToolbarItem.SEARCH) {
                fieldWidth + fieldGap
            } else {
                (button + getGapAfter(order, index, isSharedBackground, visibility)) *
                    visibility(item)
            }
        }
        return fieldWidth
    }

    /** The gap to the next item, blended through the buttons after it by how far each is shown */
    private fun getGapAfter(
        order: List<MToolbarItem>,
        index: Int,
        isSharedBackground: Boolean,
        visibility: (MToolbarItem) -> Float
    ): Float {
        var gap = 0f
        var weight = 1f
        for (next in index + 1 until order.size) {
            val item = order[next]
            val isBesideField = order[index] == MToolbarItem.SEARCH || item == MToolbarItem.SEARCH
            val itemGap = when {
                isBesideField -> FIELD_GAP.dp.toFloat()
                isSharedBackground -> 0f
                else -> BUTTON_GAP.dp.toFloat()
            }
            val itemVisibility = if (item ==
                MToolbarItem.SEARCH
            ) {
                1f
            } else {
                visibility(item).coerceIn(0f, 1f)
            }
            gap += weight * itemVisibility * itemGap
            weight *= 1 - itemVisibility
            if (weight == 0f) break
        }
        return gap
    }
}
