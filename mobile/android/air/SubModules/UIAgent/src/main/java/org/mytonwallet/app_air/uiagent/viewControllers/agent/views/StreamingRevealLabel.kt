package org.mytonwallet.app_air.uiagent.viewControllers.agent.views

import android.animation.ValueAnimator
import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.ColorFilter
import android.graphics.Paint
import android.graphics.Path
import android.graphics.PorterDuff
import android.graphics.PorterDuffColorFilter
import android.graphics.Rect
import android.graphics.RectF
import android.graphics.RenderEffect
import android.graphics.RenderNode
import android.graphics.Shader
import android.os.Build
import android.os.SystemClock
import android.text.Layout
import android.view.Choreographer
import android.view.animation.AccelerateDecelerateInterpolator
import android.view.animation.PathInterpolator
import androidx.annotation.RequiresApi
import androidx.core.graphics.createBitmap
import kotlin.math.ceil
import kotlin.math.floor
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.walletbasecontext.DEBUG_MODE
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage

/**
 * An answer's text, whose new characters come in as iOS's streamed text does, where they rest: each comes in at 0.15
 * opacity and is sharp within 0.15 s, a glow of its own shape in the Agent's blue fading as it sharpens, and it
 * arrives in the Agent's blue, which turns violet on its way into the text's own colours by 0.65 s, so the fresh end
 * of a line runs from blue to violet as the thinking glow does
 */
@SuppressLint("ViewConstructor")
class StreamingRevealLabel(context: Context) : WLabel(context) {

    companion object {
        private const val SIZE_TRANSITION_DURATION = 0.15
        private const val MAX_SNIPPETS_PER_FRAME = 128
        private const val MAX_BITMAP_DIMENSION = 4096
        private const val MAX_CHANNEL = 255f

        // The glow's blur in dp, as a UIKit shadow radius: iOS's shrinks from 3 pt as the glow fades, and the glow
        // shows most at about 1.75 pt. UIKit's shadow blur is twice its gaussian's sigma, and a blur effect of
        // radius r blurs with a sigma of 0.57735 r + 0.5.
        private const val GLOW_BLUR = 1.75f
        private const val BLUR_SIGMA_SCALE = 0.57735f
        private const val BLUR_SIGMA_OFFSET = 0.5f

        // A gaussian reaches this many sigmas out
        private const val BLUR_REACH = 3f

        private val revealProgressByKey = mutableMapOf<String, Int>()

        // Start times of in-flight snippet animations per message, so a label adopting the
        // reveal after a cell handoff can respawn them instead of popping the characters in.
        private val snippetTimesByKey = mutableMapOf<String, MutableList<Pair<Int, Double>>>()
        private const val SNIPPET_LIFETIME = AgentStreamedCharacterLook.DURATION_S
    }

    private class Snippet(
        val charIndex: Int,
        val startTime: Double,
        val src: Rect,
        val dst: RectF,
        val bitmap: Bitmap
    )

    private var revealKey: String? = null
    private var revealController: TextRevealController? = null
    private var revealCharCount: Int? = null
    private val snippets = mutableListOf<Snippet>()

    private var textBitmap: Bitmap? = null
    private var textBitmapLayout: Layout? = null

    // The layout the snippets took their glyphs and places from
    private var snippetLayout: Layout? = null

    private var hasSizeOverride = false
    private var sizeFromWidth = 0f
    private var sizeFromHeight = 0f
    private var sizeToWidth = 0f
    private var sizeToHeight = 0f
    private var sizeAnimStart = 0.0

    private var pendingSnippetAdoption = false
    private var isRenderingEnabled = true
    private var frameScheduled = false
    private val interpolator = AccelerateDecelerateInterpolator()

    // Core Animation's ease-out, which iOS sharpens a character with
    private val sharpenInterpolator = PathInterpolator(0f, 0f, 0.58f, 1f)
    private val maskPath = Path()
    private val snippetPaint = Paint(Paint.FILTER_BITMAP_FLAG)
    private val tintPaint = Paint(Paint.FILTER_BITMAP_FLAG)
    private val glowPaint = Paint(Paint.FILTER_BITMAP_FLAG)
    private val glowRegion = RectF()
    private var streamedGlow: StreamedGlow? = null
    private var blueTint = 0
    private var violetTint = 0
    private var blueTintFilter: ColorFilter? = null
    private var violetTintFilter: ColorFilter? = null

