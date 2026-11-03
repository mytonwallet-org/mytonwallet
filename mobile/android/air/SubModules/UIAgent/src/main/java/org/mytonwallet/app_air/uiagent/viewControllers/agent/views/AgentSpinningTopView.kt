package org.mytonwallet.app_air.uiagent.viewControllers.agent.views

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.ColorFilter
import android.graphics.LinearGradient
import android.graphics.Matrix
import android.graphics.Paint
import android.graphics.Path
import android.graphics.PixelFormat
import android.graphics.RectF
import android.graphics.Shader
import android.graphics.SurfaceTexture
import android.graphics.drawable.Drawable
import android.view.Choreographer
import android.view.MotionEvent
import android.view.TextureView
import android.view.VelocityTracker
import android.view.View
import android.view.ViewConfiguration
import android.view.ViewGroup
import androidx.recyclerview.widget.RecyclerView
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.ceil
import kotlin.math.cos
import kotlin.math.exp
import kotlin.math.hypot
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt
import kotlin.math.sin
import kotlin.math.sqrt
import kotlin.random.Random
import org.mytonwallet.app_air.uiagent.viewControllers.agent.agentChatBackgroundColor
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.helpers.HapticType
import org.mytonwallet.app_air.uicomponents.helpers.Haptics
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.theme.ThemeManager
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage

/**
 * The Agent's spinning top, in 3D as iOS draws it: a hollow shell of frosted glass in the Agent gradient that spins on
 * its point, its leaning axis going around as a top's does, and nods a little. It moves only while it is on screen and
 * animations are on. Where OpenGL ES 3.0 is unavailable it draws the flat mark, its coating bands sweeping across the
 * body as it turns and the body swaying around its tip as its lean goes round.
 */
