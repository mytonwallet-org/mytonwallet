package org.mytonwallet.app_air.uicomponents.widgets.menu

import org.junit.Assert.assertEquals
import org.junit.Test

class ReorderPositionTest {

    // Five 56px rows under 4px of padding, as in the tab menu, with the middle one dragged
    private val rowTops = List(5) { 4 + it * 56 }
    private val rowHeights = List(5) { 56 }

    private fun findPlace(top: Float) =
        findReorderPosition(rowTops, rowHeights, position = 2, top = top)

    @Test
    fun middleRowHeldAtTheTopReachesTheFirstPlace() {
        assertEquals(0, findPlace(rowTops.first().toFloat()))
    }

    @Test
    fun middleRowHeldAtTheBottomReachesTheLastPlace() {
        assertEquals(4, findPlace(rowTops.last().toFloat()))
    }

    @Test
    fun rowPassesANeighborOnlyOnceItsEdgeCrossesTheNeighborsMiddle() {
        val middleAbove = rowTops[1] + 28f
        val middleBelow = rowTops[3] + 28f
        assertEquals(2, findPlace(middleAbove))
        assertEquals(1, findPlace(middleAbove - 1))
        assertEquals(2, findPlace(middleBelow - 56))
        assertEquals(3, findPlace(middleBelow - 55))
    }
}
