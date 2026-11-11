package org.mytonwallet.app_air.uicomponents.widgets.stories

import android.animation.Animator
import android.animation.ValueAnimator
import android.annotation.SuppressLint
import android.content.Context
import android.content.res.ColorStateList
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Outline
import android.graphics.Paint
import android.graphics.RectF
import android.graphics.drawable.GradientDrawable
import android.os.Build
import android.view.Choreographer
import android.view.Gravity
import android.view.MotionEvent
import android.view.RoundedCorner
import android.view.VelocityTracker
import android.view.View
import android.view.ViewConfiguration
import android.view.ViewGroup
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import android.view.ViewOutlineProvider
import android.view.accessibility.AccessibilityManager
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.ScrollView
import androidx.appcompat.widget.AppCompatImageButton
import androidx.core.animation.doOnEnd
import androidx.core.view.ViewCompat
import androidx.core.view.doOnLayout
import androidx.core.view.isVisible
import kotlin.math.abs
import kotlin.math.hypot
import kotlin.math.max
import kotlin.math.min
import org.mytonwallet.app_air.icons.R
import org.mytonwallet.app_air.uicomponents.base.WWindow
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.helpers.PopupHelpers
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.helpers.typeface
import org.mytonwallet.app_air.uicomponents.widgets.IPopup
import org.mytonwallet.app_air.uicomponents.widgets.WButton
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.uicomponents.widgets.stories.StoryPlaybackState.Change
import org.mytonwallet.app_air.uicomponents.widgets.stories.StoryPlaybackState.PauseReason
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage
import org.mytonwallet.app_air.walletcontext.helpers.WInterpolator

