package org.mytonwallet.app_air.uicomponents.widgets.coverFlow

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Camera
import android.graphics.Canvas
import android.graphics.LinearGradient
import android.graphics.Matrix
import android.graphics.Paint
import android.graphics.Path
import android.graphics.RectF
import android.graphics.Shader
import android.graphics.drawable.Drawable
import android.util.AttributeSet
import android.view.GestureDetector
import android.view.MotionEvent
import android.view.View
import android.widget.Scroller
import androidx.core.graphics.createBitmap
import androidx.core.graphics.drawable.toDrawable
import androidx.core.graphics.withSave
import androidx.core.net.toUri
import com.facebook.common.executors.CallerThreadExecutor
import com.facebook.common.references.CloseableReference
import com.facebook.datasource.DataSource
import com.facebook.datasource.DataSubscriber
import com.facebook.drawee.backends.pipeline.Fresco
import com.facebook.imagepipeline.image.CloseableBitmap
import com.facebook.imagepipeline.image.CloseableImage
import com.facebook.imagepipeline.request.ImageRequestBuilder
import org.mytonwallet.app_air.uicomponents.AnimationConstants
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.helpers.HapticType
import org.mytonwallet.app_air.uicomponents.helpers.Haptics
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletcontext.utils.AnimUtils.Companion.lerp
import kotlin.math.abs
import kotlin.math.pow
import kotlin.math.roundToInt

