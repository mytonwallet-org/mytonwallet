package org.mytonwallet.app_air.uicomponents.widgets.chart.extended

class SegmentTree(private val values: LongArray) {
    private val size: Int
    private val maxTree: LongArray
    private val minTree: LongArray

    init {
        var n = 1
        while (n < values.size) {
            n = n shl 1
        }
        size = n
        maxTree = LongArray(size * 2) { Long.MIN_VALUE }
        minTree = LongArray(size * 2) { Long.MAX_VALUE }
        for (index in values.indices) {
            maxTree[size + index] = values[index]
            minTree[size + index] = values[index]
        }
        for (index in size - 1 downTo 1) {
            maxTree[index] = maxOf(maxTree[index * 2], maxTree[index * 2 + 1])
            minTree[index] = minOf(minTree[index * 2], minTree[index * 2 + 1])
        }
    }

    fun rMaxQ(left: Int, right: Int): Long {
        var l = left.coerceAtLeast(0) + size
        var r = right.coerceAtMost(values.lastIndex) + size
        var result = Long.MIN_VALUE
        while (l <= r) {
            if ((l and 1) == 1) result = maxOf(result, maxTree[l++])
            if ((r and 1) == 0) result = maxOf(result, maxTree[r--])
            l = l shr 1
            r = r shr 1
        }
        return if (result == Long.MIN_VALUE) 0L else result
    }

    fun rMinQ(left: Int, right: Int): Long {
        var l = left.coerceAtLeast(0) + size
        var r = right.coerceAtMost(values.lastIndex) + size
        var result = Long.MAX_VALUE
        while (l <= r) {
            if ((l and 1) == 1) result = minOf(result, minTree[l++])
            if ((r and 1) == 0) result = minOf(result, minTree[r--])
            l = l shr 1
            r = r shr 1
        }
        return if (result == Long.MAX_VALUE) 0L else result
    }
}
