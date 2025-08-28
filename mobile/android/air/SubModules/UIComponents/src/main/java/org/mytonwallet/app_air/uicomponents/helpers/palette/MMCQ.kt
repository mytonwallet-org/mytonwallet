package org.mytonwallet.app_air.uicomponents.helpers.palette

/**
 * Kotlin port of the MMCQ (modified median cut quantization)
 * algorithm from the Leptonica library (http://www.leptonica.com/).
 * Returns a color map you can use to map original pixels to the reduced
 * palette.
 *
 * Original by Nick Rabinowitz, ported to Kotlin
 *
 * @example
 *
 * // array of pixels as [R,G,B] arrays
 * val myPixels = listOf(
 *     intArrayOf(190, 197, 190),
 *     intArrayOf(202, 204, 200),
 *     intArrayOf(207, 214, 210),
 *     intArrayOf(211, 214, 211),
 *     intArrayOf(205, 207, 207)
 *     // etc
 * )
 * val maxColors = 4
 *
 * val cmap = MMCQ.quantize(myPixels, maxColors)
 * val newPalette = cmap.palette()
 * val newPixels = myPixels.map { cmap.map(it) }
 */

object MMCQ {
    // private constants
    private const val SIGBITS = 5
    private const val RSHIFT = 8 - SIGBITS
    private const val MAX_ITERATIONS = 1000
    private const val FRACT_BY_POPULATIONS = 0.75

    // Utility functions similar to pv in the original
    private object Utils {
        fun map(array: List<IntArray>, f: ((IntArray, Int) -> IntArray)? = null): List<IntArray> {
            return if (f != null) {
                array.mapIndexed { index, item -> f(item, index) }
            } else {
                array.toList()
            }
        }

        fun naturalOrder(a: Int, b: Int): Int {
            return when {
                a < b -> -1
                a > b -> 1
                else -> 0
            }
        }

        fun sum(array: List<IntArray>, f: ((IntArray, Int) -> Int)? = null): Int {
            return if (f != null) {
                array.mapIndexed { index, item -> f(item, index) }.sum()
            } else {
                array.sumOf { it.sum() }
            }
        }

        fun max(array: List<Int>): Int {
            return array.maxOrNull() ?: 0
        }

        fun max(array: List<IntArray>, f: (IntArray) -> Int): Int {
            return array.maxOfOrNull { f(it) } ?: 0
        }
    }

    // get reduced-space color index for a pixel
    private fun getColorIndex(r: Int, g: Int, b: Int): Int {
        return (r shl (2 * SIGBITS)) + (g shl SIGBITS) + b
    }

    // Simple priority queue
    class PQueue<T>(private val comparator: (T, T) -> Int) {
        private val contents = mutableListOf<T>()
        private var sorted = false

        private fun sort() {
            contents.sortWith { a, b -> comparator(a, b) }
            sorted = true
        }

        fun push(o: T) {
            contents.add(o)
            sorted = false
        }

        fun peek(index: Int = contents.size - 1): T {
            if (!sorted) sort()
            return contents[index]
        }

        fun pop(): T {
            if (!sorted) sort()
            return contents.removeAt(contents.size - 1)
        }

        fun size(): Int {
            return contents.size
        }

        fun map(f: (T) -> Any): List<Any> {
            return contents.map(f)
        }

        fun debug(): List<T> {
            if (!sorted) sort()
            return contents
        }
    }