class WCoverFlowView @JvmOverloads constructor(
    context: Context,
    attrs: AttributeSet? = null,
    defStyleAttr: Int = 0
) : View(context, attrs, defStyleAttr) {

    // Configuration constants
    private val FIRST_COVER_SPACING = 94f.dp
    private val NEXT_COVER_SPACINGS = 35f.dp
    private val COVER_WIDTH = 144f.dp
    private val COVER_HEIGHT = 144f.dp
    private val MAX_ROTATION = 30f
    private val SCALE_FACTOR = 0.9f
    private val DEFAULT_PLACEHOLDER = WColor.Background

    // Data and state
    private var covers = mutableListOf<CoverItem>()
    private var coverDrawables = mutableMapOf<Int, Drawable>()
    private var placeholderDrawable: Drawable? = null
    private var currentIndex = 0
    private var lastNotifiedIndex = -1  // Track last notified index
    private var scrollOffset = 0f
    private var targetOffset = 0f

    var shouldRenderCenterItem: Boolean = true
        set(value) {
            field = value
            invalidate()
        }

    // Scroll state tracking
    enum class ScrollState {
        IDLE, DRAGGING, SETTLING
    }

    var scrollState = ScrollState.IDLE
        private set

    // Animation and interaction
    private val scroller = Scroller(context)
    private val gestureDetector = GestureDetector(context, CoverFlowGestureListener())
    private var isScrolling = false
    private var lastTouchX = 0f

    // Listeners
    private var onCoverSelectedListener: ((Int) -> Unit)? = null
    private var onScrollStateChangeListener: ((ScrollState) -> Unit)? = null

    init {
        // Create placeholder drawable
        createPlaceholderDrawable()
    }

    fun onDestroy() {
        onCoverSelectedListener = null
        onScrollStateChangeListener = null
    }

    private fun createPlaceholderDrawable() {
        val bitmap = createBitmap(COVER_WIDTH.toInt(), COVER_HEIGHT.toInt())
        val canvas = Canvas(bitmap)
        val paint = Paint(Paint.ANTI_ALIAS_FLAG)

        // Draw gradient placeholder
        val gradient = LinearGradient(
            0f, 0f, COVER_WIDTH, COVER_HEIGHT,
            WColor.SecondaryBackground.color,
            WColor.GroupedBackground.color,
            Shader.TileMode.CLAMP
        )
        paint.shader = gradient
        canvas.drawRoundRect(RectF(0f, 0f, COVER_WIDTH, COVER_HEIGHT), 20f, 20f, paint)

        placeholderDrawable = bitmap.toDrawable(context.resources)
    }

    fun setCovers(newCovers: List<CoverItem>) {
        covers.clear()
        covers.addAll(newCovers)
        coverDrawables.clear()
        currentIndex = 0
        lastNotifiedIndex = -1
        scrollOffset = 0f
        targetOffset = 0f
        setScrollState(ScrollState.IDLE)

        // Load images for covers that have URLs
        loadCoverImages()

        invalidate()
    }

    fun setSelectedIndex(index: Int) {
        scrollToIndex(index, animate = false)
    }

    fun getSelectedIndex(): Int {
        return currentIndex
    }

    private fun setScrollState(newState: ScrollState) {
        if (scrollState != newState) {
            scrollState = newState
            onScrollStateChangeListener?.invoke(newState)
        }
    }

    private fun loadCoverImages() {
        covers.forEachIndexed { index, cover ->
            when {
                cover.imageUrl != null -> {
                    loadImageFromUrl(cover.imageUrl, index)
                }

                else -> {
                    // Use color-based placeholder
                    coverDrawables[index] =
                        createColorDrawable(cover.color ?: DEFAULT_PLACEHOLDER.color)
                }
            }
        }
    }

    private fun loadImageFromUrl(url: String, index: Int) {
        val imageRequest = ImageRequestBuilder
            .newBuilderWithSource(url.toUri())
            .setResizeOptions(
                com.facebook.imagepipeline.common.ResizeOptions(
                    COVER_WIDTH.toInt(),
                    COVER_HEIGHT.toInt()
                )
            )
            .build()

        val imagePipeline = Fresco.getImagePipeline()
        val dataSource = imagePipeline.fetchDecodedImage(imageRequest, this)

        dataSource.subscribe(object : DataSubscriber<CloseableReference<CloseableImage>> {
            override fun onNewResult(dataSource: DataSource<CloseableReference<CloseableImage>>) {
                if (!dataSource.isFinished) {
                    return
                }

                val result = dataSource.result
                if (result != null) {
                    try {
                        val closeableImage = result.get()
                        if (closeableImage is CloseableBitmap) {
                            val bitmap = closeableImage.underlyingBitmap
                            if (bitmap != null && !bitmap.isRecycled) {
                                // Create a copy of the bitmap since the original will be recycled
                                val bitmapCopy = bitmap.copy(bitmap.config!!, false)
                                val drawable = bitmapCopy.toDrawable(context.resources)

                                post {
                                    coverDrawables[index] = drawable
                                    invalidate()
                                }
                            }
                        }
                    } finally {
                        result.close()
                    }
                }
            }

            override fun onFailure(dataSource: DataSource<CloseableReference<CloseableImage>>) {
                post {
                    val cover = covers.getOrNull(index)
                    coverDrawables[index] = cover?.let {
                        createColorDrawable(it.color ?: DEFAULT_PLACEHOLDER.color)
                    } ?: placeholderDrawable!!
                    invalidate()
                }
            }

            override fun onCancellation(dataSource: DataSource<CloseableReference<CloseableImage>>) {
                // Handle cancellation if needed
            }

            override fun onProgressUpdate(dataSource: DataSource<CloseableReference<CloseableImage>>) {
                // Handle progress updates if needed
            }
        }, CallerThreadExecutor.getInstance())
    }

    private fun createColorDrawable(color: Int): Drawable {
        val bitmap = createBitmap(COVER_WIDTH.toInt(), COVER_HEIGHT.toInt())
        val canvas = Canvas(bitmap)
        val paint = Paint(Paint.ANTI_ALIAS_FLAG)
        paint.color = color
        canvas.drawRoundRect(RectF(0f, 0f, COVER_WIDTH, COVER_HEIGHT), 20f, 20f, paint)

        return bitmap.toDrawable(context.resources)
    }

    fun setOnCoverSelectedListener(listener: (Int) -> Unit) {
        onCoverSelectedListener = listener
    }

    fun setOnScrollStateChangeListener(listener: (ScrollState) -> Unit) {
        onScrollStateChangeListener = listener
    }

    var isCollapsed = false
    var animationProgress = 1f
    fun setCollapsed(progress: Float) {
        animationProgress = (1 - progress).coerceIn(0f, 1f)
        isCollapsed = progress > 0
        invalidate()
    }

    fun setExpanded(progress: Float) {
        isCollapsed = false
        animationProgress = (1 - progress).coerceIn(0f, 1f)
        invalidate()
    }

    // Calculate absolute position for a cover index
    private fun getAbsolutePositionForIndex(index: Int): Float {
        if (index == 0) return 0f

        var position = 0f
        for (i in 1..index) {
            position += if (i == 1) FIRST_COVER_SPACING else NEXT_COVER_SPACINGS
        }
        return position
    }

    // Get the fractional index (with interpolation) from scroll offset
    private fun getFractionalIndexFromOffset(offset: Float): Float {
        if (offset <= 0f) return 0f

        var currentOffset = 0f
        var index = 0

        while (index < covers.size - 1) {
            val nextSpacing = if (index == 0) FIRST_COVER_SPACING else NEXT_COVER_SPACINGS
            if (currentOffset + nextSpacing > offset) {
                val progress = (offset - currentOffset) / nextSpacing
                return index + progress
            }
            currentOffset += nextSpacing
            index++
        }

        return (covers.size - 1).toFloat()
    }

    // Get the current center index (rounded)
    private fun getCurrentCenterIndex(): Int {
        return getFractionalIndexFromOffset(scrollOffset).roundToInt().coerceIn(0, covers.size - 1)
    }

    // Check if index changed and notify listener during scroll
    private fun checkAndNotifyIndexChange() {
        val newIndex = getCurrentCenterIndex()
        if (newIndex != lastNotifiedIndex) {
            if (lastNotifiedIndex >= 0) {
                Haptics.play(this, HapticType.SELECTION)
            }
            lastNotifiedIndex = newIndex
            currentIndex = newIndex
            onCoverSelectedListener?.invoke(currentIndex)
        }
    }

    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)

        if (covers.isEmpty()) return

        val centerX = width / 2f - COVER_WIDTH / 2f
        val centerY = height / 2f - COVER_HEIGHT / 2f

        // Get the fractional center index for smooth interpolation
        val fractionalCenterIndex = getFractionalIndexFromOffset(scrollOffset)
        val centerIndex = getCurrentCenterIndex()

        // Draw covers from back to front
        val visibleRange = getVisibleRange(centerIndex)

        // Draw back covers first
        for (i in visibleRange.first until centerIndex) {
            drawCover(canvas, i, fractionalCenterIndex, centerX, centerY)
        }
        for (i in visibleRange.second downTo centerIndex + 1) {
            drawCover(canvas, i, fractionalCenterIndex, centerX, centerY)
        }

        // Draw center cover last
        if (shouldRenderCenterItem && !isCollapsed && animationProgress == 1f)
            drawCover(canvas, centerIndex, fractionalCenterIndex, centerX, centerY)
    }

    private fun drawCover(
        canvas: Canvas,
        index: Int,
        fractionalCenterIndex: Float,
        centerX: Float,
        centerY: Float
    ) {
        // Calculate the position difference from the fractional center
        val position = index - fractionalCenterIndex
        val distance = abs(position)

        val animPow2 = animationProgress.pow(2)
        val FIRST_COVER_SPACING =
            if (isCollapsed)
                lerp(0f, FIRST_COVER_SPACING, animPow2)
            else
                lerp(FIRST_COVER_SPACING * 3f, FIRST_COVER_SPACING, animPow2)
        val NEXT_COVER_SPACINGS =
            if (isCollapsed)
                lerp(0f, NEXT_COVER_SPACINGS, animationProgress.pow(distance * 2))
            else
                NEXT_COVER_SPACINGS
        val MAX_ROTATION =
            if (isCollapsed)
                lerp(0f, MAX_ROTATION, animationProgress.pow(distance * 2))
            else
                lerp(MAX_ROTATION * 2f, MAX_ROTATION, animPow2)
        val SCALE_FACTOR =
            if (isCollapsed)
                lerp(0f, SCALE_FACTOR, animationProgress.pow(distance * 2))
            else
                SCALE_FACTOR
        if (index < 0 || index >= covers.size) return

        // Calculate visual position using variable spacing
        val visualPosition = when {
            position > 0 -> {
                // Right side
                var pos = 0f
                val wholeSteps = position.toInt()
                val fraction = position - wholeSteps

                // Add spacing for whole steps
                for (step in 1..wholeSteps) {
                    pos += if (step == 1) FIRST_COVER_SPACING else NEXT_COVER_SPACINGS
                }

                // Add fractional spacing
                if (fraction > 0) {
                    val nextSpacing =
                        if (wholeSteps == 0) FIRST_COVER_SPACING else NEXT_COVER_SPACINGS
                    pos += fraction * nextSpacing
                }

                pos
            }

            position < 0 -> {
                // Left side
                var pos = 0f
                val wholeSteps = (-position).toInt()
                val fraction = -position - wholeSteps

                // Add spacing for whole steps
                for (step in 1..wholeSteps) {
                    pos -= if (step == 1) FIRST_COVER_SPACING else NEXT_COVER_SPACINGS
                }

                // Add fractional spacing
                if (fraction > 0) {
                    val nextSpacing =
                        if (wholeSteps == 0) FIRST_COVER_SPACING else NEXT_COVER_SPACINGS
                    pos -= fraction * nextSpacing
                }

                pos
            }

            else -> 0f // Center position
        }

        // Calculate 3D transformation based on logical position
        val rotationY = (-position * MAX_ROTATION).coerceIn(-MAX_ROTATION, MAX_ROTATION)
        val scale = 1f - (distance * (1f - SCALE_FACTOR)).coerceAtMost(1f - SCALE_FACTOR)

        val drawable = coverDrawables[index] ?: placeholderDrawable
        drawable?.let {
            canvas.withSave {

                // Prepare transformation matrix
                val matrix = Matrix()
                val camera = Camera()
                camera.save()

                camera.rotateY(rotationY)
                camera.getMatrix(matrix)
                camera.restore()

                matrix.preTranslate(-COVER_WIDTH / 2f, -COVER_HEIGHT / 2f)
                matrix.postTranslate(COVER_WIDTH / 2f, COVER_HEIGHT / 2f)

                val translateX = centerX + visualPosition
                val translateY = centerY

                canvas.translate(translateX, translateY)
                canvas.scale(scale, scale, COVER_WIDTH / 2f, COVER_HEIGHT / 2f)
                canvas.concat(matrix)

                val path = Path().apply {
                    addRoundRect(
                        0f, 0f, COVER_WIDTH, COVER_HEIGHT,
                        12f.dp, 12f.dp,
                        Path.Direction.CW
                    )
                }
                canvas.clipPath(path)

                // Set bounds and draw
                it.setBounds(0, 0, COVER_WIDTH.toInt(), COVER_HEIGHT.toInt())
                it.draw(canvas)

            }
        }
    }

    private fun getVisibleRange(centerIndex: Int): Pair<Int, Int> {
        val start = (centerIndex - 3).coerceAtLeast(0)
        val end = (centerIndex + 4).coerceAtMost(covers.size - 1)
        return Pair(start, end)
    }

    @SuppressLint("ClickableViewAccessibility")
    override fun onTouchEvent(event: MotionEvent): Boolean {
        if (animationProgress != 0f) {
            gestureDetector.onTouchEvent(event)

            when (event.action) {
                MotionEvent.ACTION_DOWN -> {
                    if (!scroller.isFinished) {
                        scroller.abortAnimation()
                    }
                    lastTouchX = event.x
                    isScrolling = true
                    setScrollState(ScrollState.DRAGGING)
                    return true
                }

                MotionEvent.ACTION_MOVE -> {
                    if (isScrolling) {
                        val deltaX = (lastTouchX - event.x) * 0.5f
                        scrollOffset += deltaX
                        val maxOffset = getAbsolutePositionForIndex(covers.size - 1)
                        scrollOffset = scrollOffset.coerceIn(0f, maxOffset)
                        lastTouchX = event.x

                        // Check for index changes during scroll
                        checkAndNotifyIndexChange()

                        invalidate()
                    }
                    return true
                }

                MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> {
                    isScrolling = false
                    setScrollState(ScrollState.SETTLING)
                    if (scroller.isFinished) {
                        snapToNearest()
                    }
                    return true
                }
            }
        }

        return super.onTouchEvent(event)
    }

    fun snapToNearest() {
        val nearestIndex = getFractionalIndexFromOffset(scrollOffset).roundToInt()
        val targetIndex = nearestIndex.coerceIn(0, covers.size - 1)
        targetOffset = getAbsolutePositionForIndex(targetIndex)

        // Update current index
        currentIndex = targetIndex

        // Ensure the final selection is notified
        if (currentIndex != lastNotifiedIndex) {
            lastNotifiedIndex = currentIndex
        }

        animateToTarget()
    }

    private fun animateToTarget() {
        val startOffset = scrollOffset
        val distance = (targetOffset - startOffset).toInt()

        if (abs(distance) > 1) {
            scroller.startScroll(
                startOffset.toInt(),
                0,
                distance,
                0,
                AnimationConstants.VERY_QUICK_ANIMATION.toInt()
            )
            invalidate()
        } else {
            // Animation finished, set to idle
            setScrollState(ScrollState.IDLE)
        }
    }

    override fun computeScroll() {
        if (scroller.computeScrollOffset()) {
            scrollOffset = scroller.currX.toFloat()

            // Check for index changes during settling animation
            if (scrollState == ScrollState.SETTLING) {
                checkAndNotifyIndexChange()
            }

            postInvalidateOnAnimation()
        } else if (scrollState == ScrollState.SETTLING) {
            // Scroller finished, set to idle
            setScrollState(ScrollState.IDLE)
            snapToNearest()
        }
    }

    fun scrollToIndex(index: Int, animate: Boolean = true) {
        if (index in 0 until covers.size) {
            targetOffset = getAbsolutePositionForIndex(index)
            currentIndex = index
            lastNotifiedIndex = index

            if (animate) {
                setScrollState(ScrollState.SETTLING)
                animateToTarget()
            } else {
                scrollOffset = targetOffset
                invalidate()
            }
        }
    }

    private inner class CoverFlowGestureListener : GestureDetector.SimpleOnGestureListener() {
        override fun onSingleTapUp(e: MotionEvent): Boolean {
            val centerX = width / 2f
            val tapX = e.x

            if (tapX < centerX - COVER_WIDTH / 2) {
                // Tap on left side - go to previous
                if (currentIndex > 0) {
                    scrollToIndex(currentIndex - 1)
                }
            } else if (tapX > centerX + COVER_WIDTH / 2) {
                // Tap on right side - go to next
                if (currentIndex < covers.size - 1) {
                    scrollToIndex(currentIndex + 1)
                }
            }

            return true
        }

        override fun onFling(
            e1: MotionEvent?,
            e2: MotionEvent,
            velocityX: Float,
            velocityY: Float
        ): Boolean {
            if (covers.isEmpty()) return false

            val velocity = (-velocityX * 0.3f).toInt()
            val startX = scrollOffset.toInt()
            val minX = 0
            val maxX = getAbsolutePositionForIndex(covers.size - 1).toInt()

            scroller.fling(
                startX, 0,
                velocity, 0,
                minX, maxX,
                0, 0
            )

            val finalX = scroller.finalX.toFloat()
            val targetIndex =
                getFractionalIndexFromOffset(finalX).roundToInt().coerceIn(0, covers.size - 1)
            targetOffset = getAbsolutePositionForIndex(targetIndex)

            val distance = (targetOffset - scrollOffset).toInt()
            val velocityAbs = abs(velocity).coerceAtLeast(1)
            val duration = (5000f * abs(distance) / velocityAbs).coerceIn(150f, 2000f)
            scroller.startScroll(scrollOffset.toInt(), 0, distance, 0, duration.toInt())
            setScrollState(ScrollState.SETTLING)
            postInvalidateOnAnimation()

            return true
        }
    }

    data class CoverItem(
        val imageUrl: String?,
        val color: Int? = null,
    )
}
