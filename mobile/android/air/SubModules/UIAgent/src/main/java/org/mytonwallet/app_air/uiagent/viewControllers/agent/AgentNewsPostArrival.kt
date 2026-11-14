package org.mytonwallet.app_air.uiagent.viewControllers.agent

import android.graphics.Bitmap
import android.graphics.Camera
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.ColorFilter
import android.graphics.Matrix
import android.graphics.Paint
import android.graphics.PixelFormat
import android.graphics.Rect
import android.graphics.RectF
import android.graphics.drawable.Drawable
import android.view.Choreographer
import android.view.View
import android.view.ViewGroup
import android.view.ViewTreeObserver
import androidx.core.graphics.createBitmap
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.cos
import kotlin.math.exp
import kotlin.math.ln
import kotlin.math.roundToInt
import kotlin.math.sin
import kotlin.math.sqrt
import org.mytonwallet.app_air.uiagent.viewControllers.agent.cells.AgentHintsCell
import org.mytonwallet.app_air.uiagent.viewControllers.agent.cells.AgentNewsPostCell
import org.mytonwallet.app_air.uiagent.viewControllers.agent.views.AgentPreDrawBinding
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.extensions.getLocationInWindow
import org.mytonwallet.app_air.walletbasecontext.utils.x
import org.mytonwallet.app_air.walletbasecontext.utils.y

/** A card of the News feed that flies into its discussion's post: a news item's or a digest's */
internal interface AgentNewsFlightSource {
    /** The card's bubble without its tail, and where it is in the window */
    fun makeFlightSnapshot(): Pair<Bitmap, Rect>?

    /** Hides the card while its picture flies into the discussion, so the feed does not show it twice */
    fun setFlightSourceHidden(isHidden: Boolean)
}

/** [bubble]'s picture without the tail its start padding holds, and its frame in the window */
internal fun makeAgentBubbleFlightSnapshot(bubble: View): Pair<Bitmap, Rect>? {
    val width = bubble.width - bubble.paddingLeft - bubble.paddingRight
    if (width <= 0 || bubble.height <= 0) return null
    val bitmap = createBitmap(width, bubble.height)
    val canvas = Canvas(bitmap)
    canvas.translate(-bubble.paddingLeft.toFloat(), 0f)
    bubble.draw(canvas)
    val location = bubble.getLocationInWindow()
    val left = location.x + bubble.paddingLeft
    return bitmap to Rect(left, location.y, left + width, location.y + bubble.height)
}

/**
 * Flies a news or digest card from the feed into a new discussion's post.
 *
 * As soon as the chat sliding in lays the post out, the card leaves the place it had on screen and flies onto the
 * post, turning into it on the way: it lifts toward the viewer with a shadow, leans into its flight in perspective, and
 * drops onto the post on a spring that carries it a little past and back. The flight is drawn over the window, over
 * both screens as one slides in over the other, but under the header they share, which it never covers. It follows
 * where the post shows on every frame, and turns into the post as drawn in the chat, so the post takes over without a
 * visible change. A post that never shows lets the card fade away where it is.
 */