    // 3d color space box
    class VBox(
        var r1: Int, var r2: Int,
        var g1: Int, var g2: Int,
        var b1: Int, var b2: Int,
        val histo: IntArray
    ) {
        private var _volume: Int? = null
        private var _count: Int? = null
        private var _count_set = false
        private var _avg: IntArray? = null

        fun volume(force: Boolean = false): Int {
            if (_volume == null || force) {
                _volume = ((r2 - r1 + 1) * (g2 - g1 + 1) * (b2 - b1 + 1))
            }
            return _volume!!
        }

        fun count(force: Boolean = false): Int {
            if (!_count_set || force) {
                var npix = 0
                for (i in r1..r2) {
                    for (j in g1..g2) {
                        for (k in b1..b2) {
                            val index = getColorIndex(i, j, k)
                            npix += (histo[index] ?: 0)
                        }
                    }
                }
                _count = npix
                _count_set = true
            }
            return _count!!
        }

        fun copy(): VBox {
            return VBox(r1, r2, g1, g2, b1, b2, histo)
        }

        fun avg(force: Boolean = false): IntArray {
            if (_avg == null || force) {
                var ntot = 0
                val mult = 1 shl (8 - SIGBITS)
                var rsum = 0
                var gsum = 0
                var bsum = 0

                for (i in r1..r2) {
                    for (j in g1..g2) {
                        for (k in b1..b2) {
                            val histoIndex = getColorIndex(i, j, k)
                            val hval = histo[histoIndex] ?: 0
                            ntot += hval
                            rsum += (hval * (i + 0.5) * mult).toInt()
                            gsum += (hval * (j + 0.5) * mult).toInt()
                            bsum += (hval * (k + 0.5) * mult).toInt()
                        }
                    }
                }

                _avg = if (ntot > 0) {
                    intArrayOf((rsum / ntot), (gsum / ntot), (bsum / ntot))
                } else {
                    intArrayOf(
                        (mult * (r1 + r2 + 1) / 2),
                        (mult * (g1 + g2 + 1) / 2),
                        (mult * (b1 + b2 + 1) / 2)
                    )
                }
            }
            return _avg!!
        }

        fun contains(pixel: IntArray): Boolean {
            val rval = pixel[0] shr RSHIFT
            val gval = pixel[1] shr RSHIFT
            val bval = pixel[2] shr RSHIFT
            return (rval >= r1 && rval <= r2 &&
                gval >= g1 && gval <= g2 &&
                bval >= b1 && bval <= b2)
        }
    }

    // Color map
    class CMap {
        val vboxes = PQueue<VBoxAndColor> { a, b ->
            Utils.naturalOrder(
                a.vbox.count() * a.vbox.volume(),
                b.vbox.count() * b.vbox.volume()
            )
        }

        data class VBoxAndColor(val vbox: VBox, val color: IntArray)

        fun push(vbox: VBox) {
            vboxes.push(VBoxAndColor(vbox, vbox.avg()))
        }

        fun palette(): List<IntArray> {
            return vboxes.map { it.color } as List<IntArray>
        }

        fun size(): Int {
            return vboxes.size()
        }

        fun map(color: IntArray): IntArray {
            for (i in 0 until vboxes.size()) {
                if (vboxes.peek(i).vbox.contains(color)) {
                    return vboxes.peek(i).color
                }
            }
            return nearest(color)
        }

        fun nearest(color: IntArray): IntArray {
            var d1: Double? = null
            var pColor: IntArray? = null

            for (i in 0 until vboxes.size()) {
                val vboxColor = vboxes.peek(i).color
                val d2 = Math.sqrt(
                    Math.pow((color[0] - vboxColor[0]).toDouble(), 2.0) +
                        Math.pow((color[1] - vboxColor[1]).toDouble(), 2.0) +
                        Math.pow((color[2] - vboxColor[2]).toDouble(), 2.0)
                )
                if (d1 == null || d2 < d1) {
                    d1 = d2
                    pColor = vboxColor
                }
            }
            return pColor!!
        }

        fun forcebw() {
            // Sort by luminance
            val tempVboxes = mutableListOf<VBoxAndColor>()
            for (i in 0 until vboxes.size()) {
                tempVboxes.add(vboxes.peek(i))
            }

            tempVboxes.sortWith { a, b ->
                Utils.naturalOrder(
                    a.color.sum(),
                    b.color.sum()
                )
            }

            // Force darkest color to black if everything < 5
            val lowest = tempVboxes.firstOrNull()?.color
            if (lowest != null && lowest[0] < 5 && lowest[1] < 5 && lowest[2] < 5) {
                tempVboxes[0] = tempVboxes[0].copy(color = intArrayOf(0, 0, 0))
            }

            // Force lightest color to white if everything > 251
            val idx = tempVboxes.size - 1
            val highest = tempVboxes.lastOrNull()?.color
            if (highest != null && highest[0] > 251 && highest[1] > 251 && highest[2] > 251) {
                tempVboxes[idx] = tempVboxes[idx].copy(color = intArrayOf(255, 255, 255))
            }

            // Rebuild the vboxes
            vboxes.map { it }.forEach { _ -> vboxes.pop() }
            tempVboxes.forEach { vboxes.push(it) }
        }
    }