@SuppressLint("ViewConstructor")
class StoriesView(
    private val window: WWindow,
    private val pages: List<StoryPage>,
    private val backgroundView: View? = null,
    backgroundColors: IntArray = DEFAULT_BACKGROUND_COLORS,
    private val onCompletion: (() -> Unit)? = null
) : FrameLayout(window),
    IPopup {
    var presentationSource: StoriesPresentationSource? = null

    /** Called once the stories cover the window. */
    var onPresented: (() -> Unit)? = null

    private val playback = StoryPlaybackState(pages)
    private var media: StoryMediaView? = null
    private var preparedMedia: Pair<Int, StoryMediaView>? = null
    private var mediaAnimator: Animator? = null
    private var buttonAnimator: Animator? = null
    private var transitionAnimator: Animator? = null
    private var dragReturnAnimator: Animator? = null
    private var isPresented = false
    private var isClosing = false
    private var isCompletionDelivered = false
    private var isNextButtonVisible = false
    private var previousStatusBarLight: Boolean? = null
    private var previousBottomBarLight: Boolean? = null

    private val choreographer = Choreographer.getInstance()
    private var isClockRunning = false
    private var previousFrameNanos: Long? = null
    private val frameCallback = object : Choreographer.FrameCallback {
        override fun doFrame(frameTimeNanos: Long) {
            if (!isClockRunning) return
            tick(frameTimeNanos)
            if (isClockRunning) choreographer.postFrameCallback(this)
        }
    }

    private val accessibilityManager = window.getSystemService(AccessibilityManager::class.java)
    private val touchExplorationListener =
        AccessibilityManager.TouchExplorationStateChangeListener { updateEnvironment() }

    private val flightRect = RectF()
    private var flightRadius = 0f
    private val clipFrame = FrameLayout(window).apply {
        id = generateViewId()
        outlineProvider = object : ViewOutlineProvider() {
            override fun getOutline(view: View, outline: Outline) {
                if (flightRect.isEmpty) {
                    outline.setRect(0, 0, view.width, view.height)
                    return
                }
                outline.setRoundRect(
                    flightRect.left.toInt(),
                    flightRect.top.toInt(),
                    flightRect.right.toInt(),
                    flightRect.bottom.toInt(),
                    flightRadius
                )
            }
        }
        clipToOutline = true
    }
    private val flightView = FrameLayout(window).apply {
        id = generateViewId()
        pivotX = 0f
        pivotY = 0f
    }
    private val contentView = FrameLayout(window).apply {
        id = generateViewId()
        background = GradientDrawable(
            GradientDrawable.Orientation.TOP_BOTTOM,
            backgroundColors.takeIf { it.isNotEmpty() } ?: DEFAULT_BACKGROUND_COLORS
        )
    }
    private val snapshotView = ImageView(window).apply {
        id = generateViewId()
        scaleType = ImageView.ScaleType.FIT_XY
        alpha = 0f
        importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_NO
    }
    private val actionFlightView = StoryActionFlightView(window).apply {
        id = generateViewId()
        isVisible = false
    }
    private val mediaContainer = FrameLayout(window).apply { id = generateViewId() }
    private val progressView = StoryProgressView(window, pages.size).apply { id = generateViewId() }

    private val closeButton = AppCompatImageButton(window).apply {
        id = generateViewId()
        setImageResource(R.drawable.ic_close)
        imageTintList = ColorStateList.valueOf(Color.WHITE)
        scaleType = ImageView.ScaleType.CENTER
        background = null
        contentDescription = LocaleController.getString("Close")
        setOnClickListener { close() }
    }

    private val titleLabel = WLabel(window).apply {
        setStyle(28f, WFont.Bold)
        setLineHeight(34f)
        letterSpacing = -0.023f
        setTextColor(Color.WHITE)
        gravity = Gravity.CENTER_HORIZONTAL
        ViewCompat.setAccessibilityHeading(this, true)
        ViewCompat.addAccessibilityAction(this, LocaleController.getString("Previous")) { _, _ ->
            navigate(forward = false)
            true
        }
        ViewCompat.addAccessibilityAction(this, LocaleController.getString("Next")) { _, _ ->
            navigate(forward = true)
            true
        }
    }
    private val bodyLabel = WLabel(window).apply {
        setStyle(17f)
        setLineHeight(23f)
        letterSpacing = -0.025f
        setTextColor(Color.WHITE)
        gravity = Gravity.CENTER_HORIZONTAL
    }
    private val copyColumn = LinearLayout(window).apply {
        id = generateViewId()
        orientation = LinearLayout.VERTICAL
        addView(titleLabel, LinearLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT))
        addView(
            bodyLabel,
            LinearLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT).apply { topMargin = 12.dp }
        )
    }
    private val copyScrollView = ScrollView(window).apply {
        id = generateViewId()
        isVerticalScrollBarEnabled = false
        overScrollMode = OVER_SCROLL_NEVER
        addView(copyColumn, LayoutParams(MATCH_PARENT, WRAP_CONTENT))
    }
    private val nextButton = WButton(window, WButton.Type.PRIMARY).apply {
        buttonHeight = BUTTON_HEIGHT.dp
        customTint = NEXT_BUTTON_COLOR
        customTextColor = NEXT_BUTTON_TEXT_COLOR
        visibility = INVISIBLE
        setOnClickListener { navigate(forward = true) }
    }

    private val contentBlock = FrameLayout(window).apply {
        id = generateViewId()
        addView(copyScrollView, LayoutParams(MATCH_PARENT, 0, Gravity.TOP))
        addView(nextButton, LayoutParams(MATCH_PARENT, BUTTON_HEIGHT.dp, Gravity.BOTTOM))
    }

    init {
        id = generateViewId()
        isClickable = true
        importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_YES
        backgroundView?.let {
            it.importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_NO_HIDE_DESCENDANTS
            contentView.addView(it, LayoutParams(MATCH_PARENT, MATCH_PARENT))
        }
        contentView.addView(mediaContainer, LayoutParams(MATCH_PARENT, MATCH_PARENT))
        contentView.addView(progressView, LayoutParams(MATCH_PARENT, PROGRESS_HEIGHT.dp))
        contentView.addView(
            closeButton,
            LayoutParams(
                CLOSE_SIZE.dp,
                CLOSE_SIZE.dp,
                Gravity.TOP or Gravity.END
            )
        )
        contentView.addView(
            contentBlock,
            LayoutParams(MATCH_PARENT, MIN_BLOCK_HEIGHT.dp, Gravity.BOTTOM)
        )
        flightView.addView(contentView, LayoutParams(MATCH_PARENT, MATCH_PARENT))
        flightView.addView(snapshotView, LayoutParams(MATCH_PARENT, MATCH_PARENT))
        clipFrame.addView(flightView, LayoutParams(MATCH_PARENT, MATCH_PARENT))
        addView(clipFrame, LayoutParams(MATCH_PARENT, MATCH_PARENT))
        addView(actionFlightView, LayoutParams(MATCH_PARENT, MATCH_PARENT))
    }

    fun present() {
        if (isPresented) return
        isPresented = true
        PopupHelpers.popupShown(this)
        window.windowView.addView(this, LayoutParams(MATCH_PARENT, MATCH_PARENT))
        previousStatusBarLight = window.forceStatusBarLight
        previousBottomBarLight = window.forceBottomBarLight
        showCurrentPage(animated = false)
        doOnLayout { startPresentation() }
    }

    override fun onBackPressed() {
        close()
    }

    override fun dismiss() {
        close()
    }

    override fun onAttachedToWindow() {
        super.onAttachedToWindow()
        accessibilityManager?.addTouchExplorationStateChangeListener(touchExplorationListener)
        updateEnvironment()
    }

    override fun onDetachedFromWindow() {
        accessibilityManager?.removeTouchExplorationStateChangeListener(touchExplorationListener)
        stopClock()
        super.onDetachedFromWindow()
    }

    override fun onWindowVisibilityChanged(visibility: Int) {
        super.onWindowVisibilityChanged(visibility)
        setPaused(visibility != VISIBLE, PauseReason.BACKGROUND)
    }

    override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
        val width = MeasureSpec.getSize(widthMeasureSpec)
        val height = MeasureSpec.getSize(heightMeasureSpec)
        val insets = window.systemBars
        val left = insets?.left ?: 0
        val top = insets?.top ?: 0
        val right = insets?.right ?: 0
        val bottom = insets?.bottom ?: 0
        val gutter = GUTTER.dp
        (progressView.layoutParams as LayoutParams).setMargins(
            left + gutter,
            top + PROGRESS_TOP.dp,
            right + gutter,
            0
        )
        // Only the 24 dp icon counts for the spacing
        val closeInset = (CLOSE_SIZE - CLOSE_ICON_SIZE).dp / 2
        (closeButton.layoutParams as LayoutParams).apply {
            val side = if (layoutDirection == LAYOUT_DIRECTION_RTL) Gravity.LEFT else Gravity.RIGHT
            gravity = Gravity.TOP or side
            setMargins(
                left + gutter - closeInset,
                top + (PROGRESS_TOP + PROGRESS_HEIGHT + 16).dp - closeInset,
                right + gutter - closeInset,
                0
            )
        }
        val blockWidth = max(1, width - left - right - 2 * gutter)
        copyColumn.measure(
            MeasureSpec.makeMeasureSpec(blockWidth, MeasureSpec.EXACTLY),
            MeasureSpec.makeMeasureSpec(0, MeasureSpec.UNSPECIFIED)
        )
        val isLandscape = width > height
        val actionSpace = if (isLandscape && !isNextButtonVisible) {
            LANDSCAPE_COPY_BOTTOM.dp
        } else {
            BLOCK_ACTION_SPACE.dp
        }
        val available = max(actionSpace, height - top - bottom - 97.dp)
        val minBlockHeight = if (isLandscape) 0 else MIN_BLOCK_HEIGHT.dp
        val blockHeight =
            min(available, max(minBlockHeight, copyColumn.measuredHeight + actionSpace))
        (contentBlock.layoutParams as LayoutParams).apply {
            this.height = blockHeight
            setMargins(left + gutter, 0, right + gutter, bottom + 6.dp)
        }

        copyScrollView.layoutParams.height = blockHeight - actionSpace
        super.onMeasure(widthMeasureSpec, heightMeasureSpec)
    }

    private fun tick(frameTimeNanos: Long) {
        val interval = previousFrameNanos?.let { (frameTimeNanos - it) / 1e9 } ?: 0.0
        previousFrameNanos = frameTimeNanos
        apply(playback.advance(interval, media?.isWaitingForFirstFrame == true))
        progressView.update(playback.index, playback.progress)
    }

    private fun setPaused(paused: Boolean, reason: PauseReason) {
        playback.setPaused(paused, reason)
        previousFrameNanos = null
        if (playback.isPaused || !isAttachedToWindow) stopClock() else startClock()
        media?.setPlaying(!playback.isPaused)
    }

    private fun startClock() {
        if (isClockRunning) return
        isClockRunning = true
        choreographer.postFrameCallback(frameCallback)
    }

    private fun stopClock() {
        isClockRunning = false
        choreographer.removeFrameCallback(frameCallback)
    }

    private fun updateEnvironment() {
        setPaused(
            accessibilityManager?.isTouchExplorationEnabled == true,
            PauseReason.ACCESSIBILITY
        )
    }

    private fun showCurrentPage(animated: Boolean, forward: Boolean = true) {
        val page = pages.getOrNull(playback.index) ?: return
        setPaused(false, PauseReason.SCROLLING)
        mediaAnimator?.end()
        val previous = media
        previous?.setPlaying(false)
        val prepared = preparedMedia
        preparedMedia = null
        val next = prepared?.takeIf { it.first == playback.index }?.second
            ?: StoryMediaView(context, page).also {
                mediaContainer.addView(it, LayoutParams(MATCH_PARENT, MATCH_PARENT))
            }
        if (prepared != null && prepared.second !== next) mediaContainer.removeView(prepared.second)
        next.alpha = 1f
        next.bringToFront()
        media = next
        next.preparePlayback()
        next.setPlaying(!playback.isPaused)
        val shouldAnimate = animated && previous != null && mediaContainer.width > 0 &&
            WGlobalStorage.getAreAnimationsActive()
        if (shouldAnimate) {
            val isRTL = (layoutDirection == LAYOUT_DIRECTION_RTL) != !forward
            val width = mediaContainer.width.toFloat()
            val from = if (isRTL) -4 * width else width
            val to = if (isRTL) 0f else -3 * width
            next.isSweepRTL = isRTL
            next.sweepOffset = from
            val index = playback.index
            mediaAnimator = ValueAnimator.ofFloat(0f, 1f).apply {
                duration = PAGE_TRANSITION_DURATION
                interpolator = WInterpolator.easeInOut
                addUpdateListener {
                    val progress = it.animatedValue as Float
                    next.sweepOffset = from + (to - from) * progress
                    previous.alpha = 1 - progress
                }
                doOnEnd {
                    next.sweepOffset = null
                    mediaContainer.removeView(previous)
                    mediaAnimator = null
                    if (playback.index == index) prepareNextMedia()
                }
                start()
            }
            updateCopy()
            copyColumn.alpha = 0f
            copyColumn.animate().alpha(1f).setDuration(COPY_TRANSITION_DURATION).start()
        } else {
            previous?.let(mediaContainer::removeView)
            updateCopy()
        }
        updateButton(shouldAnimate)
        copyScrollView.scrollTo(0, 0)
        progressView.update(playback.index, playback.progress)
        requestLayout()
        if (animated && accessibilityManager?.isTouchExplorationEnabled == true) {
            titleLabel.announceForAccessibility(page.title)
        }
    }

    private fun prepareNextMedia() {
        val index = playback.index + 1
        val page = pages.getOrNull(index) ?: return
        if (preparedMedia?.first == index || media == null || playback.isPaused(
                PauseReason.HIDDEN
            ) ||
            !WGlobalStorage.getAreAnimationsActive()
        ) {
            return
        }
        preparedMedia?.second?.let(mediaContainer::removeView)
        val next = StoryMediaView(context, page).apply { alpha = 0f }
        mediaContainer.addView(next, 0, LayoutParams(MATCH_PARENT, MATCH_PARENT))
        preparedMedia = index to next
        next.preparePlayback()
    }

    private fun updateCopy() {
        val page = pages.getOrNull(playback.index) ?: return
        titleLabel.text = page.title
        bodyLabel.text = page.body
    }

    private fun updateButton(animated: Boolean) {
        buttonAnimator?.end()
        val title = pages[playback.index].buttonTitle
        val isVisible = title != null
        val wasVisible = isNextButtonVisible
        title?.let { nextButton.setText(it, animated && wasVisible) }
        if (wasVisible == isVisible) return
        isNextButtonVisible = isVisible
        if (!animated) {
            nextButton.alpha = 1f
            nextButton.visibility = if (isVisible) VISIBLE else INVISIBLE
            return
        }
        nextButton.visibility = VISIBLE
        buttonAnimator =
            ValueAnimator.ofFloat(if (isVisible) 0f else 1f, if (isVisible) 1f else 0f).apply {
                duration = BUTTON_TRANSITION_DURATION
                interpolator = WInterpolator.easeInOut
                addUpdateListener {
                    val value = it.animatedValue as Float
                    nextButton.alpha = value
                    nextButton.scaleX = 0.9f + 0.1f * value
                    nextButton.scaleY = nextButton.scaleX
                }
                doOnEnd {
                    nextButton.alpha = 1f
                    nextButton.scaleX = 1f
                    nextButton.scaleY = 1f
                    nextButton.visibility = if (isVisible) VISIBLE else INVISIBLE
                    buttonAnimator = null
                }
                start()
            }
    }

    private fun navigate(forward: Boolean) {
        if (isClosing || isDragging || dragReturnAnimator != null ||
            transitionAnimator != null
        ) {
            return
        }
        previousFrameNanos = null
        apply(if (forward) playback.next() else playback.previous(), forward)
    }

    private fun apply(change: Change, forward: Boolean = true) {
        when (change) {
            Change.NONE -> {}

            Change.PAGE -> showCurrentPage(animated = true, forward = forward)

            Change.COMPLETED -> {
                close()
                if (!isCompletionDelivered) {
                    isCompletionDelivered = true
                    onCompletion?.invoke()
                }
            }
        }
    }

    private enum class TouchArea { BUTTON, COPY, STAGE }

    private var touchArea = TouchArea.STAGE
    private var downX = 0f
    private var downY = 0f
    private var isTapCandidate = false
    private var isHolding = false
    private var isDragging = false
    private var velocityTracker: VelocityTracker? = null
    private val touchSlop = ViewConfiguration.get(window).scaledTouchSlop
    private val holdRunnable = Runnable {
        isHolding = true
        isTapCandidate = false
        setPaused(true, PauseReason.TOUCH)
    }

    override fun dispatchTouchEvent(event: MotionEvent): Boolean {
        if (isClosing || transitionAnimator != null || dragReturnAnimator != null) return true
        velocityTracker?.addMovement(event)
        when (event.actionMasked) {
            MotionEvent.ACTION_DOWN -> {
                velocityTracker?.recycle()
                velocityTracker = VelocityTracker.obtain().apply { addMovement(event) }
                downX = event.x
                downY = event.y
                isHolding = false
                touchArea = when {
                    closeButton.contains(event) ||
                        (isNextButtonVisible && nextButton.contains(event)) ->
                        TouchArea.BUTTON

                    copyScrollView.contains(event) && isCopyScrollable() -> TouchArea.COPY

                    else -> TouchArea.STAGE
                }
                isTapCandidate = touchArea == TouchArea.STAGE
                if (touchArea != TouchArea.BUTTON) postDelayed(holdRunnable, HOLD_DELAY)
            }

            MotionEvent.ACTION_MOVE -> {
                val dx = event.x - downX
                val dy = event.y - downY
                if (isDragging) {
                    setDragDistance(max(0f, dy))
                    return true
                }
                if (touchArea != TouchArea.BUTTON) {
                    if (!isHolding &&
                        hypot(dx, dy) > HOLD_ALLOWABLE_MOVEMENT.dp
                    ) {
                        removeCallbacks(holdRunnable)
                    }
                    if (abs(dx) > touchSlop || abs(dy) > touchSlop) isTapCandidate = false
                    if (touchArea == TouchArea.STAGE && dy > touchSlop && dy > abs(dx)) {
                        beginDrag(event)
                        return true
                    }
                    if (touchArea == TouchArea.COPY && abs(dy) > touchSlop && abs(dy) > abs(dx)) {
                        setPaused(true, PauseReason.SCROLLING)
                    }
                }
            }

            MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> {
                removeCallbacks(holdRunnable)
                val isUp = event.actionMasked == MotionEvent.ACTION_UP
                val tracker = velocityTracker
                tracker?.computeCurrentVelocity(1000)
                val velocityX = tracker?.xVelocity ?: 0f
                val velocityY = tracker?.yVelocity ?: 0f
                tracker?.recycle()
                velocityTracker = null
                if (isDragging) {
                    endDrag(event.y - downY, velocityY, isUp)
                    return true
                }
                super.dispatchTouchEvent(event)
                if (isUp && touchArea != TouchArea.BUTTON &&
                    !isHolding
                ) {
                    handleRelease(event, velocityX)
                }
                isHolding = false
                setPaused(false, PauseReason.TOUCH)
                setPaused(false, PauseReason.SCROLLING)
                return true
            }
        }
        super.dispatchTouchEvent(event)
        return true
    }

    private fun handleRelease(event: MotionEvent, velocityX: Float) {
        val dx = event.x - downX
        val dy = event.y - downY
        val isRTL = layoutDirection == LAYOUT_DIRECTION_RTL
        if (abs(dx) > abs(dy) &&
            (
                abs(dx) > SWIPE_DISTANCE.dp ||
                    (abs(dx) > touchSlop && abs(velocityX) > SWIPE_VELOCITY.dp)
                )
        ) {
            navigate(forward = (dx < 0) != isRTL)
            return
        }
        if (!isTapCandidate) return
        val isLeading = event.x < width / 2f
        navigate(forward = isLeading == isRTL)
    }

    private fun View.contains(event: MotionEvent): Boolean {
        if (!isShown) return false
        val location = IntArray(2).also(::getLocationInWindow)
        val origin = IntArray(2).also(this@StoriesView::getLocationInWindow)
        val x = event.x + origin[0] - location[0]
        val y = event.y + origin[1] - location[1]
        return x >= 0 && y >= 0 && x < width && y < height
    }

    private fun isCopyScrollable() =
        copyScrollView.canScrollVertically(1) || copyScrollView.canScrollVertically(-1)

    private fun beginDrag(event: MotionEvent) {
        removeCallbacks(holdRunnable)
        isDragging = true
        isTapCandidate = false
        setPaused(true, PauseReason.DISMISSAL)
        val cancel = MotionEvent.obtain(event).apply { action = MotionEvent.ACTION_CANCEL }
        super.dispatchTouchEvent(cancel)
        cancel.recycle()
        setDragDistance(max(0f, event.y - downY))
    }

    private fun setDragDistance(distance: Float) {
        applyFlight(
            RectF(0f, distance, width.toFloat(), height + distance),
            deviceCornerRadius() * min(1f, distance / DRAG_ROUNDING_DISTANCE.dp),
            contentAlpha = 1f,
            snapshotAlpha = 0f
        )
    }

    private fun endDrag(distance: Float, velocity: Float, isUp: Boolean) {
        isDragging = false
        isHolding = false
        setPaused(false, PauseReason.TOUCH)
        if (isUp &&
            (distance > height * DISMISS_DISTANCE_FRACTION || velocity > DISMISS_VELOCITY.dp)
        ) {
            close()
            return
        }
        val start = max(0f, distance)
        dragReturnAnimator = ValueAnimator.ofFloat(start, 0f).apply {
            duration = DRAG_RETURN_DURATION
            interpolator = WInterpolator.spring(dampingRatio = 0.86f)
            addUpdateListener { setDragDistance(it.animatedValue as Float) }
            doOnEnd {
                if (isClosing) return@doOnEnd
                dragReturnAnimator = null
                resetFlight()
                setPaused(false, PauseReason.DISMISSAL)
            }
            start()
        }
    }

    private fun startPresentation() {
        setPaused(false, PauseReason.HIDDEN)
        val source = presentationSource
        val anchor = source?.resolve(this)
        val snapshot = anchor?.let { source.makeSnapshot() }
        if (anchor == null || snapshot == null || !WGlobalStorage.getAreAnimationsActive()) {
            anchor?.let { source.hide() }
            runFallbackTransition(isPresenting = true)
            return
        }
        snapshotView.setImageBitmap(snapshot)
        val fullFrame = RectF(0f, 0f, width.toFloat(), height.toFloat())
        val actionFrame = nextButton.frameIn(this)
        val isActionVisible = isNextButtonVisible
        actionFlightView.configure(
            source,
            currentButtonTitle(),
            NEXT_BUTTON_TEXT_COLOR,
            ACTION_TEXT_SIZE.dp
        )
        actionFlightView.isVisible = true
        nextButton.alpha = 0f
        source.hide()
        transitionAnimator = ValueAnimator.ofFloat(0f, 1f).apply {
            duration = PRESENT_DURATION
            interpolator = WInterpolator.spring(dampingRatio = 0.82f)
            addUpdateListener {
                val progress = it.animatedValue as Float
                val clamped = progress.coerceIn(0f, 1f)
                applyFlight(
                    lerp(anchor.frame, fullFrame, progress),
                    lerp(source.cornerRadius, 0f, clamped),
                    contentAlpha = clamped,
                    snapshotAlpha = 1 - clamped
                )
                actionFlightView.update(
                    lerp(anchor.buttonFrame, actionFrame, progress),
                    clamped,
                    alpha = if (isActionVisible) 1f else 1 - clamped
                )
            }
            doOnEnd {
                if (isClosing) return@doOnEnd
                transitionAnimator = null
                actionFlightView.isVisible = false
                nextButton.alpha = 1f
                snapshotView.setImageDrawable(null)
                resetFlight()
                finishPresentation()
            }
            start()
        }
    }

    private fun finishPresentation() {
        setPaused(false, PauseReason.HIDDEN)
        onPresented?.invoke()
        updateEnvironment()
        prepareNextMedia()
        if (pages.isEmpty()) close()
    }

    private fun close() {
        if (isClosing || !isPresented) return
        // Set first: cancelled animators run their end actions, which then keep the current frame
        isClosing = true
        dragReturnAnimator?.cancel()
        dragReturnAnimator = null
        transitionAnimator?.cancel()
        transitionAnimator = null
        isDragging = false
        removeCallbacks(holdRunnable)
        setPaused(true, PauseReason.DISMISSAL)
        val source = presentationSource
        val anchor = source?.resolve(this)
        val snapshot = anchor?.let { source.makeSnapshot() }
        if (anchor == null || snapshot == null || !WGlobalStorage.getAreAnimationsActive()) {
            runFallbackTransition(isPresenting = false)
            return
        }
        snapshotView.setImageBitmap(snapshot)
        val startFrame =
            RectF(
                flightRect.takeIf {
                    !it.isEmpty
                } ?: RectF(0f, 0f, width.toFloat(), height.toFloat())
            )
        val startRadius = if (flightRect.isEmpty) 0f else flightRadius
        val actionFrame = nextButton.frameIn(this)
        val isActionVisible = isNextButtonVisible && nextButton.alpha > 0f
        buttonAnimator?.end()
        actionFlightView.configure(
            source,
            currentButtonTitle(),
            NEXT_BUTTON_TEXT_COLOR,
            ACTION_TEXT_SIZE.dp
        )
        actionFlightView.isVisible = true
        nextButton.alpha = 0f
        transitionAnimator = ValueAnimator.ofFloat(0f, 1f).apply {
            duration = DISMISS_DURATION
            interpolator = WInterpolator.spring(dampingRatio = 0.9f)
            addUpdateListener {
                val progress = it.animatedValue as Float
                val clamped = progress.coerceIn(0f, 1f)
                applyFlight(
                    lerp(startFrame, anchor.frame, progress),
                    lerp(startRadius, source.cornerRadius, clamped),
                    contentAlpha = 1 - clamped,
                    snapshotAlpha = clamped
                )
                actionFlightView.update(
                    lerp(actionFrame, anchor.buttonFrame, progress),
                    1 - clamped,
                    alpha = if (isActionVisible) 1f else clamped
                )
            }
            doOnEnd { fadeOutOverSource() }
            start()
        }
    }

    // Window chrome over the source fades back in
    private fun fadeOutOverSource() {
        presentationSource?.restore()
        transitionAnimator = ValueAnimator.ofFloat(1f, 0f).apply {
            duration = SOURCE_REVEAL_DURATION
            addUpdateListener { alpha = it.animatedValue as Float }
            doOnEnd { finishDismissal() }
            start()
        }
    }

    private fun runFallbackTransition(isPresenting: Boolean) {
        val isAnimated = WGlobalStorage.getAreAnimationsActive()
        if (isPresenting) {
            alpha = 0f
            updateSystemBars(null)
            if (!isAnimated) {
                alpha = 1f
                finishPresentation()
                return
            }
        } else if (!isAnimated) {
            finishDismissal()
            return
        }
        val startAlpha = alpha
        val distance = height.toFloat()
        transitionAnimator = ValueAnimator.ofFloat(0f, 1f).apply {
            duration = if (isPresenting) FALLBACK_DURATION else DISMISS_DURATION
            interpolator = WInterpolator.emphasizedDecelerate
            addUpdateListener {
                val progress = it.animatedValue as Float
                if (isPresenting) {
                    alpha = progress
                } else {
                    alpha = startAlpha * (1 - progress)
                    translationY = distance * progress
                    updateSystemBars(
                        RectF(0f, translationY, width.toFloat(), height + translationY)
                    )
                }
            }
            doOnEnd {
                if (isPresenting && isClosing) return@doOnEnd
                transitionAnimator = null
                if (isPresenting) finishPresentation() else finishDismissal()
            }
            start()
        }
    }

    private fun finishDismissal() {
        transitionAnimator = null
        stopClock()
        mediaAnimator?.cancel()
        presentationSource?.restore()
        window.forceStatusBarLight = previousStatusBarLight
        window.forceBottomBarLight = previousBottomBarLight
        (parent as? ViewGroup)?.removeView(this)
        PopupHelpers.popupDismissed(this)
    }

    private fun applyFlight(rect: RectF, radius: Float, contentAlpha: Float, snapshotAlpha: Float) {
        flightRect.set(rect)
        flightRadius = radius
        clipFrame.invalidateOutline()
        val width = max(1, this.width).toFloat()
        val height = max(1, this.height).toFloat()
        flightView.translationX = rect.left
        flightView.translationY = rect.top
        flightView.scaleX = rect.width() / width
        flightView.scaleY = rect.height() / height
        contentView.alpha = contentAlpha
        snapshotView.alpha = snapshotAlpha
        updateSystemBars(rect)
    }

    /** `null` covers the whole window. */
    private fun updateSystemBars(rect: RectF?) {
        val insets = window.systemBars
        val coversTop = rect == null || rect.top < max(1, insets?.top ?: 0)
        val coversBottom = rect == null || rect.bottom > height - max(1, insets?.bottom ?: 0)
        val statusBarLight = if (coversTop) true else previousStatusBarLight
        val bottomBarLight = if (coversBottom) true else previousBottomBarLight
        if (window.forceStatusBarLight !=
            statusBarLight
        ) {
            window.forceStatusBarLight = statusBarLight
        }
        if (window.forceBottomBarLight !=
            bottomBarLight
        ) {
            window.forceBottomBarLight = bottomBarLight
        }
    }

    private fun resetFlight() {
        flightRect.setEmpty()
        flightRadius = 0f
        clipFrame.invalidateOutline()
        flightView.translationX = 0f
        flightView.translationY = 0f
        flightView.scaleX = 1f
        flightView.scaleY = 1f
        contentView.alpha = 1f
        snapshotView.alpha = 0f
        updateSystemBars(null)
    }

    private fun deviceCornerRadius(): Float {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) return 0f
        return rootWindowInsets?.getRoundedCorner(
            RoundedCorner.POSITION_TOP_LEFT
        )?.radius?.toFloat()
            ?: 0f
    }

    private fun View.frameIn(container: View): RectF {
        val location = IntArray(2).also(::getLocationInWindow)
        val origin = IntArray(2).also(container::getLocationInWindow)
        val left = (location[0] - origin[0]).toFloat()
        val top = (location[1] - origin[1]).toFloat()
        return RectF(left, top, left + width, top + height)
    }

    private fun currentButtonTitle(): String =
        pages.getOrNull(playback.index)?.buttonTitle.orEmpty()

    companion object {
        val DEFAULT_BACKGROUND_COLORS = intArrayOf(
            Color.rgb(0, 183, 255),
            Color.rgb(10, 114, 244),
            Color.rgb(0, 104, 238)
        )

        internal val NEXT_BUTTON_COLOR = Color.WHITE
        private val NEXT_BUTTON_TEXT_COLOR = Color.rgb(11, 31, 68)
        private const val GUTTER = 24
        private const val CLOSE_SIZE = 44
        private const val CLOSE_ICON_SIZE = 24
        private const val PROGRESS_TOP = 12
        private const val PROGRESS_HEIGHT = 3
        private const val BUTTON_HEIGHT = 50
        private const val ACTION_TEXT_SIZE = 16f
        private const val MIN_BLOCK_HEIGHT = 233
        private const val BLOCK_ACTION_SPACE = 76
        private const val LANDSCAPE_COPY_BOTTOM = 18
        private const val HOLD_DELAY = 150L
        private const val HOLD_ALLOWABLE_MOVEMENT = 20
        private const val SWIPE_DISTANCE = 80
        private const val SWIPE_VELOCITY = 300
        private const val DISMISS_DISTANCE_FRACTION = 0.2f
        private const val DISMISS_VELOCITY = 700
        private const val DRAG_RETURN_DURATION = 350L
        private const val PAGE_TRANSITION_DURATION = 400L
        private const val COPY_TRANSITION_DURATION = 400L
        private const val BUTTON_TRANSITION_DURATION = 250L
        private const val PRESENT_DURATION = 650L
        private const val DISMISS_DURATION = 400L
        private const val FALLBACK_DURATION = 200L
        private const val SOURCE_REVEAL_DURATION = 200L
        private const val DRAG_ROUNDING_DISTANCE = 40

        private fun lerp(from: Float, to: Float, progress: Float) = from + (to - from) * progress

        private fun lerp(from: RectF, to: RectF, progress: Float) = RectF(
            lerp(from.left, to.left, progress),
            lerp(from.top, to.top, progress),
            lerp(from.right, to.right, progress),
            lerp(from.bottom, to.bottom, progress)
        )
    }
}