internal class AgentNewsPostArrival(
    private val card: Bitmap,
    /** The card's body in the window */
    private val cardFrame: Rect,
    private val destination: () -> Destination?,
    /** In the window; null while the chat has no header */
    private val headerBottom: () -> Int?
) {
    /** The chat on screen; it gives none until its view is in the window, and none once it leaves */
    class Destination(
        val post: AgentNewsPostCell?,
        val followups: AgentHintsCell?,
        val composer: View
    )

    private enum class Phase { WAITING, HOLDING, FLYING, DISSOLVING, FINISHED }

    var onFinish: (() -> Unit)? = null

    private val flight = FlightDrawable()
    private var root: ViewGroup? = null
    private var phase = Phase.WAITING
    private var phaseStartedAt = 0L
    private var hasSeenDestination = false
    private var hiddenPost: View? = null
    private var hiddenFollowups: AgentHintsCell? = null

    // Where the post's body is, or last was, and where the card flies now, in the overlay's coordinates
    private val target = RectF()
    private var hasTarget = false
    private val flightFrame = RectF()
    private val sourceFrame = RectF()
    private var missingPostSince: Long? = null
    private val rootLocation = IntArray(2)
    private val postLocation = IntArray(2)
    private var flightTop = 0f
    private var flightBottom = Float.MAX_VALUE
    private var preDrawBinding: AgentPreDrawBinding? = null

    // Read after layout so the overlay and the post share a frame at handoff
    private val preDrawListener = ViewTreeObserver.OnPreDrawListener {
        if (phase != Phase.FINISHED) tick(System.nanoTime())
        true
    }
    private val rootAttachListener = object : View.OnAttachStateChangeListener {
        override fun onViewAttachedToWindow(v: View) = Unit

        override fun onViewDetachedFromWindow(v: View) = finish()
    }

    private val frameCallback = object : Choreographer.FrameCallback {
        override fun doFrame(frameTimeNanos: Long) {
            if (phase == Phase.FINISHED) return
            if (root?.windowVisibility != View.VISIBLE) {
                finish()
                return
            }
            root?.invalidate()
            Choreographer.getInstance().postFrameCallback(this)
        }
    }

    /** Holds the card over the window, where the feed showed it, until the chat sliding in lays the post out */
    fun start(root: ViewGroup) {
        if (phase != Phase.WAITING) return
        this.root = root
        phase = Phase.HOLDING
        phaseStartedAt = System.nanoTime()
        flight.setBounds(0, 0, root.width, root.height)
        flight.showCard(computeRootCardFrame())
        root.overlay.add(flight)
        preDrawBinding = AgentPreDrawBinding(root, preDrawListener)
        root.addOnAttachStateChangeListener(rootAttachListener)
        tick(phaseStartedAt)
        Choreographer.getInstance().postFrameCallback(frameCallback)
    }

    fun cancel() = finish()

    private fun tick(now: Long) {
        updateFlightTop()
        if (phase == Phase.DISSOLVING) {
            updateDissolve(now)
            return
        }
        val destination = destination()
        if (destination == null) {
            if (hasSeenDestination || toSeconds(now - phaseStartedAt) > HOLD_TIMEOUT) finish()
            return
        }
        hasSeenDestination = true
        updateFlightBottom(destination.composer)
        track(destination)
        when (phase) {
            // The card takes off as soon as the post is laid out, while the chat still slides in
            Phase.HOLDING -> {
                val post = destination.post?.postView
                if (post != null && post.isAttachedToWindow && post.isLaidOut && post.height > 0) {
                    phase = Phase.FLYING
                    phaseStartedAt = now
                    updateFlight(destination, now)
                } else if (toSeconds(now - phaseStartedAt) > HOLD_TIMEOUT) {
                    dissolve(now)
                } else {
                    flight.showCard(computeRootCardFrame())
                }
            }

            Phase.FLYING -> updateFlight(destination, now)

            else -> Unit
        }
    }

    private fun updateFlight(destination: Destination, now: Long) {
        val post = destination.post?.postView?.takeIf { it.isAttachedToWindow && it.height > 0 }
        if (post != null) {
            computeBodyFrame(post, target)
            hasTarget = true
            missingPostSince = null
        } else {
            // The post's row is being bound again: fly on to where the post was
            val since = missingPostSince ?: now
            missingPostSince = since
            if (!hasTarget || toSeconds(now - since) >= MISSING_POST_TOLERANCE) {
                finish()
                return
            }
        }
        val elapsed = toSeconds(now - phaseStartedAt)
        val progress = computeSpringProgress(elapsed)
        // Past the post the spring carries only the frame, a few percent, while the card is already down
        val time = (elapsed / LIFT_DURATION).coerceAtMost(1f)
        val height = sin(PI.toFloat() * time)
        val source = computeRootCardFrame()
        val width = interpolate(source.width(), target.width(), progress).coerceAtLeast(1f)
        val bodyHeight = interpolate(source.height(), target.height(), progress).coerceAtLeast(1f)
        val centerX = interpolate(source.centerX(), target.centerX(), progress)
        val centerY = interpolate(source.centerY(), target.centerY(), progress)
        val vertical = target.centerY() - source.centerY()
        val horizontal = target.centerX() - source.centerX()
        // Its leading edge dips away in the direction it flies
        val pitch = MAX_PITCH * height * (if (vertical < 0) 1f else -1f) *
            (abs(vertical) / PITCH_TRAVEL.dp).coerceAtMost(1f)
        val yaw = MAX_YAW * height * (horizontal / YAW_TRAVEL.dp).coerceIn(-1f, 1f)
        flightFrame.set(
            centerX - width / 2,
            centerY - bodyHeight / 2,
            centerX + width / 2,
            centerY + bodyHeight / 2
        )
        flight.showFlight(
            post,
            flightFrame,
            scale = 1 + LIFT * height,
            pitch = pitch,
            yaw = yaw,
            shadow = SHADOW_OPACITY * height,
            cardAlpha = 1 - smoothstep(0.3f, 0.7f, time),
            postAlpha = smoothstep(0.05f, 0.4f, time)
        )
        if (elapsed >= SPRING_REST_TIME && elapsed >= LIFT_DURATION && post != null) {
            land(destination)
        }
    }

    private fun land(destination: Destination) {
        stop()
        // Suggestions already under the post appear as they do under an answer once it has settled
        destination.followups?.reveal()
    }

    // Lets the card fade away where it is, for a post that never shows
    private fun dissolve(now: Long) {
        showHidden()
        phase = Phase.DISSOLVING
        phaseStartedAt = now
        updateDissolve(now)
    }

    private fun updateDissolve(now: Long) {
        val fraction = (toSeconds(now - phaseStartedAt) / DISSOLVE_DURATION).coerceAtMost(1f)
        val eased = fraction * fraction
        flight.showCard(computeRootCardFrame(), alpha = 1 - eased, scale = 1 - 0.08f * eased)
        if (fraction >= 1f) finish()
    }

    private fun finish() {
        stop()
    }

    private fun stop() {
        if (phase == Phase.FINISHED) return
        phase = Phase.FINISHED
        Choreographer.getInstance().removeFrameCallback(frameCallback)
        preDrawBinding?.release()
        preDrawBinding = null
        root?.removeOnAttachStateChangeListener(rootAttachListener)
        root?.overlay?.remove(flight)
        root = null
        showHidden()
        onFinish?.invoke()
        onFinish = null
    }

    // Hides whichever rows show the post and its suggestions now, and shows rows that no longer do
    private fun track(destination: Destination) {
        destination.post?.let { post ->
            if (post !== hiddenPost) {
                hiddenPost?.alpha = 1f
                post.alpha = 0f
                hiddenPost = post
            }
        }
        destination.followups?.let { followups ->
            if (followups !== hiddenFollowups) {
                hiddenFollowups?.alpha = 1f
                followups.alpha = 0f
                hiddenFollowups = followups
            }
        }
    }

    private fun showHidden() {
        hiddenPost?.alpha = 1f
        hiddenPost = null
        hiddenFollowups?.alpha = 1f
        hiddenFollowups = null
    }

    // The post's bubble without its tail, where the card's body lands, in the overlay's coordinates
    private fun computeBodyFrame(post: View, out: RectF) {
        post.getLocationInWindow(postLocation)
        root?.getLocationInWindow(rootLocation)
        val left = (postLocation[0] - rootLocation[0] + post.paddingLeft).toFloat()
        val top = (postLocation[1] - rootLocation[1]).toFloat()
        val width = post.width - post.paddingLeft - post.paddingRight
        out.set(left, top, left + width, top + post.height)
    }

    private fun updateFlightTop() {
        val bottom = headerBottom() ?: return
        root?.getLocationInWindow(rootLocation)
        val top = (bottom - rootLocation[1]).toFloat()
        if (top != flightTop) {
            flightTop = top
            flight.invalidateSelf()
        }
    }

    // Before layout the composer has no position, and a zero boundary would hide the flying card
    private fun updateFlightBottom(composer: View) {
        if (!composer.isAttachedToWindow || !composer.isLaidOut || composer.height <= 0) return
        composer.getLocationInWindow(postLocation)
        root?.getLocationInWindow(rootLocation)
        val bottom = (postLocation[1] - rootLocation[1]).toFloat()
        if (bottom > flightTop && bottom != flightBottom) {
            flightBottom = bottom
            flight.invalidateSelf()
        }
    }

    private fun computeRootCardFrame(): RectF {
        root?.getLocationInWindow(rootLocation)
        sourceFrame.set(cardFrame)
        sourceFrame.offset(-rootLocation[0].toFloat(), -rootLocation[1].toFloat())
        return sourceFrame
    }

    /** Draws the card, and the post it turns into, over everything in the window */
    private inner class FlightDrawable : Drawable() {
        private val bitmapPaint = Paint(Paint.ANTI_ALIAS_FLAG or Paint.FILTER_BITMAP_FLAG)
        private val shadowPaint = Paint(Paint.ANTI_ALIAS_FLAG)
        private val camera = Camera()
        private val matrix = Matrix()
        private val frame = RectF()
        private val cardSource = Rect(0, 0, card.width, card.height)
        private val cardDestination = RectF()
        private var post: View? = null
        private var isFlying = false
        private var scale = 1f
        private var pitch = 0f
        private var yaw = 0f
        private var shadow = 0f
        private var cardAlpha = 1f
        private var postAlpha = 0f

        init {
            // The perspective of a viewer as far away as on iOS
            camera.setLocation(0f, 0f, -PERSPECTIVE_DISTANCE.dp / CAMERA_UNITS_PER_INCH)
        }

        fun showCard(frame: RectF, alpha: Float = 1f, scale: Float = 1f) {
            isFlying = false
            post = null
            this.frame.set(frame)
            this.scale = scale
            cardAlpha = alpha
            invalidateSelf()
        }

        fun showFlight(
            post: View?,
            frame: RectF,
            scale: Float,
            pitch: Float,
            yaw: Float,
            shadow: Float,
            cardAlpha: Float,
            postAlpha: Float
        ) {
            isFlying = true
            if (post != null) this.post = post
            this.frame.set(frame)
            this.scale = scale
            this.pitch = pitch
            this.yaw = yaw
            this.shadow = shadow
            this.cardAlpha = cardAlpha
            this.postAlpha = postAlpha
            invalidateSelf()
        }

        override fun draw(canvas: Canvas) {
            val width = frame.width()
            val height = frame.height()
            canvas.save()
            canvas.clipRect(
                0f,
                flightTop,
                bounds.width().toFloat(),
                minOf(flightBottom, bounds.height().toFloat())
            )
            canvas.translate(frame.centerX(), frame.centerY())
            if (isFlying) {
                camera.save()
                camera.rotateX(pitch)
                camera.rotateY(yaw)
                camera.getMatrix(matrix)
                camera.restore()
                canvas.concat(matrix)
            }
            canvas.scale(scale, scale)
            canvas.translate(-width / 2, -height / 2)
            if (isFlying) {
                // The bubble's colour under both, lifted with a shadow
                shadowPaint.color = agentIncomingBubbleColor
                shadowPaint.setShadowLayer(
                    SHADOW_RADIUS.dp,
                    0f,
                    SHADOW_OFFSET.dp,
                    Color.argb((255 * shadow).roundToInt(), 0, 0, 0)
                )
                canvas.drawRoundRect(0f, 0f, width, height, CORNER.dp, CORNER.dp, shadowPaint)
            }
            if (cardAlpha > 0f) {
                bitmapPaint.alpha = (255 * cardAlpha).roundToInt()
                cardDestination.set(0f, 0f, width, height)
                canvas.drawBitmap(card, cardSource, cardDestination, bitmapPaint)
            }
            val post = post
            if (isFlying && post != null && postAlpha > 0f) {
                // The post's body covers the flying frame and its tail hangs off its side, as in the chat
                val bodyWidth = (post.width - post.paddingLeft - post.paddingRight).coerceAtLeast(1)
                canvas.scale(width / bodyWidth, height / post.height.coerceAtLeast(1))
                canvas.translate(-post.paddingLeft.toFloat(), 0f)
                // A layer only while the post fades in over the card
                val isFading = postAlpha < 1f
                if (isFading) {
                    canvas.saveLayerAlpha(
                        0f,
                        0f,
                        post.width.toFloat(),
                        post.height.toFloat(),
                        (255 * postAlpha).roundToInt()
                    )
                }
                post.draw(canvas)
                if (isFading) canvas.restore()
            }
            canvas.restore()
        }

        override fun setAlpha(alpha: Int) = Unit

        override fun setColorFilter(colorFilter: ColorFilter?) = Unit

        @Deprecated("Deprecated in Java")
        override fun getOpacity() = PixelFormat.TRANSLUCENT
    }

    private companion object {
        // The flight's spring: it reaches the post in about half a second, a few percent past it, and settles
        const val SPRING_DAMPING = 0.7f
        const val SPRING_RESPONSE = 0.55f
        val SPRING_OMEGA = 2 * PI.toFloat() / SPRING_RESPONSE
        val SPRING_REST_TIME = (ln(1000f) / (SPRING_DAMPING * SPRING_OMEGA))

        // In seconds: how long the card is in the air, and how long the chat may take to show the post
        const val LIFT_DURATION = 0.42f
        const val HOLD_TIMEOUT = 2f
        const val MISSING_POST_TOLERANCE = 0.5f
        const val DISSOLVE_DURATION = 0.25f

        // At the top of the flight the card is this much larger, leans this far and casts its shadow
        const val LIFT = 0.08f
        const val MAX_PITCH = 16f
        const val MAX_YAW = 8f
        const val PITCH_TRAVEL = 120
        const val YAW_TRAVEL = 160
        const val PERSPECTIVE_DISTANCE = 900
        const val CAMERA_UNITS_PER_INCH = 72f
        const val SHADOW_OPACITY = 0.22f
        const val SHADOW_RADIUS = 18f
        const val SHADOW_OFFSET = 10f
        const val CORNER = 20f

        fun toSeconds(nanos: Long) = nanos / 1_000_000_000f

        fun interpolate(from: Float, to: Float, progress: Float) = from + (to - from) * progress

        fun smoothstep(start: Float, end: Float, value: Float): Float {
            val fraction = ((value - start) / (end - start)).coerceIn(0f, 1f)
            return fraction * fraction * (3 - 2 * fraction)
        }

        fun computeSpringProgress(time: Float): Float {
            if (time <= 0f) return 0f
            val decay = exp(-SPRING_DAMPING * SPRING_OMEGA * time)
            val damped = SPRING_OMEGA * sqrt(1 - SPRING_DAMPING * SPRING_DAMPING)
            return 1 - decay * (
                cos(damped * time) + SPRING_DAMPING * SPRING_OMEGA / damped * sin(damped * time)
                )
        }
    }
}