    // histo (1-d array, giving the number of pixels in
    // each quantized region of color space), or null on error
    private fun getHisto(pixels: List<IntArray>): IntArray {
        val histoSize = 1 shl (3 * SIGBITS)
        val histo = IntArray(histoSize)

        for (pixel in pixels) {
            val rval = pixel[0] shr RSHIFT
            val gval = pixel[1] shr RSHIFT
            val bval = pixel[2] shr RSHIFT
            val index = getColorIndex(rval, gval, bval)
            histo[index] = histo[index] + 1
        }

        return histo
    }

    private fun vboxFromPixels(pixels: List<IntArray>, histo: IntArray): VBox {
        var rmin = Int.MAX_VALUE
        var rmax = 0
        var gmin = Int.MAX_VALUE
        var gmax = 0
        var bmin = Int.MAX_VALUE
        var bmax = 0

        // find min/max
        pixels.forEach { pixel ->
            val rval = pixel[0] shr RSHIFT
            val gval = pixel[1] shr RSHIFT
            val bval = pixel[2] shr RSHIFT

            if (rval < rmin) rmin = rval
            else if (rval > rmax) rmax = rval
            if (gval < gmin) gmin = gval
            else if (gval > gmax) gmax = gval
            if (bval < bmin) bmin = bval
            else if (bval > bmax) bmax = bval
        }
        return VBox(rmin, rmax, gmin, gmax, bmin, bmax, histo)
    }

    private fun medianCutApply(histo: IntArray, vbox: VBox): List<VBox>? {
        if (vbox.count() == 0) return null

        val rw = vbox.r2 - vbox.r1 + 1
        val gw = vbox.g2 - vbox.g1 + 1
        val bw = vbox.b2 - vbox.b1 + 1
        val maxw = maxOf(rw, gw, bw)

        // Only one pixel, no split
        if (vbox.count() == 1) {
            return listOf(vbox.copy())
        }

        var total = 0
        val size = when (maxw) {
            rw -> vbox.r2 + 1
            gw -> vbox.g2 + 1
            else -> vbox.b2 + 1
        }
        val partialSum = IntArray(size) { 0 }
        val lookaheadSum = IntArray(size) { 0 }

        if (maxw == rw) {
            for (i in vbox.r1..vbox.r2) {
                var sum = 0
                for (j in vbox.g1..vbox.g2) {
                    for (k in vbox.b1..vbox.b2) {
                        val index = getColorIndex(i, j, k)
                        if (index < histo.size) {
                            sum += histo[index]
                        }
                    }
                }
                total += sum
                if (i < partialSum.size) {
                    partialSum[i] = total
                }
            }
        } else if (maxw == gw) {
            for (i in vbox.g1..vbox.g2) {
                var sum = 0
                for (j in vbox.r1..vbox.r2) {
                    for (k in vbox.b1..vbox.b2) {
                        val index = getColorIndex(j, i, k)
                        if (index < histo.size) {
                            sum += histo[index]
                        }
                    }
                }
                total += sum
                if (i < partialSum.size) {
                    partialSum[i] = total
                }
            }
        } else { // maxw == bw
            for (i in vbox.b1..vbox.b2) {
                var sum = 0
                for (j in vbox.r1..vbox.r2) {
                    for (k in vbox.g1..vbox.g2) {
                        val index = getColorIndex(j, k, i)
                        if (index < histo.size) {
                            sum += histo[index]
                        }
                    }
                }
                total += sum
                if (i < partialSum.size) {
                    partialSum[i] = total
                }
            }
        }

        for (i in partialSum.indices) {
            lookaheadSum[i] = total - partialSum[i]
        }

        fun doCut(color: Char): List<VBox>? {
            val dim1 = when (color) {
                'r' -> vbox.r1
                'g' -> vbox.g1
                'b' -> vbox.b1
                else -> throw IllegalArgumentException("Invalid color")
            }
            val dim2 = when (color) {
                'r' -> vbox.r2
                'g' -> vbox.g2
                'b' -> vbox.b2
                else -> throw IllegalArgumentException("Invalid color")
            }

            for (i in dim1..dim2) {
                val index = i - dim1
                if (index in partialSum.indices && partialSum[index] > total / 2) {
                    val vbox1 = vbox.copy()
                    val vbox2 = vbox.copy()

                    val left = i - dim1
                    val right = dim2 - i

                    var d2 = if (left <= right) {
                        minOf(dim2 - 1, i + right / 2)
                    } else {
                        maxOf(dim1, i - 1 - left / 2)
                    }

                    // Avoid 0-count boxes, with bounds checking
                    while (d2 - dim1 in partialSum.indices && partialSum.getOrElse(d2 - dim1) { 0 } == 0) {
                        d2++
                    }

                    var count2 = lookaheadSum.getOrElse(d2 - dim1) { 0 }
                    while (count2 == 0 && d2 - dim1 - 1 in partialSum.indices && partialSum.getOrElse(
                            d2 - dim1 - 1
                        ) { 0 } != 0
                    ) {
                        count2 = lookaheadSum.getOrElse(--d2 - dim1) { 0 }
                    }

                    // Set dimensions
                    when (color) {
                        'r' -> {
                            vbox1.r2 = d2
                            vbox2.r1 = vbox1.r2 + 1
                        }

                        'g' -> {
                            vbox1.g2 = d2
                            vbox2.g1 = vbox1.g2 + 1
                        }

                        'b' -> {
                            vbox1.b2 = d2
                            vbox2.b1 = vbox1.b2 + 1
                        }
                    }

                    return listOf(vbox1, vbox2)
                }
            }

            return null
        }

        // Determine the cut planes
        return when (maxw) {
            rw -> doCut('r')
            gw -> doCut('g')
            else -> doCut('b')
        }
    }