    private val isRevealActive: Boolean
        get() = revealController != null || snippets.isNotEmpty() || hasSizeOverride

    val isRevealAnimating: Boolean
        get() = isRevealActive

    // Debug builds show streamed text at once while system animations are off, for fast E2E runs
    private val canAnimateReveal: Boolean
        get() = WGlobalStorage.getAreAnimationsActive() &&
            (!DEBUG_MODE || areSystemAnimatorsEnabled)

    private val areSystemAnimatorsEnabled: Boolean
        get() = Build.VERSION.SDK_INT < Build.VERSION_CODES.O || ValueAnimator.areAnimatorsEnabled()

    var onRevealFinished: (() -> Unit)? = null
    var onSizeTransitionFrame: (() -> Unit)? = null

    fun setRenderingActive(active: Boolean) {
        isRenderingEnabled = active
        if (active) {
            if (isRevealActive) scheduleFrame()
        } else if (frameScheduled) {
            frameScheduled = false
            Choreographer.getInstance().removeFrameCallback(frameCallback)
        }
    }

    fun setTextWithReveal(newText: CharSequence?, isStreaming: Boolean, key: String) {
        if (key != revealKey) {
            revealKey = key
            cancelReveal(notifySizeChange = false)
        }
        val previousText = if (revealController != null) text else null
        text = newText
        if (!canAnimateReveal) {
            cancelReveal()
            return
        }
        val length = text?.length ?: 0
        val now = nowSeconds()
        val controller = revealController
        if (controller != null && previousText != null && newText != null) {
            val prefixLength = commonPrefixLength(previousText, newText)
            if (prefixLength < (revealCharCount ?: 0)) {
                controller.rewind(prefixLength)
                revealCharCount = prefixLength
                revealProgressByKey[key] = prefixLength
            }
        }
        when {
            isStreaming && length > 0 -> {
                val active = controller ?: TextRevealController(
                    initialRevealedCount = revealCharCount ?: revealProgressByKey[key] ?: 0,
                    initialLength = length
                ).also {
                    revealController = it
                    if (revealCharCount == null) {
                        revealCharCount = revealProgressByKey[key] ?: 0
                    }
                }
                active.observeUpdate(length, now)
                scheduleFrame()
            }

            controller != null && !controller.isFinalizing -> {
                controller.finalize(length)
                scheduleFrame()
            }

            // The final bind can land on a different recycled cell than the one that ran the
            // streaming reveal (a deeplink update reloads the list). Resume the reveal from
            // the progress stored for this message instead of snapping to the full text.
            controller == null && (revealProgressByKey[key] ?: length) < length -> {
                val stored = revealProgressByKey[key] ?: 0
                revealCharCount = stored
                revealController = TextRevealController(
                    initialRevealedCount = stored,
                    initialLength = length
                ).also { it.finalize(length) }
                pendingSnippetAdoption = true
                scheduleFrame()
            }
        }
    }

    private fun commonPrefixLength(a: CharSequence, b: CharSequence): Int {
        val limit = min(a.length, b.length)
        var i = 0
        while (i < limit && a[i] == b[i]) {
            i++
        }
        return i
    }

    internal fun finishReveal(key: String) {
        val isSameMessage = revealKey == key
        revealKey = key
        revealProgressByKey.remove(key)
        snippetTimesByKey.remove(key)
        cancelReveal(notifySizeChange = isSameMessage)
        if (frameScheduled) {
            frameScheduled = false
            Choreographer.getInstance().removeFrameCallback(frameCallback)
        }
    }

    private fun cancelReveal(notifySizeChange: Boolean = true) {
        pendingSnippetAdoption = false
        revealController = null
        revealCharCount = null
        snippets.clear()
        textBitmap = null
        textBitmapLayout = null
        if (hasSizeOverride) {
            hasSizeOverride = false
            if (notifySizeChange) onSizeTransitionFrame?.invoke()
            requestLayout()
        }
    }

    private fun nowSeconds(): Double = SystemClock.uptimeMillis() / 1000.0

    private fun scheduleFrame() {
        if (frameScheduled || !isRenderingEnabled || !isAttachedToWindow) return
        frameScheduled = true
        Choreographer.getInstance().postFrameCallback(frameCallback)
    }