private class StoryActionFlightView(context: Context) : View(context) {
    private val rect = RectF()
    private var progress = 0f
    private var sourceColor = 0
    private var sourceTitle = ""
    private var sourceTextColor = 0
    private var sourceTextSize = 0f
    private var destinationTitle = ""
    private var destinationTextColor = 0
    private var destinationTextSize = 0f
    private val backgroundPaint = Paint(Paint.ANTI_ALIAS_FLAG)
    private val textPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        typeface = WFont.Medium.typeface
        textAlign = Paint.Align.CENTER
    }

    init {
        importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_NO
    }

    fun configure(
        source: StoriesPresentationSource,
        title: String,
        textColor: Int,
        textSize: Float
    ) {
        sourceColor = source.buttonColor
        sourceTitle = source.buttonTitle
        sourceTextColor = source.buttonTextColor
        sourceTextSize = source.buttonTextSize
        destinationTitle = title
        destinationTextColor = textColor
        destinationTextSize = textSize
    }

    fun update(rect: RectF, progress: Float, alpha: Float) {
        this.rect.set(rect)
        this.progress = progress
        this.alpha = alpha.coerceIn(0f, 1f)
        invalidate()
    }

    override fun onDraw(canvas: Canvas) {
        if (rect.isEmpty) return
        backgroundPaint.color = blend(sourceColor, DESTINATION_COLOR, progress)
        val radius = rect.height() / 2
        canvas.drawRoundRect(rect, radius, radius, backgroundPaint)
        drawTitle(canvas, sourceTitle, sourceTextColor, sourceTextSize, 1 - progress)
        drawTitle(canvas, destinationTitle, destinationTextColor, destinationTextSize, progress)
    }

    private fun drawTitle(canvas: Canvas, title: String, color: Int, size: Float, alpha: Float) {
        if (title.isEmpty() || alpha <= 0f) return
        textPaint.color = color
        textPaint.alpha = (Color.alpha(color) * alpha.coerceIn(0f, 1f)).toInt()
        textPaint.textSize = size
        val baseline = rect.centerY() - (textPaint.descent() + textPaint.ascent()) / 2
        canvas.drawText(title, rect.centerX(), baseline, textPaint)
    }

    private fun blend(from: Int, to: Int, progress: Float): Int {
        val t = progress.coerceIn(0f, 1f)
        fun channel(shift: Int) = (
            ((from shr shift) and 0xFF) +
                (((to shr shift) and 0xFF) - ((from shr shift) and 0xFF)) * t
            ).toInt()
        return (channel(24) shl 24) or (channel(16) shl 16) or (channel(8) shl 8) or channel(0)
    }

    private companion object {
        val DESTINATION_COLOR = StoriesView.NEXT_BUTTON_COLOR
    }
}