@SuppressLint("ViewConstructor")
class AgentSpinningTopView(
    context: Context,
    private val speed: Float = 1f,
    // A top in the chat stands on the chat's background, one in the list on the list's card
    private val isOnChatBackground: Boolean = true
) : ViewGroup(context) {
    private val paint = Paint(Paint.ANTI_ALIAS_FLAG)
    private val shaderMatrix = Matrix()
    private val fitMatrix = Matrix()
    private val markPath = Path()
    private var markFrame = RectF()
    private var shader: LinearGradient? = null
    private var isFrameScheduled = false
    private var isShownOnScreen = false

    // The motion, advanced frame by frame so that a spin-up changes its pace without a jump
    private var lastFrameNanos = 0L
    private var elapsedSeconds = 0.0
    private var turn = 0.0
    private var precessionPhase = 0.0
    private var boost = 0.0

    // The camera's pitch around its elevation: a slow sway, a nod when the held top is let go, and a finger's tilt
    private var pitchOffset = 0.0
    private var pitchVelocity = 0.0
    private var dragPitch = 0.0
    private val swayPhases = doubleArrayOf(Random.nextDouble(2 * PI), Random.nextDouble(2 * PI))

    // A touch: how far the top has grown out of its place (0 at rest, 1 at three times its size)
    private var grip = 0.0
    private var isHolding = false
    private var expansionStartNanos = 0L
    private var expansionFrom = 0.0
    private var isExpanding = false
    private var liftedTop: LiftedTop? = null
    private var liftedRoot: View? = null
    private var touchX = 0f
    private var touchY = 0f
    private var touchStartX = 0f
    private var touchStartY = 0f
    private var touchStartTime = 0L
    private var isTap = false
    private var velocityTracker: VelocityTracker? = null
    private val landing = Runnable { Haptics.play(this, HapticType.LIGHT_TAP) }

    // The 3D top: a canvas a little larger than this view, and while it is grown, one over the window
    private var restingCanvas: TopCanvas? =
        if (AgentSpinningTopRenderer.isAvailable(context)) {
            TopCanvas(context, standsInForFirstFrame = true)
        } else {
            null
        }
    private var liftedCanvas: TopCanvas? = null
    private val renderedFrame = AgentSpinningTopRenderer.Frame()
    private val location = IntArray(2)

    // While the canvas over the window shows the top, the resting canvas is cleared
    private var isRestingCleared = false

    // Where the grown top moves to keep off the screen's sides, in pixels
    private var expansionShift = 0f

    // What is behind the grown top, drawn from the list it sits in as it lifts, for its glass to frost and bend
    private var backdrop: Bitmap? = null

    // Where the backdrop lies, in this view's pixels
    private val backdropRect = RectF()

    /**
     * The top responds to the finger. A tap spins it up, faster with every tap in a row, and it
     * winds down to its own speed; a faster top leans less, and its lean goes round slower. A touch
     * grows it to three times its size above everything else, where a horizontal drag spins it, a
     * vertical one tilts it, and a fling spins it up; let go, it springs back into place.
     */
    var isTouchInteractive = false

    /** What the grown top sees behind it, drawn as it lifts; by default the list the top sits in */
    var backdropSource: View? = null

    /** Holds the motion still, as while the screen showing it doesn't render */
    var isAnimationPaused = false
        set(value) {
            if (field == value) return
            field = value
            redraw()
            scheduleFrameIfNeeded()
        }

    private val frameCallback = Choreographer.FrameCallback {
        isFrameScheduled = false
        val now = System.nanoTime()
        fallBackIfRendererFailed()
        updateExpansion(now)
        val isLifted = liftedTop != null || liftedCanvas != null
        if (isLifted && !isHolding && !isExpanding && grip == 0.0) settle()
        if (isRenderedIn3D) {
            if (isMoving) advance(now) else lastFrameNanos = 0L
            renderCanvases()
            if (restingCanvas?.hasShownFrame == false) invalidate()
        } else {
            invalidate()
            liftedTop?.invalidateSelf()
        }
        scheduleFrameIfNeeded()
    }

    init {
        id = generateViewId()
        importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_NO
        contentDescription = LocaleController.getString("Agent")
        setWillNotDraw(false)
        // The leaning top reaches a little past its box
        clipChildren = false
        clipToPadding = false
        restingCanvas?.let { canvas ->
            canvas.onFrameShown = ::finishSettling
            addView(canvas)
        }
    }

    private val isRenderedIn3D: Boolean
        get() = restingCanvas != null

    override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
        setMeasuredDimension(
            getDefaultSize(suggestedMinimumWidth, widthMeasureSpec),
            getDefaultSize(suggestedMinimumHeight, heightMeasureSpec)
        )
        restingCanvas?.let { canvas ->
            val margin = computeCanvasMargin(measuredWidth, measuredHeight)
            canvas.measure(
                MeasureSpec.makeMeasureSpec(measuredWidth + 2 * margin, MeasureSpec.EXACTLY),
                MeasureSpec.makeMeasureSpec(measuredHeight + 2 * margin, MeasureSpec.EXACTLY)
            )
        }
    }

    override fun onLayout(changed: Boolean, left: Int, top: Int, right: Int, bottom: Int) {
        val canvas = restingCanvas ?: return
        val margin = computeCanvasMargin(width, height)
        canvas.layout(-margin, -margin, width + margin, height + margin)
    }

    // The resting canvas reaches this share of the side past each edge, so the leaning top is never clipped
    private fun computeCanvasMargin(width: Int, height: Int) =
        ceil(min(width, height) * RESTING_CANVAS_MARGIN).toInt()

    override fun onSizeChanged(w: Int, h: Int, oldw: Int, oldh: Int) {
        super.onSizeChanged(w, h, oldw, oldh)
        rebuildMark(w, h)
    }

    override fun onVisibilityAggregated(isVisible: Boolean) {
        super.onVisibilityAggregated(isVisible)
        isShownOnScreen = isVisible
        if (!isVisible) {
            removeCallbacks(landing)
            settleNow()
        } else {
            redraw()
        }
        scheduleFrameIfNeeded()
    }

    override fun onDetachedFromWindow() {
        super.onDetachedFromWindow()
        removeCallbacks(landing)
        removeCallbacks(claimTouch)
        settleNow()
        Choreographer.getInstance().removeFrameCallback(frameCallback)
        isFrameScheduled = false
    }

    override fun onTouchEvent(event: MotionEvent): Boolean {
        if (!isTouchInteractive) return super.onTouchEvent(event)
        when (event.actionMasked) {
            MotionEvent.ACTION_DOWN -> {
                // The top grows from the touch at once, as iOS's does. It takes the touch over after a short hold or a
                // sideways move, so a scroll or a swipe back can still start on it, which lets the top go
                postDelayed(claimTouch, HOLD_DELAY_MS)
                touchX = event.rawX
                touchY = event.rawY
                touchStartX = event.rawX
                touchStartY = event.rawY
                touchStartTime = event.eventTime
                isTap = true
                velocityTracker?.recycle()
                velocityTracker = VelocityTracker.obtain().apply { addMovement(event) }
                removeCallbacks(landing)
                setHolding(true)
            }

            MotionEvent.ACTION_MOVE -> {
                velocityTracker?.addMovement(event)
                val dx = event.rawX - touchStartX
                val dy = event.rawY - touchStartY
                val distance = hypot(dx, dy)
                if (distance > TAP_MOVEMENT.dp) isTap = false
                if (!isTouchClaimed && distance > touchSlop) {
                    removeCallbacks(claimTouch)
                    if (abs(dx) > abs(dy)) claimTouch.run()
                }
                if (isTouchClaimed && isMoving) {
                    spinByFinger(event.rawX - touchX)
                    tiltByFinger(event.rawY - touchY)
                }
                touchX = event.rawX
                touchY = event.rawY
            }

            MotionEvent.ACTION_UP -> {
                removeCallbacks(claimTouch)
                val tracker = velocityTracker
                tracker?.addMovement(event)
                tracker?.computeCurrentVelocity(MILLISECONDS_PER_SECOND)
                val velocity = tracker?.xVelocity ?: 0f
                val releasePower = grip
                if (isTap && event.eventTime - touchStartTime <= TAP_DURATION_MS) {
                    spinUp()
                } else if (isTouchClaimed && abs(velocity) > FLING_VELOCITY.dp) {
                    fling()
                }
                // Let go, the top nods as it springs back into place
                if (isTouchClaimed && isMoving) pitchVelocity -= RELEASE_NOD
                endTouch()
                if (releasePower > LANDING_POWER) postDelayed(landing, LANDING_DELAY_MS)
                performClick()
            }

            MotionEvent.ACTION_CANCEL -> {
                removeCallbacks(claimTouch)
                endTouch()
            }
        }
        return true
    }

    private val touchSlop = ViewConfiguration.get(context).scaledTouchSlop

    // Whether the finger spins and tilts the top, which the lists around it then leave alone
    private var isTouchClaimed = false
    private val claimTouch = Runnable {
        isTouchClaimed = true
        parent?.requestDisallowInterceptTouchEvent(true)
    }

    private fun endTouch() {
        isTouchClaimed = false
        velocityTracker?.recycle()
        velocityTracker = null
        dragPitch = 0.0
        setHolding(false)
    }

    private fun spinUp() {
        if (!isMoving) return
        boost = min(MAXIMUM_BOOST, boost + TAP_BOOST + TAP_BOOST_GROWTH * boost)
    }

    private fun fling() {
        if (!isMoving) return
        boost = min(MAXIMUM_BOOST, boost + FLING_BOOST)
    }

    // A drag across the lifted top's width turns it once
    private fun spinByFinger(dx: Float) {
        val width = markFrame.width() * (1 + 2 * grip).toFloat()
        if (width > 0f) turn = (turn + dx / width + 1.0) % 1.0
    }

    // A vertical drag tilts the held top toward or away from the viewer, less and less the further it goes
    private fun tiltByFinger(dy: Float) {
        dragPitch += dy / 1f.dp * PI / DRAG_SCALE
    }

    // The top grows out of its place at once and springs back when let go
    private fun setHolding(shouldHold: Boolean) {
        if (isHolding == shouldHold) return
        val now = System.nanoTime()
        updateExpansion(now)
        isHolding = shouldHold
        if (!WGlobalStorage.getAreAnimationsActive()) {
            isExpanding = false
            grip = if (shouldHold) 1.0 else 0.0
        } else {
            isExpanding = true
            expansionStartNanos = now
            expansionFrom = grip
        }
        if (shouldHold || grip != 0.0 || isExpanding) lift() else settle()
        redraw()
        scheduleFrameIfNeeded()
    }

    private fun updateExpansion(now: Long) {
        if (!isExpanding) return
        val elapsed = max(0.0, (now - expansionStartNanos) / NANOS_PER_SECOND)
        if (isHolding) {
            val progress = min(1.0, elapsed / GROW_DURATION_S)
            val eased = progress * progress * (3 - 2 * progress)
            val settle = 1 - exp(-GROW_DAMPING * eased) *
                (
                    cos(GROW_FREQUENCY * eased) +
                        GROW_DAMPING / GROW_FREQUENCY * sin(GROW_FREQUENCY * eased)
                    )
            grip = expansionFrom + (1 - expansionFrom) * settle
            if (progress == 1.0) {
                grip = 1.0
                isExpanding = false
            }
        } else {
            val spring = exp(-RELEASE_DAMPING * elapsed) * cos(RELEASE_FREQUENCY * elapsed)
            grip = expansionFrom * spring
            if (elapsed >= RELEASE_DURATION_S) {
                grip = 0.0
                isExpanding = false
            }
        }
    }

    // While it is grown, the top draws over its window, so that nothing clips it
    private fun lift() {
        if (!isAttachedToWindow) return
        val root = rootView ?: return
        if (isRenderedIn3D) {
            if (liftedCanvas == null) liftCanvas(root)
            return
        }
        if (liftedTop != null) return
        liftedRoot = root
        liftedTop = LiftedTop().also {
            it.setBounds(0, 0, root.width, root.height)
            root.overlay.add(it)
        }
    }

    private fun liftCanvas(root: View) {
        val overlay = (root as? ViewGroup)?.overlay ?: return
        liftedRoot = root
        expansionShift = computeExpansionShift(root)
        val canvas = TopCanvas(context, standsInForFirstFrame = false)
        // The resting canvas clears once the lifted one shows the top
        canvas.onFrameShown = {
            if (liftedCanvas === canvas && !isRestingCleared) {
                isRestingCleared = true
                renderCanvases()
            }
        }
        val (canvasWidth, canvasHeight) = computeExpandedCanvasSize()
        canvas.measure(
            MeasureSpec.makeMeasureSpec(canvasWidth, MeasureSpec.EXACTLY),
            MeasureSpec.makeMeasureSpec(canvasHeight, MeasureSpec.EXACTLY)
        )
        canvas.layout(0, 0, canvasWidth, canvasHeight)
        liftedCanvas = canvas
        captureBackdrop(canvasWidth, canvasHeight)
        placeLiftedCanvas()
        overlay.add(canvas)
    }

    /**
     * Draws the backdrop source under the grown top's canvas, with a margin, into the backdrop. The tops themselves
     * draw nothing there, as their canvases show only on screen; anything the source can't draw this way leaves the
     * flat color
     */
    private fun captureBackdrop(canvasWidth: Int, canvasHeight: Int) {
        backdrop = null
        val source = findBackdropSource() ?: return
        updateExpandedCanvasOffset()
        val margin = EXPANDED_BACKDROP_MARGIN.dp
        val centerX = width / 2f + expandedOffsetX
        val centerY = height / 2f + expandedOffsetY
        backdropRect.set(
            centerX - canvasWidth / 2f - margin,
            centerY - canvasHeight / 2f - margin,
            centerX + canvasWidth / 2f + margin,
            centerY + canvasHeight / 2f + margin
        )
        val scale = min(1f, BACKDROP_PIXELS_PER_DP / resources.displayMetrics.density)
        val bitmapWidth = max(1, (backdropRect.width() * scale).roundToInt())
        val bitmapHeight = max(1, (backdropRect.height() * scale).roundToInt())
        getLocationInWindow(location)
        val viewX = location[0]
        val viewY = location[1]
        source.getLocationInWindow(location)
        val bitmap = Bitmap.createBitmap(bitmapWidth, bitmapHeight, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)
        canvas.drawColor(backdropColor)
        canvas.scale(scale, scale)
        canvas.translate(
            location[0] - viewX - backdropRect.left,
            location[1] - viewY - backdropRect.top
        )
        try {
            source.draw(canvas)
        } catch (_: IllegalArgumentException) {
            // A hardware-only bitmap or node in the list
            return
        } catch (_: IllegalStateException) {
            return
        }
        backdrop = bitmap
    }

    private fun findBackdropSource(): View? {
        backdropSource?.let { return it }
        var current = parent
        while (current != null) {
            if (current is RecyclerView) return current
            current = current.parent
        }
        return null
    }

    // The glass takes the background the top sits on as what is seen through it
    private val backdropColor: Int
        get() = if (isOnChatBackground) agentChatBackgroundColor else WColor.Background.color

    // Back in its place: the resting canvas shows the top again, and the lifted one goes once it has
    private fun settle() {
        isHolding = false
        isExpanding = false
        grip = 0.0
        velocityTracker?.recycle()
        velocityTracker = null
        if (liftedCanvas != null) {
            if (isRestingCleared) {
                isRestingCleared = false
                renderCanvases()
            }
            if (restingCanvas?.hasTarget != true || !isShownOnScreen) removeLiftedCanvas()
        }
        val lifted = liftedTop ?: return
        liftedRoot?.overlay?.remove(lifted)
        liftedTop = null
        liftedRoot = null
        invalidate()
    }

    // Back in its place, at once
    private fun settleNow() {
        settle()
        isRestingCleared = false
        removeLiftedCanvas()
    }

    private fun finishSettling() {
        val isSettled = grip == 0.0 && !isHolding && !isExpanding
        if (!isRestingCleared && liftedCanvas != null && isSettled) {
            removeLiftedCanvas()
        }
    }

    private fun removeLiftedCanvas() {
        val canvas = liftedCanvas ?: return
        liftedCanvas = null
        if (backdrop != null) AgentSpinningTopRenderer.forgetBackdrop()
        backdrop = null
        (liftedRoot as? ViewGroup)?.overlay?.remove(canvas)
        if (liftedTop == null) liftedRoot = null
    }

    private fun fallBackIfRendererFailed() {
        if (!AgentSpinningTopRenderer.hasFailed) return
        val canvas = restingCanvas ?: return
        restingCanvas = null
        removeView(canvas)
        removeLiftedCanvas()
        isRestingCleared = false
        invalidate()
    }

    override fun onDraw(canvas: Canvas) {
        // The 3D top draws on its canvases, and the grown flat one over the window
        if (liftedTop != null) return
        val resting = restingCanvas
        if (resting == null) {
            drawTop(canvas)
        } else if (!resting.hasShownFrame) {
            // The canvas has no frame yet: the flat mark stands in, moved by the 3D top's motion
            drawTop(canvas, advancesMotion = false)
        }
    }

    // A change that shows on a still top
    private fun redraw() {
        fallBackIfRendererFailed()
        if (isRenderedIn3D) renderCanvases() else invalidate()
    }

    private fun drawTop(canvas: Canvas, advancesMotion: Boolean = true) {
        val shader = shader ?: return
        if (advancesMotion) {
            if (isMoving) advance(System.nanoTime()) else lastFrameNanos = 0L
        }
        // The lean goes round, which shows as a sway around the tip, with a slight nod; held, it
        // leans half as much
        val nod = 1 + NOD_AMPLITUDE * sin(2 * PI * elapsedSeconds / NOD_PERIOD_S)
        val hold = 1 - HELD_LEAN_REDUCTION * min(1.0, max(0.0, grip))
        // A top that doesn't move stands upright
        val sway = if (isMoving) {
            (SWAY_DEGREES * cos(precessionPhase) * nod * hold / sqrt(1 + boost)).toFloat()
        } else {
            0f
        }
        val frame = markFrame
        shaderMatrix.setTranslate((turn * frame.width() * BAND_TILE_SCALE).toFloat(), 0f)
        shader.setLocalMatrix(shaderMatrix)
        canvas.save()
        canvas.rotate(
            sway,
            frame.left + frame.width() * AgentMark.TIP_X,
            frame.top + frame.height() * AgentMark.TIP_Y
        )
        canvas.drawPath(markPath, paint)
        canvas.restore()
    }

    private fun advance(nowNanos: Long) {
        val deltaSeconds = if (lastFrameNanos == 0L) {
            0.0
        } else {
            ((nowNanos - lastFrameNanos) / NANOS_PER_SECOND).coerceIn(0.0, MAXIMUM_FRAME_S)
        }
        lastFrameNanos = nowNanos
        elapsedSeconds += deltaSeconds * speed
        // One turn of the body moves the coating bands by one tile
        turn = (turn + deltaSeconds * speed * (1 + boost) / TURN_PERIOD_S) % 1.0
        precessionPhase =
            (precessionPhase + 2 * PI * deltaSeconds * speed / PRECESSION_PERIOD_S / (1 + boost)) %
            (2 * PI)
        boost *= exp(-deltaSeconds / BOOST_DECAY_S)
        if (boost < MINIMUM_BOOST) boost = 0.0
        if (isRenderedIn3D) advancePitch(deltaSeconds)
    }

    // The pitch follows its target on a stiff spring: the sway at rest, the finger's tilt while held
    private fun advancePitch(deltaSeconds: Double) {
        val target = if (isHolding) {
            dragPitch / (1 + abs(dragPitch) / PITCH_LIMIT)
        } else {
            val time = elapsedSeconds / speed
            SWAY_SCALE * (
                SWAY_AMPLITUDE_A * sin(2 * PI / SWAY_PERIOD_A_S * time + swayPhases[0]) +
                    SWAY_AMPLITUDE_B * sin(2 * PI / SWAY_PERIOD_B_S * time + swayPhases[1])
                )
        }
        val stiffness = PITCH_SPRING_FREQUENCY * PITCH_SPRING_FREQUENCY
        val damping = 2 * PITCH_SPRING_DAMPING * PITCH_SPRING_FREQUENCY
        var remaining = deltaSeconds
        while (remaining > 0) {
            val step = min(remaining, PITCH_SPRING_STEP_S)
            pitchVelocity += ((target - pitchOffset) * stiffness - damping * pitchVelocity) * step
            pitchOffset += pitchVelocity * step
            remaining -= step
        }
    }

    private val isMoving: Boolean
        get() = isShownOnScreen && isAttachedToWindow && !isAnimationPaused &&
            WGlobalStorage.getAreAnimationsActive()

    private fun scheduleFrameIfNeeded() {
        if (isFrameScheduled) return
        if (!isMoving && !isExpanding) return
        isFrameScheduled = true
        Choreographer.getInstance().postFrameCallback(frameCallback)
    }

    private fun rebuildMark(width: Int, height: Int) {
        if (width <= 0 || height <= 0) return
        // The silhouette, not its design box, is centered, keeping room for the sway
        markFrame = AgentMark.fit(fitMatrix, width.toFloat(), height.toFloat(), CONTENT_FRACTION)
        AgentMark.path.transform(fitMatrix, markPath)
        shader = LinearGradient(
            markFrame.left,
            0f,
            markFrame.left + markFrame.width() * BAND_TILE_SCALE,
            markFrame.height() * BAND_TILT,
            AGENT_GRADIENT_BAND_COLORS,
            AGENT_GRADIENT_BAND_POSITIONS,
            Shader.TileMode.REPEAT
        )
        paint.shader = shader
        redraw()
    }

    // The 3D top

    private fun renderCanvases() {
        val resting = restingCanvas ?: return
        // A cleared canvas needs no more frames until it shows the top again
        val isCleared = isRestingCleared && resting.isEmpty
        if (resting.hasTarget && width > 0 && height > 0 && !isCleared) {
            composeFrame(isLifted = false)
            renderedFrame.isEmpty = isRestingCleared
            resting.render(renderedFrame)
        }
        val lifted = liftedCanvas ?: return
        placeLiftedCanvas()
        if (lifted.hasTarget) {
            composeFrame(isLifted = true)
            lifted.render(renderedFrame)
        }
    }

    // Pixels per model unit of the resting top: its box is this view's square
    private val restingUnit: Float
        get() = min(width, height) / 2f / AgentSpinningTopGeometry.BOX_HALF_EXTENT

    private fun composeFrame(isLifted: Boolean) {
        val frame = renderedFrame
        val strength = min(1.0, max(0.0, grip)).toFloat()
        val pixelsPerUnit = restingUnit * (1 + 2 * grip).toFloat()
        // The box sits on the resting top, moving away from a screen edge as the top grows, wherever its canvas is
        var boxX = 0f
        var boxY = 0f
        if (isLifted) {
            updateExpandedCanvasOffset()
            boxX = expansionShift * strength - expandedOffsetX
            boxY = -expandedOffsetY
        }
        frame.pixelsPerUnit = pixelsPerUnit
        frame.originX = boxX + AgentSpinningTopGeometry.RESTING_OFFSET_X * pixelsPerUnit
        frame.originY = -boxY + AgentSpinningTopGeometry.RESTING_OFFSET_Y * pixelsPerUnit
        frame.strength = strength
        frame.isDark = ThemeManager.isDark
        val color = backdropColor
        frame.backdrop[0] = Color.red(color) / 255f
        frame.backdrop[1] = Color.green(color) / 255f
        frame.backdrop[2] = Color.blue(color) / 255f
        // The grown top's canvas sees the captured backdrop, placed in its own pixels
        val captured = backdrop.takeIf { isLifted }
        val lifted = liftedCanvas
        frame.backdropBitmap = captured
        if (captured != null && lifted != null) {
            val canvasLeft = width / 2f + expandedOffsetX - lifted.width / 2f
            val canvasTop = height / 2f + expandedOffsetY - lifted.height / 2f
            frame.backdropRect[0] = backdropRect.left - canvasLeft
            frame.backdropRect[1] = backdropRect.top - canvasTop
            frame.backdropRect[2] = backdropRect.width()
            frame.backdropRect[3] = backdropRect.height()
        }
        frame.isEmpty = false
        if (WGlobalStorage.getAreAnimationsActive()) {
            // A faster spin stands the top up; held, it leans half as much
            val nod = 1 + NOD_AMPLITUDE * sin(2 * PI * elapsedSeconds / NOD_PERIOD_S)
            val hold = 1 - strength * HELD_LEAN_REDUCTION
            val lean = AgentSpinningTopGeometry.LEAN * nod / sqrt(1 + boost) * hold
            AgentSpinningTopGeometry.computeTransform(
                yaw = (turn * 2 * PI).toFloat(),
                pitch = AgentSpinningTopGeometry.VIEW_PITCH + pitchOffset.toFloat(),
                lean = lean.toFloat(),
                leanDirection = precessionPhase.toFloat(),
                out = frame.rotation
            )
        } else {
            // Without animations the top leans to the right, as the mark does
            AgentSpinningTopGeometry.computeTransform(
                yaw = (turn * 2 * PI).toFloat(),
                pitch = AgentSpinningTopGeometry.VIEW_PITCH,
                lean = AgentSpinningTopGeometry.LEAN,
                leanDirection = 0f,
                out = frame.rotation
            )
        }
    }

    // Pixels per model unit of the threefold top
    private val expandedUnit: Float
        get() = restingUnit * EXPANDED_SCALE

    /** The canvas over the window covers wherever the threefold top can reach, so tilting it never clips it */
    private fun computeExpandedCanvasSize(): Pair<Int, Int> {
        val margin = 2 * EXPANDED_REACH_MARGIN
        val minimum = MINIMUM_EXPANDED_CANVAS_SIDE.dp
        val unit = expandedUnit
        val reachX = EXPANDED_REACH_MAX_X - EXPANDED_REACH_MIN_X + margin
        val reachY = EXPANDED_REACH_MAX_Y - EXPANDED_REACH_MIN_Y + margin
        return Pair(
            max(minimum, ceil(reachX * unit).toInt()),
            max(minimum, ceil(reachY * unit).toInt())
        )
    }

    // The expanded canvas's center relative to the resting top's, in pixels, y down
    private var expandedOffsetX = 0f
    private var expandedOffsetY = 0f

    private fun updateExpandedCanvasOffset() {
        val unit = expandedUnit
        expandedOffsetX = (EXPANDED_REACH_MIN_X + EXPANDED_REACH_MAX_X) / 2 * unit + expansionShift
        expandedOffsetY = -(EXPANDED_REACH_MIN_Y + EXPANDED_REACH_MAX_Y) / 2 * unit
    }

    // The canvas over the window follows this view, for example while the list behind it scrolls
    private fun placeLiftedCanvas() {
        val canvas = liftedCanvas ?: return
        val root = liftedRoot ?: return
        getLocationInWindow(location)
        val restingX = location[0]
        val restingY = location[1]
        root.getLocationInWindow(location)
        updateExpandedCanvasOffset()
        val centerX = restingX - location[0] + width / 2f + expandedOffsetX
        val centerY = restingY - location[1] + height / 2f + expandedOffsetY
        canvas.translationX = centerX - canvas.width / 2f
        canvas.translationY = centerY - canvas.height / 2f
    }

    /**
     * How far the growing top moves away from a side of the screen it would otherwise cross: a top near the edge grows
     * toward the middle, keeping 16 dp from the side, or as far as it is from it already
     */
    private fun computeExpansionShift(root: View): Float {
        getLocationInWindow(location)
        val restingLeft = location[0].toFloat()
        root.getLocationInWindow(location)
        val left = restingLeft - location[0]
        val right = left + width
        val center = left + width / 2f
        val bodyLeft = center + EXPANDED_BODY_REACH_MIN_X * expandedUnit
        val bodyRight = center + EXPANDED_BODY_REACH_MAX_X * expandedUnit
        val leftInset = max(0f, min(SCREEN_EDGE_INSET.dp, left))
        val rightInset = max(0f, min(SCREEN_EDGE_INSET.dp, root.width - right))
        return when {
            bodyLeft < leftInset -> leftInset - bodyLeft
            bodyRight > root.width - rightInset -> root.width - rightInset - bodyRight
            else -> 0f
        }
    }

    /**
     * A canvas the 3D top draws into. The resting one shows its first frame only a few frames after it appears, as its
     * surface comes then; until then the flat mark stands in for it, so the top comes with whatever appears around it
     */
    private inner class TopCanvas(context: Context, private val standsInForFirstFrame: Boolean) :
        TextureView(context),
        TextureView.SurfaceTextureListener {
        private var target: AgentSpinningTopRenderer.Target? = null

        /** Whether the canvas shows the top, or the flat mark stands in for it */
        var hasShownFrame = false
            private set

        /** Called as the canvas shows a new frame */
        var onFrameShown: (() -> Unit)? = null

        val hasTarget: Boolean
            get() = target != null

        /** Whether the last frame drawn was empty */
        var isEmpty = false
            private set

        init {
            id = generateViewId()
            isOpaque = false
            importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_NO
            surfaceTextureListener = this
        }

        fun render(frame: AgentSpinningTopRenderer.Frame) {
            val target = target ?: return
            isEmpty = frame.isEmpty
            target.render(frame)
        }

        override fun onSurfaceTextureAvailable(surface: SurfaceTexture, width: Int, height: Int) {
            target = AgentSpinningTopRenderer.createTarget(surface)
            isEmpty = false
            hasShownFrame = !standsInForFirstFrame
            renderCanvases()
        }

        override fun onSurfaceTextureSizeChanged(surface: SurfaceTexture, width: Int, height: Int) {
            renderCanvases()
        }

        // The renderer releases the surface once it no longer draws into it
        override fun onSurfaceTextureDestroyed(surface: SurfaceTexture): Boolean {
            target?.release()
            target = null
            return false
        }

        override fun onSurfaceTextureUpdated(surface: SurfaceTexture) {
            if (!hasShownFrame) {
                hasShownFrame = true
                this@AgentSpinningTopView.invalidate()
            }
            onFrameShown?.invoke()
        }
    }

    /**
     * The grown flat top over its window, centered where the top rests. A top near a side of the screen
     * grows toward the middle, keeping 16 dp from the side, or as far as it is from it already.
     */
    private inner class LiftedTop : Drawable() {
        private val location = IntArray(2)

        override fun draw(canvas: Canvas) {
            if (width <= 0 || height <= 0) return
            getLocationInWindow(location)
            val scale = (1 + 2 * grip).toFloat()
            val share = min(1.0, max(0.0, grip)).toFloat()
            canvas.save()
            canvas.translate(location[0] + computeEdgeShift() * share, location[1].toFloat())
            canvas.scale(scale, scale, width / 2f, height / 2f)
            drawTop(canvas)
            canvas.restore()
        }

        private fun computeEdgeShift(): Float {
            val windowWidth = bounds.width().toFloat()
            val restingLeft = location[0].toFloat()
            val restingRight = restingLeft + width
            val centerX = restingLeft + width / 2f
            val halfWidth = markFrame.width() * EXPANDED_SCALE / 2f
            val leftInset = max(0f, min(SCREEN_EDGE_INSET.dp, restingLeft))
            val rightInset = max(0f, min(SCREEN_EDGE_INSET.dp, windowWidth - restingRight))
            return when {
                centerX - halfWidth < leftInset -> leftInset - (centerX - halfWidth)

                centerX + halfWidth > windowWidth - rightInset ->
                    windowWidth - rightInset - (centerX + halfWidth)

                else -> 0f
            }
        }

        override fun setAlpha(alpha: Int) = Unit

        override fun setColorFilter(colorFilter: ColorFilter?) = Unit

        @Deprecated("Deprecated in Java")
        override fun getOpacity(): Int = PixelFormat.TRANSLUCENT
    }

    private companion object {
        const val NANOS_PER_SECOND = 1_000_000_000.0
        const val MILLISECONDS_PER_SECOND = 1000
        const val TURN_PERIOD_S = 1.2
        const val PRECESSION_PERIOD_S = 2.1
        const val NOD_PERIOD_S = 1.35
        const val NOD_AMPLITUDE = 0.12
        const val SWAY_DEGREES = 8.0
        const val HELD_LEAN_REDUCTION = 0.5
        const val CONTENT_FRACTION = 0.92f
        const val BAND_TILE_SCALE = 1.6f
        const val BAND_TILT = 0.35f
        const val MAXIMUM_FRAME_S = 0.05
        const val TAP_DURATION_MS = 250L

        const val TAP_MOVEMENT = 8f
        const val HOLD_DELAY_MS = 150L
        const val TAP_BOOST = 1.0
        const val TAP_BOOST_GROWTH = 0.5
        const val FLING_VELOCITY = 600f
        const val FLING_BOOST = 6.0
        const val MAXIMUM_BOOST = 12.0
        const val BOOST_DECAY_S = 1.6
        const val MINIMUM_BOOST = 0.001
        const val EXPANDED_SCALE = 3f
        const val SCREEN_EDGE_INSET = 16f
        const val GROW_DURATION_S = 0.46
        const val GROW_DAMPING = 5.6
        const val GROW_FREQUENCY = 6.2
        const val RELEASE_DAMPING = 4.2
        const val RELEASE_FREQUENCY = 7.0
        const val RELEASE_DURATION_S = 1.96
        const val LANDING_POWER = 0.2
        const val LANDING_DELAY_MS = 200L
        const val RESTING_CANVAS_MARGIN = 0.1f

        // Where the threefold top can reach around its box's center, in model units, y up, however it is tilted, and
        // the margin its canvas keeps around that for the springy overshoot
        const val EXPANDED_REACH_MIN_X = -1.22f
        const val EXPANDED_REACH_MAX_X = 0.96f
        const val EXPANDED_REACH_MIN_Y = -1.52f
        const val EXPANDED_REACH_MAX_Y = 0.82f
        const val EXPANDED_REACH_MARGIN = 0.1f
        const val MINIMUM_EXPANDED_CANVAS_SIDE = 160
        const val EXPANDED_BACKDROP_MARGIN = 12f
        const val BACKDROP_PIXELS_PER_DP = 2f

        // The held top's body across, around its box's center in model units: the rim around the point, and the
        // leaning stem to the right
        const val EXPANDED_BODY_REACH_MIN_X = -0.87f
        const val EXPANDED_BODY_REACH_MAX_X = 0.75f

        // The pitch's sway, its spring, the nod a release gives it and how far a finger tilts it, in radians
        const val SWAY_SCALE = 0.45
        const val SWAY_AMPLITUDE_A = 0.17
        const val SWAY_AMPLITUDE_B = 0.10
        const val SWAY_PERIOD_A_S = 5.3
        const val SWAY_PERIOD_B_S = 8.9
        const val PITCH_SPRING_FREQUENCY = 6 * PI
        const val PITCH_SPRING_DAMPING = 0.8
        const val PITCH_SPRING_STEP_S = 1 / 120.0
        const val PITCH_LIMIT = 1.1
        const val RELEASE_NOD = 2.2
        const val DRAG_SCALE = 220.0
    }
}

/** The Agent gradient as bands that repeat seamlessly */
internal val AGENT_GRADIENT_BAND_COLORS = intArrayOf(
    0xFF0088FF.toInt(),
    0xFF00BEFF.toInt(),
    0xFFB656FF.toInt(),
    0xFF00BEFF.toInt(),
    0xFF0088FF.toInt()
)
internal val AGENT_GRADIENT_BAND_POSITIONS = floatArrayOf(0f, 0.1977f, 0.5f, 0.8023f, 1f)