    private val frameCallback = Choreographer.FrameCallback {
        frameScheduled = false
        if (isRenderingEnabled) onFrame(nowSeconds())
    }

    private fun onFrame(now: Double) {
        if (revealController != null && layout == null) {
            // Text was just replaced; the layout rebuilds on the next measure pass.
            scheduleFrame()
            return
        }
        val wasActive = isRevealActive
        var needsInvalidate = false

        revealController?.let { controller ->
            val (count, isComplete) = controller.tick(now)
            val previousCount = revealCharCount ?: 0
            if (isComplete) {
                spawnSnippets(previousCount, controller.latestLength, now)
                revealController = null
                revealCharCount = null
                revealKey?.let { revealProgressByKey.remove(it) }
                contentSizeForCharCount(text?.length ?: 0)?.let { full ->
                    setSizeTarget(full.first, full.second, now)
                    requestLayout()
                }
                needsInvalidate = true
            } else if (count != previousCount) {
                revealKey?.let { revealProgressByKey[it] = count }
                spawnSnippets(previousCount, count, now)
                val previousSize = contentSizeForCharCount(previousCount)
                val newSize = contentSizeForCharCount(count)
                if (newSize != null && newSize != previousSize) {
                    setSizeTarget(newSize.first, newSize.second, now)
                    requestLayout()
                }
                revealCharCount = count
                needsInvalidate = true
            }
        }

        if (snippets.isNotEmpty()) {
            snippets.removeAll { now - it.startTime >= SNIPPET_LIFETIME }
            needsInvalidate = true
        }
        revealKey?.let { key ->
            snippetTimesByKey[key]?.let { times ->
                times.removeAll { now - it.second >= SNIPPET_LIFETIME }
                if (times.isEmpty()) snippetTimesByKey.remove(key)
            }
        }

        val sizeAnimating = hasSizeOverride && now < sizeAnimStart + SIZE_TRANSITION_DURATION
        if (sizeAnimating) {
            onSizeTransitionFrame?.invoke()
            requestLayout()
        }

        if (needsInvalidate || sizeAnimating) {
            invalidate()
        }

        if (revealController != null || snippets.isNotEmpty() || sizeAnimating) {
            scheduleFrame()
        } else if (hasSizeOverride) {
            hasSizeOverride = false
            textBitmap = null
            textBitmapLayout = null
            onSizeTransitionFrame?.invoke()
            requestLayout()
        }
        if (wasActive && !isRevealActive) {
            onRevealFinished?.invoke()
        }
    }

    private fun setSizeTarget(targetWidth: Float, targetHeight: Float, now: Double) {
        if (!hasSizeOverride) {
            sizeFromWidth = targetWidth
            sizeFromHeight = targetHeight
            sizeToWidth = targetWidth
            sizeToHeight = targetHeight
            sizeAnimStart = now - SIZE_TRANSITION_DURATION
            hasSizeOverride = true
            return
        }
        if (targetWidth == sizeToWidth && targetHeight == sizeToHeight) return
        val (currentWidth, currentHeight) = evalContentSize(now)
        sizeFromWidth = currentWidth
        sizeFromHeight = currentHeight
        sizeToWidth = targetWidth
        sizeToHeight = targetHeight
        sizeAnimStart = now
    }

    private fun evalContentSize(now: Double): Pair<Float, Float> {
        val rawProgress =
            ((now - sizeAnimStart) / SIZE_TRANSITION_DURATION).coerceIn(0.0, 1.0).toFloat()
        val progress = interpolator.getInterpolation(rawProgress)
        return Pair(
            sizeFromWidth + (sizeToWidth - sizeFromWidth) * progress,
            sizeFromHeight + (sizeToHeight - sizeFromHeight) * progress
        )
    }

    // Mirrors InteractiveTextNode.layoutForCharacterCount: height is the bottom of the last
    // revealed line (at least the first line), width follows the cut offset while the reveal
    // is still on the first line and grows to the full layout width once it wraps.
    private fun contentSizeForCharCount(count: Int): Pair<Float, Float>? {
        val layout = layout ?: return null
        if (layout.lineCount == 0) return null
        val textLength = layout.text.length
        val clamped = count.coerceIn(0, textLength)
        val firstLineHeight = layout.getLineBottom(0).toFloat()
        if (clamped <= 0) {
            return Pair(0f, firstLineHeight)
        }
        val line = layout.getLineForOffset(clamped - 1)
        val height = layout.getLineBottom(line).toFloat()
        val width = if (line > 0 || !canRevealWidth(layout)) {
            layout.width.toFloat()
        } else {
            ceil(layout.getPrimaryHorizontal(clamped))
        }
        return Pair(width, height)
    }

