package org.mytonwallet.app_air.uicomponents.commonViews.cardMotion

import android.graphics.Bitmap
import android.graphics.BitmapShader
import android.graphics.BlendMode
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.ColorSpace
import android.graphics.HardwareRenderer
import android.graphics.Mesh
import android.graphics.MeshSpecification
import android.graphics.Paint
import android.graphics.PixelFormat
import android.graphics.RectF
import android.graphics.RenderNode
import android.graphics.Shader
import android.hardware.HardwareBuffer
import android.media.ImageReader
import java.nio.ByteBuffer
import java.nio.ByteOrder
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.ceil
import kotlin.math.cos
import kotlin.math.exp
import kotlin.math.floor
import kotlin.math.hypot
import kotlin.math.max
import kotlin.math.min
import kotlin.math.pow
import kotlin.math.roundToInt
import kotlin.math.sin
import kotlin.math.sqrt

internal class Lcg(seed: ULong) {
    private var state = seed
    fun next(): Double {
        state = state * 6364136223846793005UL + 1442695040888963407UL
        return (state shr 32).toDouble() /
            4294967295.0
    }
}

/** Actual element pixels dissolve into a stable, fixed-width capsule of live samples. */
@androidx.annotation.RequiresApi(34)
internal class HeroParticleField(
    private val visible: (Canvas) -> Unit,
    private val palette: () -> Paint,
    private val softwareSnapshot: Boolean = false
) {
    private class Dot(
        val ax: Double,
        val ay: Double,
        val dx: Double,
        val dy: Double,
        val phase: Double,
        val opacity: Double,
        val radius: Double
    ) {
        var x = 0.0
        var y = 0.0
        var alpha = 0.0
        var diameter = 0.0
        var ox = 0.0
        var oy = 0.0
        var vx = 0.0
        var vy = 0.0
        var layoutX = 0.0
        var layoutY = 0.0
        var density = 1.0
        private fun random(salt: Double) = fract(sin(phase * 127.1 + salt) * 43758.5453)
        val reach =
            .82 + random(1.7) * .36
        val force =
            .4 + random(8.3) * .6
        val deflect = (random(24.9) - .5) * .65
        val response = .8 + random(63.1) * .4
    }
    private data class Fragment(
        val sx: Double,
        val sy: Double,
        val sw: Double,
        val sh: Double,
        val u: Float,
        val v: Float,
        val uw: Float,
        val vh: Float,
        val bendX: Double,
        val bendY: Double,
        val delay: Double,
        val scale: Double,
        val angle: Double,
        val dot: Int
    ) {
        var wrapX = 0.0
        var wrapY = 0.0
        var lastX = 0.0
        var lastY = 0.0
        var lastOpacity = 0.0
    }
    private val dots = ArrayList<Dot>()

    // Dots are batched by alpha level and size bin, so a frame issues a few drawPoints calls.
    private val bucketCounts = IntArray(ALPHA_LEVELS * SIZE_BINS)
    private val bucketStarts = IntArray(ALPHA_LEVELS * SIZE_BINS)
    private var dotBuckets = IntArray(0)
    private var cloudPoints = FloatArray(0)
    private var cloudPathsDirty = true
    private var fragments = emptyList<Fragment>()
    private var snapshot: Bitmap? = null
    private var fragmentPaint: Paint? = null
    private var fragmentMesh: Mesh? = null
    private var fragmentMeshDirty = true
    private var buffer: java.nio.FloatBuffer? = null
    private val meshBounds = RectF()
    var field = RectF()
        private set
    private var source = RectF()
    private var sourceInkRect: RectF? = null
    private var dynamicsPending = false
    private var transitionStep = 0.0
    private var footprintProgress = Double.NaN
    private var footprintLeft = 0.0
    private var footprintScale = 1.0

    private fun cloudX(dot: Dot): Double {
        val ink = sourceInkRect ?: return dot.x
        if (progress >= .75 || field.width() <= 0) return dot.x
        if (footprintProgress != progress) {
            footprintProgress = progress
            val amount = quintic(progress / .75)
            footprintLeft = mix(ink.left.toDouble(), field.left.toDouble(), amount)
            footprintScale =
                mix(ink.width().toDouble(), field.width().toDouble(), amount) / field.width()
        }
        return footprintLeft + (dot.x - field.left) * footprintScale
    }
    private var time = 0.0
    var concealed = false
        private set
    var progress = 0.0
        private set
    private var crossfade = false
    private var pendingReveal = false
    private var pendingFrame = false
    private var revealOriginX = 0.0
    private var revealOriginY = 0.0
    private var localRevealRemaining = 0.0
    val animating get() = snapshot != null || pendingReveal || crossfade
    val cloudActive get() = concealed || animating
    val localRevealPending get() = localRevealRemaining > 0.0
    val localRevealSeconds get() = localRevealRemaining
    fun expireLocalReveal(mode: Int) {
        if (localRevealRemaining <= 0.0) return
        localRevealRemaining = 0.0
        setConcealed(true, field.centerX().toDouble(), field.centerY().toDouble(), mode)
    }
    fun layout(nextField: RectF, nextSource: RectF) {
        if (source != nextSource) fragmentMeshDirty = true
        source.set(nextSource)
        if (nextField.isEmpty || field == nextField) return
        val old = RectF(field)
        field.set(nextField)
        val wanted = (field.width() * field.height() * .28 * .75).toInt().coerceIn(24, 6000)
        val random = Lcg(0xCA4D51DEUL)
        val rebuilt = ArrayList<Dot>(wanted)
        repeat(wanted) { i ->
            var ax: Double
            var ay: Double
            do {
                ax = random.next()
                ay = random.next()
            } while (!contains(
                    field.left + ax * field.width(),
                    field.top + ay * field.height()
                )
            )
            val direction = random.next() * 2 * PI
            val speed = .25 + random.next() * .75
            val dot = Dot(
                ax,
                ay,
                cos(direction) * speed,
                sin(direction) * speed,
                random.next(),
                .35 + random.next() * .65,
                .35 + random.next() * .35
            )
            if (i < dots.size && !old.isEmpty) {
                val previous = dots[i]
                val age = fract(time + dot.phase)
                dot.layoutX =
                    previous.x - (field.left + ax * field.width() + dot.dx * (age - .5) * 48)
                dot.layoutY =
                    previous.y - (field.top + ay * field.height() + dot.dy * (age - .5) * 48)
                dot.ox = previous.ox
                dot.oy = previous.oy
                dot.vx = previous.vx
                dot.vy = previous.vy
            } else if (!old.isEmpty) {
                dot.density = 0.0
            }
            rebuilt.add(dot)
        }
        dots.clear()
        dots.addAll(rebuilt)
        dynamicsPending = !old.isEmpty
        if (animating) settle()
        sample(0.0, null)
    }
    private fun contains(x: Double, y: Double): Boolean {
        if (field.isEmpty) return false
        val r = min(field.width(), field.height()) / 2.0
        val cx = x.coerceIn(field.left + r, field.right - r)
        val cy = y.coerceIn(field.top + r, field.bottom - r)
        return (x - cx).pow(2) + (y - cy).pow(2) <= r * r
    }
    fun setConcealed(hidden: Boolean, originX: Double, originY: Double, mode: Int) {
        localRevealRemaining = 0.0
        if (concealed == hidden) return
        concealed = hidden
        fragmentMeshDirty = true
        cloudPathsDirty = true
        if (mode == 2) {
            settle()
            return
        }
        if (mode == 1) {
            dropSnapshot()
            pendingReveal = false
            crossfade = true
            return
        }
        if (pendingReveal) {
            settle()
            return
        }
        crossfade = false
        if (snapshot != null) {
            if (!hidden) progress = min(.75, progress)
            return
        }
        if (hidden) {
            progress = 0.0
            capture(originX, originY)
        } else {
            progress = .75
            revealOriginX = originX
            revealOriginY = originY
            pendingReveal = true
            pendingFrame = true
        }
    }
    fun revealLocally(seconds: Double, originX: Double, originY: Double, mode: Int) {
        setConcealed(false, originX, originY, mode)
        localRevealRemaining = seconds
    }
    fun settle() {
        progress = if (concealed) 1.0 else 0.0
        pendingReveal = false
        crossfade = false
        dropSnapshot()
    }
    private fun dropSnapshot() {
        sourceInkRect = null
        cloudPathsDirty = true
        snapshot = null
        fragmentPaint = null
        fragmentMesh = null
        fragmentMeshDirty = true
        fragments = emptyList()
        buffer = null
    }
    fun advance(dt: Double, moving: Boolean, finger: Pair<Double, Double>?, mode: Int) {
        fragmentMeshDirty = true
        cloudPathsDirty = true
        transitionStep = dt.coerceIn(0.0, .1)
        if (mode == 2 && animating) settle()
        if (mode == 1 && snapshot != null) settle()
        if (moving) {
            time += min(dt, 1.0 / 15)
            sample(min(dt, 1.0 / 15), finger)
        }
        if (localRevealRemaining > 0) {
            localRevealRemaining = max(0.0, localRevealRemaining - dt)
            if (localRevealRemaining ==
                0.0
            ) {
                setConcealed(true, field.centerX().toDouble(), field.centerY().toDouble(), mode)
            }
        }
        if (pendingReveal) {
            if (pendingFrame) {
                pendingFrame = false
            } else {
                pendingReveal = false
                capture(revealOriginX, revealOriginY)
            }
        }
        if (crossfade) {
            progress = (progress + (if (concealed) dt / .18 else -dt / .18)).coerceIn(0.0, 1.0)
            if (progress == 0.0 || progress == 1.0) settle()
        } else if (snapshot != null) {
            progress = (progress + (if (concealed) dt / .7 else -dt * .75 / .6)).coerceIn(0.0, 1.0)
            if (progress == 0.0 || progress == 1.0) settle()
        }
    }
    private fun sample(dt: Double, finger: Pair<Double, Double>?) {
        cloudPathsDirty = true
        val layoutDecay = exp(-12 * dt)
        val densityStep = 1 - exp(-10 * dt)
        val width = field.width()
        val height = field.height()
        val updateDynamics = dynamicsPending || finger != null
        dynamicsPending = false
        for (dot in dots) {
            val age = fract(time + dot.phase)
            if (updateDynamics) {
                dot.layoutX *= layoutDecay
                dot.layoutY *= layoutDecay
                dot.density += (1 - dot.density) * densityStep
                if (abs(1 - dot.density) < .000001) dot.density = 1.0
                if (abs(dot.layoutX) + abs(dot.layoutY) < .000001) {
                    dot.layoutX = 0.0
                    dot.layoutY = 0.0
                }
            }
            val x = field.left + dot.ax * width + dot.dx * (age - .5) * 48 + dot.layoutX
            val y = field.top + dot.ay * height + dot.dy * (age - .5) * 48 + dot.layoutY
            var tx = 0.0
            var ty = 0.0
            if (finger != null) {
                val dx = x - finger.first
                val dy = y - finger.second
                val distance = hypot(dx, dy)
                if (distance < 64 * dot.reach) {
                    val px = if (distance >
                        .001
                    ) {
                        dx
                    } else {
                        dot.dx
                    }
                    val py = if (distance >
                        .001
                    ) {
                        dy
                    } else {
                        dot.dy
                    }
                    val length = max(.001, hypot(px, py))
                    val travel = 40 * dot.force * (1 - smooth(distance / (64 * dot.reach)))
                    tx = (px - py * dot.deflect) / length * travel
                    ty = (py + px * dot.deflect) / length * travel
                }
            }
            if (updateDynamics && (
                    tx != 0.0 || ty != 0.0 || dot.ox != 0.0 || dot.oy != 0.0 ||
                        dot.vx != 0.0 || dot.vy != 0.0
                    )
            ) {
                val rate = (if (tx == 0.0 && ty == 0.0) 14 else 24) * dot.response
                val decay = exp(-rate * dt)
                val dx = dot.ox - tx
                val dy = dot.oy - ty
                val ix = dot.vx + rate * dx
                val iy = dot.vy + rate * dy
                dot.ox = tx + (dx + ix * dt) * decay
                dot.oy = ty + (dy + iy * dt) * decay
                dot.vx = (dot.vx - rate * ix * dt) * decay
                dot.vy = (dot.vy - rate * iy * dt) * decay
                if (tx == 0.0 && ty == 0.0 && hypot(dot.ox, dot.oy) < .001 &&
                    hypot(dot.vx, dot.vy) < .005
                ) {
                    dot.ox = 0.0
                    dot.oy = 0.0
                    dot.vx = 0.0
                    dot.vy = 0.0
                }
            }
            if (updateDynamics && (
                    dot.layoutX != 0.0 || dot.layoutY != 0.0 || dot.density != 1.0 ||
                        dot.ox != 0.0 || dot.oy != 0.0 || dot.vx != 0.0 || dot.vy != 0.0
                    )
            ) {
                dynamicsPending = true
            }
            dot.x = x + dot.ox
            dot.y = y + dot.oy
            dot.diameter = dot.radius * DIAMETER_SCALE
            val alpha = dot.opacity * sin(PI * age).pow(2) * dot.density
            dot.alpha = if (alpha <= .005) {
                0.0
            } else {
                (
                    min(
                        63,
                        max(0, (alpha * 64).toInt())
                    ) + 1
                    ) / 64.0
            }
        }
    }
    private fun capturePixels(): Bitmap? {
        val width = ceil(source.width() * 2).toInt()
        val height = ceil(source.height() * 2).toInt()
        if (softwareSnapshot) {
            // Plain text can be sampled directly without a synchronous GPU readback.
            return Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888).also { bitmap ->
                val canvas = Canvas(bitmap)
                canvas.scale(2f, 2f)
                canvas.translate(-source.left, -source.top)
                visible(canvas)
            }
        }
        val reader = ImageReader.newInstance(
            width,
            height,
            PixelFormat.RGBA_8888,
            2,
            HardwareBuffer.USAGE_GPU_SAMPLED_IMAGE or HardwareBuffer.USAGE_GPU_COLOR_OUTPUT
        )
        val node = RenderNode("PrivateElementCapture")
        node.setPosition(0, 0, width, height)
        val canvas = node.beginRecording(width, height)
        canvas.drawColor(Color.TRANSPARENT, BlendMode.CLEAR)
        canvas.scale(2f, 2f)
        canvas.translate(-source.left, -source.top)
        visible(canvas)
        node.endRecording()
        val renderer = HardwareRenderer()
        renderer.setSurface(reader.surface)
        renderer.setContentRoot(node)
        renderer.setOpaque(false)
        return try {
            renderer.createRenderRequest().setWaitForPresent(true).syncAndDraw()
            reader.acquireLatestImage()?.use { image ->
                image.hardwareBuffer?.use { hardware ->
                    Bitmap.wrapHardwareBuffer(
                        hardware,
                        ColorSpace.get(ColorSpace.Named.SRGB)
                    )?.let { bitmap ->
                        bitmap.copy(Bitmap.Config.ARGB_8888, false).also { bitmap.recycle() }
                    }
                }
            }
        } finally {
            renderer.destroy()
            reader.close()
            node.discardDisplayList()
        }
    }
    private fun capture(originX: Double, originY: Double) {
        if (source.isEmpty || dots.isEmpty()) {
            settle()
            return
        }
        val b = capturePixels() ?: run {
            settle()
            return
        }
        val pixels = IntArray(b.width * b.height)
        b.getPixels(pixels, 0, b.width, 0, 0, b.width, b.height)
        val step = ceil(
            max(1.6 / sqrt(.75), sqrt(source.width() * source.height() / 9000.0)) * 2
        ).toInt().coerceAtLeast(1)
        val random = Lcg(0xD1571A7EUL)
        val uses = IntArray(dots.size)
        val list = ArrayList<Fragment>()
        val inkBounds = RectF()
        val minCellX = floor(dots.minOf { it.x } / 16).toInt()
        val minCellY = floor(dots.minOf { it.y } / 16).toInt()
        val columns = floor(dots.maxOf { it.x } / 16).toInt() - minCellX + 1
        val rows = floor(dots.maxOf { it.y } / 16).toInt() - minCellY + 1
        // Dot indices grouped by cell, in index order: cell c owns cellDots[cellStart[c] until cellStart[c + 1]].
        val dotCell = IntArray(dots.size) { i ->
            (floor(dots[i].y / 16).toInt() - minCellY) * columns +
                floor(dots[i].x / 16).toInt() - minCellX
        }
        val cellStart = IntArray(columns * rows + 1)
        for (cell in dotCell) cellStart[cell + 1]++
        for (c in 0 until columns * rows) cellStart[c + 1] += cellStart[c]
        val cellFill = cellStart.copyOf()
        val cellDots = IntArray(dots.size)
        for (i in dots.indices) cellDots[cellFill[dotCell[i]]++] = i
        val dotX = DoubleArray(dots.size) { dots[it].x }
        val dotY = DoubleArray(dots.size) { dots[it].y }
        fun distance(i: Int, x: Double, y: Double): Double {
            val dx = dotX[i] - x
            val dy = dotY[i] - y
            return sqrt(dx * dx + dy * dy)
        }
        fun nearest(x: Double, y: Double): Int {
            val gx = floor(x / 16).toInt()
            val gy = floor(y / 16).toInt()
            var best = -1
            var score = Double.MAX_VALUE
            for (dy in -2..2) {
                for (dx in -2..2) {
                    val column = gx + dx - minCellX
                    val row = gy + dy - minCellY
                    if (column !in 0 until columns || row !in 0 until rows) continue
                    val cell = row * columns + column
                    for (k in cellStart[cell] until cellStart[cell + 1]) {
                        val i = cellDots[k]
                        val next = distance(i, x, y) + uses[i] * 12
                        if (next < score) {
                            score = next
                            best = i
                        }
                    }
                }
            }
            if (best <
                0
            ) {
                for (i in dots.indices) {
                    val next = distance(i, x, y) + uses[i] * 12
                    if (next < score) {
                        score = next
                        best = i
                    }
                }
            }
            uses[best]++
            return best
        }
        for (y in 0 until b.height step step) {
            for (x in 0 until b.width step step) {
                val tw = min(step, b.width - x)
                val th = min(step, b.height - y)
                var ink = false
                loop@for (py in y until y + th) {
                    for (px in x until x + tw) {
                        if (Color.alpha(pixels[py * b.width + px]) >
                            8
                        ) {
                            ink = true
                            break@loop
                        }
                    }
                }
                if (!ink) continue
                inkBounds.union(
                    source.left + x / 2f,
                    source.top + y / 2f,
                    source.left + (x + tw) / 2f,
                    source.top + (y + th) / 2f
                )
                val sx = source.left + (x + tw / 2.0) / 2
                val sy = source.top + (y + th / 2.0) / 2
                var rx: Double
                var ry: Double
                do {
                    rx = field.left + random.next() * field.width()
                    ry = field.top + random.next() * field.height()
                } while (!contains(rx, ry))
                var lx = sx.coerceIn(field.left.toDouble(), field.right.toDouble())
                var ly = sy.coerceIn(field.top.toDouble(), field.bottom.toDouble())
                if (!contains(lx, ly)) {
                    val radius = min(field.width(), field.height()) / 2.0
                    val cx = lx.coerceIn(field.left + radius, field.right - radius)
                    val cy = ly.coerceIn(field.top + radius, field.bottom - radius)
                    val dx = lx - cx
                    val dy = ly - cy
                    val k =
                        (radius - .01) / max(radius, hypot(dx, dy))
                    lx = cx + dx * k
                    ly = cy + dy * k
                }
                val destX = mix(lx, rx, .2)
                val destY = mix(ly, ry, .2)
                val dx =
                    sx - originX
                val dy =
                    sy - originY
                val distance = max(1.0, hypot(dx, dy))
                val travel =
                    10 * (1 + (random.next() * 2 - 1))
                val delay =
                    min(
                        1.0,
                        distance / max(
                            1.0,
                            hypot(source.width().toDouble(), source.height().toDouble())
                        )
                    ) *
                        .2 +
                        random.next() * 0
                val idx = nearest(destX, destY)
                random.next() // lift turbulence draw retained for deterministic parity
                val fragment =
                    Fragment(
                        sx,
                        sy,
                        tw / 2.0,
                        th / 2.0,
                        x.toFloat(),
                        y.toFloat(),
                        tw.toFloat(),
                        th.toFloat(),
                        dx / distance * travel, dy / distance * travel, delay,
                        .6 + random.next() * .8,
                        (random.next() * 2 - 1) * 40 * PI / 180, idx
                    )
                fragment.lastX = dots[idx].x
                fragment.lastY = dots[idx].y
                fragment.lastOpacity =
                    dots[idx].alpha
                list.add(fragment)
            }
        }
        if (list.isEmpty()) {
            settle()
            return
        }
        snapshot = b
        sourceInkRect = inkBounds
        footprintProgress = Double.NaN
        cloudPathsDirty = true
        fragments = list
        // The initial footprint is a new coordinate mapping, not a wrap of a live dot.
        for (fragment in fragments) {
            val dot = dots[fragment.dot]
            fragment.lastX = cloudX(dot)
            fragment.lastY = dot.y
            fragment.lastOpacity = dot.alpha
        }
        fragmentMesh = null
        fragmentMeshDirty = true
        fragmentPaint =
            Paint(Paint.ANTI_ALIAS_FLAG).apply {
                shader =
                    BitmapShader(b, Shader.TileMode.CLAMP, Shader.TileMode.CLAMP).apply {
                        setFilterMode(BitmapShader.FILTER_MODE_LINEAR)
                    }
            }
        buffer =
            ByteBuffer.allocateDirect(
                list.size * 6 * 5 * 4
            ).order(ByteOrder.nativeOrder()).asFloatBuffer()
    }
    fun draw(canvas: Canvas) {
        if (!cloudActive) {
            visible(canvas)
            return
        }
        if (pendingReveal) {
            drawCloud(canvas, 1.0)
            return
        }
        if (crossfade) {
            val t = smooth(progress)
            val save = canvas.saveLayerAlpha(null, ((1 - t) * 255).roundToInt())
            visible(canvas)
            canvas.restoreToCount(save)
            drawCloud(canvas, t)
            return
        }
        if (snapshot != null && !canvas.isHardwareAccelerated) {
            // Meshes require a hardware canvas; software snapshots get the settled state.
            if (concealed) drawCloud(canvas, 1.0) else visible(canvas)
            return
        }
        val cloud = if (snapshot != null) {
            quintic((progress - .1) / .65)
        } else if (concealed) {
            1.0
        } else {
            0.0
        }
        if (snapshot == null && !concealed) visible(canvas)
        drawCloud(canvas, cloud)
        if (snapshot != null && progress < .75) drawFragments(canvas, cloud)
    }
    private fun drawCloud(canvas: Canvas, alpha: Double) {
        if (alpha <= 0) return
        if (cloudPathsDirty) {
            if (dotBuckets.size < dots.size) dotBuckets = IntArray(dots.size)
            if (cloudPoints.size < dots.size * 2) cloudPoints = FloatArray(dots.size * 2)
            bucketCounts.fill(0)
            for (i in dots.indices) {
                val d = dots[i]
                if (d.alpha <= 0) {
                    dotBuckets[i] = -1
                    continue
                }
                val level = (d.alpha * ALPHA_LEVELS).roundToInt().coerceIn(1, ALPHA_LEVELS) - 1
                val size = (((d.radius - MIN_RADIUS) / RADIUS_RANGE) * SIZE_BINS).toInt()
                    .coerceIn(0, SIZE_BINS - 1)
                val bucket = level * SIZE_BINS + size
                dotBuckets[i] = bucket
                bucketCounts[bucket]++
            }
            var start = 0
            for (b in bucketCounts.indices) {
                bucketStarts[b] = start
                start += bucketCounts[b]
            }
            bucketCounts.fill(0)
            for (i in dots.indices) {
                val bucket = dotBuckets[i]
                if (bucket < 0) continue
                val at = (bucketStarts[bucket] + bucketCounts[bucket]++) * 2
                cloudPoints[at] = cloudX(dots[i]).toFloat()
                cloudPoints[at + 1] = dots[i].y.toFloat()
            }
            cloudPathsDirty = false
        }
        val paint = palette()
        paint.strokeCap = Paint.Cap.ROUND
        for (b in bucketCounts.indices) {
            val count = bucketCounts[b]
            if (count == 0) continue
            val level = b / SIZE_BINS
            val size = b % SIZE_BINS
            paint.alpha = ((level + 1) / ALPHA_LEVELS.toDouble() * alpha * 255).roundToInt()
            paint.strokeWidth =
                ((MIN_RADIUS + (size + .5) * RADIUS_RANGE / SIZE_BINS) * DIAMETER_SCALE).toFloat()
            canvas.drawPoints(cloudPoints, bucketStarts[b] * 2, count * 2, paint)
        }
        paint.alpha = 255
    }
    private fun drawFragments(canvas: Canvas, cloud: Double) {
        val cachedMesh = fragmentMesh
        if (!fragmentMeshDirty && cachedMesh != null) {
            canvas.drawMesh(cachedMesh, BlendMode.MODULATE, fragmentPaint!!)
            return
        }
        val vertices = buffer ?: return
        vertices.clear()
        val decay = exp(-30 * transitionStep)
        for (f in fragments) {
            val d = dots[f.dot.coerceAtMost(dots.lastIndex)]
            val x = cloudX(d)
            if (hypot(x - f.lastX, d.y - f.lastY) > 8 &&
                min(d.alpha, f.lastOpacity) <= 1.0 / 64
            ) {
                f.wrapX += f.lastX - x
                f.wrapY += f.lastY - d.y
            }
            f.wrapX *= decay
            f.wrapY *= decay
            f.lastX = x
            f.lastY = d.y
            f.lastOpacity = d.alpha
            val p = quintic((progress / .75 - f.delay) / .78)
            val bend = sin(p * PI)
            val cx = mix(f.sx, x + f.wrapX, p) + f.bendX * bend
            val cy = mix(f.sy, d.y + f.wrapY, p) + f.bendY * bend
            val w = mix(mix(f.sw, 2.2 * .7 * f.scale, p), d.diameter, cloud)
            val h = mix(mix(f.sh, 2.2 * .7 * f.scale, p), d.diameter, cloud)
            val angle =
                bend * f.angle
            val co = cos(angle)
            val si = sin(angle)
            val opacity = (
                (1 - cloud) *
                    mix(1.0, d.alpha, cloud)
                ).toFloat()
            for (q in QUAD) {
                val x = (q[0] - .5) * w
                val y = (q[1] - .5) * h
                vertices.put((cx + x * co - y * si).toFloat())
                vertices.put((cy + x * si + y * co).toFloat())
                vertices.put(f.u + q[0] * f.uw)
                vertices.put(f.v + q[1] * f.vh)
                vertices.put(opacity)
            }
        }
        vertices.flip()
        meshBounds.set(source.left - 90, source.top - 90, source.right + 90, source.bottom + 90)
        val mesh = Mesh(SPEC, Mesh.TRIANGLES, vertices, fragments.size * 6, meshBounds)
        fragmentMesh = mesh
        fragmentMeshDirty = false
        canvas.drawMesh(mesh, BlendMode.MODULATE, fragmentPaint!!)
    }
    companion object {
        private const val ALPHA_LEVELS = 64
        private const val SIZE_BINS = 4
        private const val MIN_RADIUS = .35
        private const val RADIUS_RANGE = .35
        private const val DIAMETER_SCALE = 2.2 * 2

        fun prewarm() {
            SPEC
        }

        private val QUAD =
            arrayOf(
                floatArrayOf(0f, 0f),
                floatArrayOf(1f, 0f),
                floatArrayOf(0f, 1f),
                floatArrayOf(1f, 0f),
                floatArrayOf(1f, 1f),
                floatArrayOf(0f, 1f)
            )
        private val SPEC by lazy {
            MeshSpecification.make(
                arrayOf(
                    MeshSpecification.Attribute(MeshSpecification.TYPE_FLOAT2, 0, "position"),
                    MeshSpecification.Attribute(MeshSpecification.TYPE_FLOAT2, 8, "tex"),
                    MeshSpecification.Attribute(MeshSpecification.TYPE_FLOAT, 16, "opacity")
                ),
                20,
                arrayOf(
                    MeshSpecification.Varying(MeshSpecification.TYPE_FLOAT2, "tex"),
                    MeshSpecification.Varying(MeshSpecification.TYPE_FLOAT, "opacity")
                ),
                "Varyings main(const Attributes a) { Varyings v; v.position=a.position;v.tex=a.tex;v.opacity=a.opacity;return v; }",
                "float2 main(const Varyings v, out float4 color) { color=float4(v.opacity);return v.tex; }",
                ColorSpace.get(ColorSpace.Named.SRGB)
            )
        }
    }
}
