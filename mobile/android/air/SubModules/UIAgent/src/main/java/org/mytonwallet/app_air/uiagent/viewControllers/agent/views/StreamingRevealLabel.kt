package org.mytonwallet.app_air.uiagent.viewControllers.agent.views

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Bitmap
import android.graphics.BlurMaskFilter
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.Path
import android.graphics.Rect
import android.graphics.RectF
import android.os.Build
import android.os.SystemClock
import android.text.Layout
import android.view.Choreographer
import android.view.animation.AccelerateDecelerateInterpolator
import androidx.core.graphics.createBitmap
import kotlin.math.ceil
import kotlin.math.floor
import kotlin.math.max
import kotlin.math.min
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage

@SuppressLint("ViewConstructor")
class StreamingRevealLabel(context: Context) : WLabel(context) {

    companion object {
        private const val SNIPPET_DURATION = 0.2
        private const val BLUR_DURATION = 0.22
        private const val SIZE_TRANSITION_DURATION = 0.15
        private const val MAX_SNIPPETS_PER_FRAME = 128
        private const val MAX_BITMAP_DIMENSION = 4096

        private val revealProgressByKey = mutableMapOf<String, Int>()

        // Start times of in-flight snippet animations per message, so a label adopting the
        // reveal after a cell handoff can respawn them instead of popping the characters in.
        private val snippetTimesByKey = mutableMapOf<String, MutableList<Pair<Int, Double>>>()
        private val SNIPPET_LIFETIME = max(SNIPPET_DURATION, BLUR_DURATION)
    }

    private class Snippet(
        val charIndex: Int,
        val startTime: Double,
        val src: Rect,
        val dst: RectF,
        val bitmap: Bitmap
    )

    private val snippetRise = 6f.dp
    private val snippetBlurRadius = 2f.dp

    private var revealKey: String? = null
    private var revealController: TextRevealController? = null
    private var revealCharCount: Int? = null
    private val snippets = mutableListOf<Snippet>()

    private var textBitmap: Bitmap? = null
    private var textBitmapText: CharSequence? = null

    private var hasSizeOverride = false
    private var sizeFromWidth = 0f
    private var sizeFromHeight = 0f
    private var sizeToWidth = 0f
    private var sizeToHeight = 0f
    private var sizeAnimStart = 0.0

    private var pendingSnippetAdoption = false
    private var frameScheduled = false
    private val interpolator = AccelerateDecelerateInterpolator()
    private val maskPath = Path()
    private val snippetPaint = Paint(Paint.FILTER_BITMAP_FLAG)

    private val isRevealActive: Boolean
        get() = revealController != null || snippets.isNotEmpty() || hasSizeOverride

    val isRevealAnimating: Boolean
        get() = isRevealActive

    var onRevealFinished: (() -> Unit)? = null
    var onSizeTransitionFrame: (() -> Unit)? = null

    fun setTextWithReveal(
        newText: CharSequence?,
        isStreaming: Boolean,
        key: String,
        transitionFromContentSize: Pair<Float, Float>? = null
    ) {
        if (key != revealKey) {
            revealKey = key
            cancelReveal()
        }
        val previousText = if (revealController != null) text else null
        text = newText
        if (!WGlobalStorage.getAreAnimationsActive()) {
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
                    // Start the size morph from the previous bubble content (e.g. the typing
                    // indicator) instead of snapping to the empty reveal size.
                    if (transitionFromContentSize != null && !hasSizeOverride &&
                        (revealCharCount ?: 0) == 0
                    ) {
                        setSizeTarget(
                            transitionFromContentSize.first,
                            transitionFromContentSize.second,
                            now
                        )
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

    private fun cancelReveal() {
        pendingSnippetAdoption = false
        revealController = null
        revealCharCount = null
        snippets.clear()
        textBitmap = null
        textBitmapText = null
        if (hasSizeOverride) {
            hasSizeOverride = false
            onSizeTransitionFrame?.invoke()
            requestLayout()
        }
    }

    private fun nowSeconds(): Double = SystemClock.uptimeMillis() / 1000.0

    private fun scheduleFrame() {
        if (frameScheduled || !isAttachedToWindow) return
        frameScheduled = true
        Choreographer.getInstance().postFrameCallback(frameCallback)
    }

    private val frameCallback = Choreographer.FrameCallback {
        frameScheduled = false
        onFrame(nowSeconds())
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
            textBitmapText = null
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

    private fun maskCharLimit(): Int? {
        val minAnimating = snippets.minOfOrNull { it.charIndex }
        val revealed = revealCharCount
        return when {
            revealed != null && minAnimating != null -> min(revealed, minAnimating)
            revealed != null -> revealed
            minAnimating != null -> minAnimating
            else -> null
        }
    }

    override fun onDraw(canvas: Canvas) {
        if (pendingSnippetAdoption) {
            pendingSnippetAdoption = false
            adoptInFlightSnippets(nowSeconds())
        }
        val layout = layout
        val limit = maskCharLimit()
        if (limit == null || layout == null) {
            super.onDraw(canvas)
            return
        }
        maskPath.rewind()
        buildMaskPath(layout, limit.coerceAtMost(layout.text.length), maskPath)
        val saveCount = canvas.save()
        canvas.clipPath(maskPath)
        super.onDraw(canvas)
        canvas.restoreToCount(saveCount)
        drawSnippets(canvas, nowSeconds())
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

    private fun spawnSnippets(from: Int, to: Int, now: Double) {
        val layout = layout ?: return
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
    // over from, keeping their original start times so the fly-in continues seamlessly.
    private fun adoptInFlightSnippets(now: Double) {
        val entries = revealKey?.let { snippetTimesByKey[it] } ?: return
        val layout = layout ?: return
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
            if (textBitmapText === layout.text) return it
        }
        val width = layout.width
        val height = layout.height
        if (!hasSupportedBitmapDimensions(width, height)) {
            return null
        }
        val bitmap = createBitmap(width, height)
        layout.draw(Canvas(bitmap))
        textBitmap = bitmap
        textBitmapText = layout.text
        return bitmap
    }

    private fun drawSnippets(canvas: Canvas, now: Double) {
        if (snippets.isEmpty()) return
        val supportsBlur =
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.P || !canvas.isHardwareAccelerated
        for (snippet in snippets) {
            val elapsed = now - snippet.startTime
            val progress = interpolator.getInterpolation(
                (elapsed / SNIPPET_DURATION).coerceIn(0.0, 1.0).toFloat()
            )
            val blurProgress = interpolator.getInterpolation(
                (elapsed / BLUR_DURATION).coerceIn(0.0, 1.0).toFloat()
            )
            val scale = 0.5f + 0.5f * progress
            val translationY = snippetRise * (1f - progress)
            val blurRadius = snippetBlurRadius * (1f - blurProgress)
            val saveCount = canvas.save()
            canvas.translate(0f, translationY)
            canvas.scale(scale, scale, snippet.dst.centerX(), snippet.dst.centerY())
            snippetPaint.alpha = (progress * 255f).toInt().coerceIn(0, 255)
            snippetPaint.maskFilter = if (supportsBlur && blurRadius > 0.1f) {
                BlurMaskFilter(blurRadius, BlurMaskFilter.Blur.NORMAL)
            } else {
                null
            }
            canvas.drawBitmap(snippet.bitmap, snippet.src, snippet.dst, snippetPaint)
            canvas.restoreToCount(saveCount)
        }
    }

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
}