    private fun canRevealWidth(layout: Layout): Boolean {
        // Shrinking the measured width only clips the correct (trailing) side when both the
        // view gravity and the paragraph run left-to-right.
        return !LocaleController.isRTL &&
            layout.getParagraphDirection(0) != Layout.DIR_RIGHT_TO_LEFT
    }

    override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
        super.onMeasure(widthMeasureSpec, heightMeasureSpec)
        if (!hasSizeOverride && revealController != null) {
            contentSizeForCharCount(revealCharCount ?: 0)?.let { (width, height) ->
                setSizeTarget(width, height, nowSeconds())
            }
        }
        if (!hasSizeOverride) return
        val (contentWidth, contentHeight) = evalContentSize(nowSeconds())
        var targetWidth = ceil(contentWidth).toInt() + compoundPaddingLeft + compoundPaddingRight
        var targetHeight = ceil(contentHeight).toInt() + compoundPaddingTop + compoundPaddingBottom
        if (MeasureSpec.getMode(widthMeasureSpec) != MeasureSpec.UNSPECIFIED) {
            targetWidth = min(targetWidth, MeasureSpec.getSize(widthMeasureSpec))
        }
        if (MeasureSpec.getMode(heightMeasureSpec) != MeasureSpec.UNSPECIFIED) {
            targetHeight = min(targetHeight, MeasureSpec.getSize(heightMeasureSpec))
        }
        setMeasuredDimension(targetWidth, targetHeight)
    }

    // The text shows up to the first character still sharpening; a sharp one settling in its colours shows in it
    private fun maskCharLimit(now: Double): Int? {
        var minSharpening: Int? = null
        for (snippet in snippets) {
            if (now - snippet.startTime >= AgentStreamedCharacterLook.SHARPEN_S) continue
            minSharpening = min(minSharpening ?: snippet.charIndex, snippet.charIndex)
        }
        val revealed = revealCharCount
        return when {
            revealed != null && minSharpening != null -> min(revealed, minSharpening)
            revealed != null -> revealed
            minSharpening != null -> minSharpening
            else -> null
        }
    }

    override fun onDraw(canvas: Canvas) {
        if (pendingSnippetAdoption) {
            pendingSnippetAdoption = false
            adoptInFlightSnippets(nowSeconds())
        }
        val layout = layout
        if (layout != null && layout !== snippetLayout) relayoutSnippets(layout)
        if (layout == null) {
            super.onDraw(canvas)
            return
        }
        val now = nowSeconds()
        val limit = maskCharLimit(now)
        if (limit == null) {
            super.onDraw(canvas)
        } else {
            maskPath.rewind()
            buildMaskPath(layout, limit.coerceAtMost(layout.text.length), maskPath)
            val saveCount = canvas.save()
            canvas.clipPath(maskPath)
            super.onDraw(canvas)
            canvas.restoreToCount(saveCount)
        }
        drawSnippets(canvas, now, limit ?: Int.MAX_VALUE)
    }

    private fun buildMaskPath(layout: Layout, limit: Int, path: Path) {
        val paddingLeft = totalPaddingLeft.toFloat()
        val paddingTop = totalPaddingTop.toFloat()
        val fullRight = paddingLeft + layout.width
        var mergedTop = -1f
        var mergedBottom = -1f
        for (i in 0 until layout.lineCount) {
            if (limit <= layout.getLineStart(i)) break
            val top = paddingTop + layout.getLineTop(i)
            val bottom = paddingTop + layout.getLineBottom(i)
            if (limit >= layout.getLineEnd(i)) {
                if (mergedTop < 0f) mergedTop = top
                mergedBottom = bottom
            } else {
                if (mergedTop >= 0f) {
                    path.addRect(0f, mergedTop, fullRight, mergedBottom, Path.Direction.CW)
                    mergedTop = -1f
                }
                val cutX = paddingLeft + layout.getPrimaryHorizontal(limit)
                if (layout.getParagraphDirection(i) == Layout.DIR_RIGHT_TO_LEFT) {
                    path.addRect(
                        cutX,
                        top,
                        paddingLeft + layout.getLineRight(i),
                        bottom,
                        Path.Direction.CW
                    )
                } else {
                    path.addRect(
                        paddingLeft + layout.getLineLeft(i),
                        top,
                        cutX,
                        bottom,
                        Path.Direction.CW
                    )
                }
                break
            }
        }
        if (mergedTop >= 0f) {
            path.addRect(0f, mergedTop, fullRight, mergedBottom, Path.Direction.CW)
        }
    }

    /**
     * Moves the snippets still coming in onto [layout], where the text re-wrapped as it grew, so each glyph settles
     * where the text now has it
     */
    private fun relayoutSnippets(layout: Layout) {
        snippetLayout = layout
        if (snippets.isEmpty()) return
        val inFlight = snippets.map { it.charIndex to it.startTime }
        snippets.clear()
        val bitmap = ensureTextBitmap(layout) ?: return
        val textLength = layout.text.length
        for ((charIndex, startTime) in inFlight) {
            if (charIndex < textLength) spawnSnippetForChar(layout, bitmap, charIndex, startTime)
        }
    }

    private fun spawnSnippets(from: Int, to: Int, now: Double) {
        val layout = layout ?: return
        if (layout !== snippetLayout) relayoutSnippets(layout)
        val textLength = layout.text.length
        val end = min(to, textLength)
        if (from >= end) return
        val bitmap = ensureTextBitmap(layout) ?: return
        var spawned = 0
        val times = revealKey?.let { snippetTimesByKey.getOrPut(it) { mutableListOf() } }
        for (charIndex in max(from, 0) until end) {
            if (spawned >= MAX_SNIPPETS_PER_FRAME) break
            if (spawnSnippetForChar(layout, bitmap, charIndex, now)) {
                times?.add(Pair(charIndex, now))
                spawned++
            }
        }
    }

    // Re-creates the snippets that were still animating on the label this reveal was handed
    // over from, keeping their original start times so their coming in continues seamlessly.
    private fun adoptInFlightSnippets(now: Double) {
        val entries = revealKey?.let { snippetTimesByKey[it] } ?: return
        val layout = layout ?: return
        if (layout !== snippetLayout) relayoutSnippets(layout)
        val bitmap = ensureTextBitmap(layout) ?: return
        val textLength = layout.text.length
        for ((charIndex, startTime) in entries) {
            if (now - startTime >= SNIPPET_LIFETIME) continue
            if (charIndex >= textLength) continue
            spawnSnippetForChar(layout, bitmap, charIndex, startTime)
        }
    }

    private fun spawnSnippetForChar(
        layout: Layout,
        bitmap: Bitmap,
        charIndex: Int,
        startTime: Double
    ): Boolean {
        if (layout.text[charIndex].isWhitespace()) return false
        val paddingLeft = totalPaddingLeft.toFloat()
        val paddingTop = totalPaddingTop.toFloat()
        val line = layout.getLineForOffset(charIndex)
        val startX = layout.getPrimaryHorizontal(charIndex)
        val endX = if (charIndex + 1 < layout.getLineEnd(line)) {
            layout.getPrimaryHorizontal(charIndex + 1)
        } else if (layout.getParagraphDirection(line) == Layout.DIR_RIGHT_TO_LEFT) {
            layout.getLineLeft(line)
        } else {
            layout.getLineRight(line)
        }
        val left = min(startX, endX)
        val right = max(startX, endX)
        if (right - left < 0.5f) return false
        val src = Rect(
            floor(left).toInt().coerceIn(0, bitmap.width),
            layout.getLineTop(line).coerceIn(0, bitmap.height),
            ceil(right).toInt().coerceIn(0, bitmap.width),
            layout.getLineBottom(line).coerceIn(0, bitmap.height)
        )
        if (src.isEmpty) return false
        val dst = RectF(
            paddingLeft + src.left,
            paddingTop + src.top,
            paddingLeft + src.right,
            paddingTop + src.bottom
        )
        snippets.add(Snippet(charIndex, startTime, src, dst, bitmap))
        return true
    }

    private fun hasSupportedBitmapDimensions(width: Int, height: Int): Boolean {
        val hasPositiveDimensions = width > 0 && height > 0
        val fitsBitmapLimit = width <= MAX_BITMAP_DIMENSION && height <= MAX_BITMAP_DIMENSION
        return hasPositiveDimensions && fitsBitmapLimit
    }

    private fun ensureTextBitmap(layout: Layout): Bitmap? {
        textBitmap?.let {
            if (textBitmapLayout === layout) return it
        }
        val width = layout.width
        val height = layout.height
        if (!hasSupportedBitmapDimensions(width, height)) {
            return null
        }
        val bitmap = createBitmap(width, height)
        layout.draw(Canvas(bitmap))
        textBitmap = bitmap
        textBitmapLayout = layout
        return bitmap
    }

    /**
     * Draws the characters still coming in where they rest: a sharpening one at its opacity over its glow, and each
     * one under copies of it in the Agent's blue and violet, the violet over the blue, as iOS lays them. The text
     * under the mask, which ends at [limit], shows a sharp character itself.
     */
    private fun drawSnippets(canvas: Canvas, now: Double, limit: Int) {
        if (snippets.isEmpty()) return
        updateTintFilters()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S && canvas.isHardwareAccelerated) {
            drawGlow(canvas, now)
        }
        for (snippet in snippets) {
            val age = now - snippet.startTime
            val sharpness = computeSharpness(age)
            if (sharpness < 1f || snippet.charIndex >= limit) {
                snippetPaint.alpha = toAlpha(computeOpacity(sharpness))
                canvas.drawBitmap(snippet.bitmap, snippet.src, snippet.dst, snippetPaint)
            }
            drawTint(
                canvas,
                snippet,
                blueTintFilter,
                AgentStreamedCharacterLook.computeBlueOpacity(age)
            )
            drawTint(
                canvas,
                snippet,
                violetTintFilter,
                AgentStreamedCharacterLook.computeVioletOpacity(age)
            )
        }
    }

    // The glow is the blur: the sharpening characters' copies in the Agent's blue, blurred together in one node sized
    // to just them, each as strong as iOS's shadow of it, which fades as the character sharpens
    @RequiresApi(Build.VERSION_CODES.S)
    private fun drawGlow(canvas: Canvas, now: Double) {
        glowRegion.setEmpty()
        for (snippet in snippets) {
            if (now - snippet.startTime < AgentStreamedCharacterLook.SHARPEN_S) {
                glowRegion.union(snippet.dst)
            }
        }
        val sigma = GLOW_BLUR.dp / 2
        val radius = (sigma - BLUR_SIGMA_OFFSET) / BLUR_SIGMA_SCALE
        if (glowRegion.isEmpty || radius <= 0f) return
        glowRegion.inset(-sigma * BLUR_REACH, -sigma * BLUR_REACH)
        val glow = streamedGlow ?: StreamedGlow().also { streamedGlow = it }
        val recording = glow.beginRecording(glowRegion, radius)
        glowPaint.colorFilter = blueTintFilter
        for (snippet in snippets) {
            val age = now - snippet.startTime
            if (age >= AgentStreamedCharacterLook.SHARPEN_S) continue
            val sharpness = computeSharpness(age)
            val strength = AgentStreamedCharacterLook.INITIAL_GLOW_OPACITY * (1f - sharpness)
            glowPaint.alpha = toAlpha(computeOpacity(sharpness) * strength)
            recording.drawBitmap(snippet.bitmap, snippet.src, snippet.dst, glowPaint)
        }
        glow.endRecording(canvas)
    }

    private fun drawTint(canvas: Canvas, snippet: Snippet, filter: ColorFilter?, opacity: Float) {
        val alpha = toAlpha(opacity)
        if (alpha == 0) return
        tintPaint.colorFilter = filter
        tintPaint.alpha = alpha
        canvas.drawBitmap(snippet.bitmap, snippet.src, snippet.dst, tintPaint)
    }

    private fun updateTintFilters() {
        val blue = AgentGlowPalette.textBlue
        if (blueTintFilter == null || blue != blueTint) {
            blueTintFilter = PorterDuffColorFilter(blue, PorterDuff.Mode.SRC_IN)
            blueTint = blue
        }
        val violet = AgentGlowPalette.textViolet
        if (violetTintFilter == null || violet != violetTint) {
            violetTintFilter = PorterDuffColorFilter(violet, PorterDuff.Mode.SRC_IN)
            violetTint = violet
        }
    }

    // How sharp a character is `age` seconds after it arrived, eased as iOS sharpens it
    private fun computeSharpness(age: Double): Float =
        sharpenInterpolator.getInterpolation(AgentStreamedCharacterLook.computeSharpness(age))

    private fun computeOpacity(sharpness: Float): Float {
        val initial = AgentStreamedCharacterLook.INITIAL_OPACITY
        return initial + (1f - initial) * sharpness
    }

    private fun toAlpha(opacity: Float): Int = (opacity * MAX_CHANNEL).roundToInt().coerceIn(0, 255)

    override fun onAttachedToWindow() {
        super.onAttachedToWindow()
        if (isRevealActive) {
            scheduleFrame()
        }
    }

    override fun onDetachedFromWindow() {
        super.onDetachedFromWindow()
        if (frameScheduled) {
            frameScheduled = false
            Choreographer.getInstance().removeFrameCallback(frameCallback)
        }
    }

    /** The blurred glow of the characters still sharpening, in a node sized to just them */
    @RequiresApi(Build.VERSION_CODES.S)
    private class StreamedGlow {
        private val node = RenderNode("AgentStreamedGlow")
        private val bounds = Rect()
        private var radius = 0f

        /** A canvas in the label's coordinates covering [region], whose drawing comes out blurred by [radius] */
        fun beginRecording(region: RectF, radius: Float): Canvas {
            region.roundOut(bounds)
            node.setPosition(bounds)
            if (this.radius != radius) {
                node.setRenderEffect(
                    RenderEffect.createBlurEffect(radius, radius, Shader.TileMode.DECAL)
                )
                this.radius = radius
            }
            val recording = node.beginRecording(bounds.width(), bounds.height())
            recording.translate(-bounds.left.toFloat(), -bounds.top.toFloat())
            return recording
        }

        /** Draws what was recorded into [canvas] */
        fun endRecording(canvas: Canvas) {
            node.endRecording()
            canvas.drawRenderNode(node)
        }
    }
}