    fun quantize(pixels: List<IntArray>, maxcolors: Int): CMap? {
        // short-circuit
        if (pixels.isEmpty() || maxcolors < 2 || maxcolors > 256) {
            return null
        }

        // Get histogram and histogram size
        val histo = getHisto(pixels)
        val histosize = 1 shl (3 * SIGBITS)

        // Check that we aren't below maxcolors already
        /*val nColors = histosize
        if (nColors <= maxcolors) {
            // XXX: generate the new colors from the histo and return
            // This part is incomplete in the original code as well
        }*/

        // Get the beginning vbox from the colors
        val vbox = vboxFromPixels(pixels, histo)
        val pq = PQueue<VBox> { a, b ->
            Utils.naturalOrder(a.count(), b.count())
        }
        pq.push(vbox)

        // Inner function to do the iteration
        fun iter(lh: PQueue<VBox>, target: Double) {
            var ncolors = 1
            var niters = 0

            while (niters < MAX_ITERATIONS) {
                val vbox = lh.pop()
                if (vbox.count() == 0) { /* just put it back */
                    lh.push(vbox)
                    niters++
                    continue
                }

                // Do the cut
                val vboxes = medianCutApply(histo, vbox)
                val vbox1 = vboxes?.getOrNull(0)
                val vbox2 = vboxes?.getOrNull(1)

                if (vbox1 == null) {
                    return
                }

                lh.push(vbox1)
                if (vbox2 != null) {
                    lh.push(vbox2)
                    ncolors++
                }

                if (ncolors >= target) return
                if (niters++ > MAX_ITERATIONS) {
                    return
                }
            }
        }

        // First set of colors, sorted by population
        iter(pq, FRACT_BY_POPULATIONS * maxcolors)

        // Re-sort by the product of pixel occupancy times the size in color space.
        val pq2 = PQueue<VBox> { a, b ->
            Utils.naturalOrder(a.count() * a.volume(), b.count() * b.volume())
        }
        while (pq.size() > 0) {
            val pqItem = pq.pop()
            pq2.push(pqItem)
        }

        // Next set - generate the median cuts using the (npix * vol) sorting.
        iter(pq2, (maxcolors - pq2.size()).toDouble())

        // Calculate the actual colors
        val cmap = CMap()
        while (pq2.size() > 0) {
            cmap.push(pq2.pop())
        }

        return cmap
    }
}