/**
 * How a streamed character comes in, as iOS's `AgentStreamedCharacterAppearance` has it: from [INITIAL_OPACITY] it is
 * sharp within [SHARPEN_S], in the Agent's colours that then turn into the text's own within [COLOR_S]. It arrives in
 * the Agent's blue, which turns violet by the middle of its way to the text's colours.
 */
internal object AgentStreamedCharacterLook {
    const val SHARPEN_S = 0.15
    const val COLOR_S = 0.5

    /** How long a character takes to settle in its own colours */
    const val DURATION_S = SHARPEN_S + COLOR_S
    const val INITIAL_OPACITY = 0.15f
    const val INITIAL_GLOW_OPACITY = 0.9f

    /** How far the character is from its arrival to sharp, `age` seconds after it arrived */
    fun computeSharpness(age: Double): Float = (age / SHARPEN_S).coerceIn(0.0, 1.0).toFloat()

    /** How much of the Agent's colours the character still shows over its own */
    fun computeAccent(age: Double): Float {
        val opacity = INITIAL_OPACITY + (1f - INITIAL_OPACITY) * computeSharpness(age)
        val toText = ((age - SHARPEN_S) / COLOR_S).coerceIn(0.0, 1.0).toFloat()
        return opacity * (1f - toText)
    }

    /** How far the Agent's colours over the character have turned from blue to violet: violet by the middle */
    fun computeViolet(age: Double): Float {
        val progress = ((age - SHARPEN_S) / (COLOR_S / 2)).coerceIn(0.0, 1.0).toFloat()
        return progress * progress * (3f - 2f * progress)
    }

    /** The opacity of the character's copy in the violet, over the blue one */
    fun computeVioletOpacity(age: Double): Float = computeAccent(age) * computeViolet(age)

    /** The opacity of the character's copy in the blue, which with the violet one over it shows [computeAccent] */
    fun computeBlueOpacity(age: Double): Float {
        val violet = computeVioletOpacity(age)
        return if (violet < 1f) (computeAccent(age) - violet) / (1f - violet) else 0f
    }
}
