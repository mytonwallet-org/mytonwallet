package org.mytonwallet.app_air.uicomponents.diamond

import android.animation.ValueAnimator
import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.ColorMatrix
import android.graphics.ColorMatrixColorFilter
import android.graphics.Paint
import android.graphics.RectF
import android.graphics.SurfaceTexture
import android.graphics.drawable.Drawable
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.view.MotionEvent
import android.view.TextureView
import android.view.VelocityTracker
import android.view.View
import android.view.ViewConfiguration
import android.widget.ImageView
import kotlin.math.abs
import kotlin.math.hypot
import kotlin.math.min
import kotlin.math.sign
import org.mytonwallet.app_air.uicomponents.helpers.HapticType
import org.mytonwallet.app_air.uicomponents.helpers.Haptics
import org.mytonwallet.app_air.uicomponents.widgets.WView
import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage

@SuppressLint("ViewConstructor", "ClickableViewAccessibility")
class WBlueDiamondView(
    context: Context,
    private val maxGrow: Float = 1f,
    private val hoverSpeed: Float = 1f,
    private val shouldRotateOnTap: Boolean = false,
    private val restingCanvasSize: Int? = null
) : WView(context) {
    var onParticleInteraction: ((pressed: Boolean, hovered: Boolean) -> Unit)? = null
    private var particlePointerId = MotionEvent.INVALID_POINTER_ID
    private var renderer: BlueDiamondRenderer? = null
    private val motionState = BlueDiamondRenderer.State()
    private val pixelsPerPoint = resources.displayMetrics.density
    private var lensMask: Bitmap? = null
    private val lensRect = RectF()
    private var hasFailed = false
    private var retainedSurface: SurfaceTexture? = null
    private val mainHandler = Handler(Looper.getMainLooper())
    private val releaseRetainedSurface = Runnable {
        retainedSurface = null
        renderer?.stop()
        renderer = null
    }
    private val preview = ImageView(context).apply {
        id = generateViewId()
        context.assets.open("blue_diamond/preview.webp").use {
            setImageDrawable(Drawable.createFromStream(it, null))
        }
        scaleType = ImageView.ScaleType.FIT_CENTER
        scaleX = if (restingCanvasSize != null) 1f else 1 / maxGrow
        scaleY = scaleX
    }
    private val textureView = TextureView(context).apply {
        id = generateViewId()
        isOpaque = false
        alpha = 0f
        surfaceTextureListener = object : TextureView.SurfaceTextureListener {
            override fun onSurfaceTextureAvailable(
                surface: SurfaceTexture,
                width: Int,
                height: Int
            ) {
                hasFailed = false
                alpha = 0f
                preview.alpha = 1f
                val current =
                    BlueDiamondRenderer(
                        context.assets,
                        surface,
                        min(width, height),
                        maxGrow,
                        pixelsPerPoint,
                        hoverSpeed,
                        restingCanvasSize,
                        motionState
                    ) {
                        post {
                            if (surfaceTexture !== surface) return@post
                            hasFailed = true
                            alpha = 0f
                            preview.alpha = 1f
                        }
                    }
                renderer = current
                current.setLensSource(lensMask, lensRect)
                updatePlayback()
            }

            override fun onSurfaceTextureSizeChanged(
                surface: SurfaceTexture,
                width: Int,
                height: Int
            ) {
                renderer?.resize(min(width, height))
            }

            override fun onSurfaceTextureDestroyed(surface: SurfaceTexture): Boolean {
                if (renderer == null) return true
                // Capture before TextureView clears its surface.
                // Returning then shows the same size and angle.
                if (alpha > 0f) {
                    bitmap?.let {
                        preview.setImageBitmap(it)
                        preview.scaleX = 1f
                        preview.scaleY = 1f
                    }
                }
                // Kept for a re-attach in the same main-loop turn; released otherwise.
                retainedSurface = surface
                return false
            }

            override fun onSurfaceTextureUpdated(surface: SurfaceTexture) {
                if (!hasFailed) {
                    alpha = 1f
                    preview.alpha = 0f
                }
            }
        }
    }
    private var pointerId = MotionEvent.INVALID_POINTER_ID
    private var startX = 0f
    private var startY = 0f
    private var lastX = 0f
    private var lastY = 0f
    private var isDragging = false
    private val touchSlop = ViewConfiguration.get(context).scaledTouchSlop
    private var velocityTracker: VelocityTracker? = null
    private val landingFeedback = Runnable {
        if (pointerId == MotionEvent.INVALID_POINTER_ID && isAttachedToWindow &&
            isRenderingEnabled
        ) {
            Haptics.play(this, HapticType.LIGHT_TAP)
        }
    }

    init {
        importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_NO_HIDE_DESCENDANTS
        addView(preview, LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.MATCH_PARENT))
        addView(textureView, LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.MATCH_PARENT))
        setConstraints {
            allEdges(preview)
            allEdges(textureView)
        }
    }

    /** Refracts [image] while the stone is held; [frame] is in pixels relative to this view's center. */
    fun setRefractionSource(image: Bitmap?, frame: RectF) {
        lensMask = image?.let { source ->
            Bitmap.createBitmap(source.width, source.height, Bitmap.Config.ARGB_8888).also {
                // Opaque dark modules become an opaque black mask; light and transparent pixels vanish.
                val paint = Paint().apply {
                    colorFilter = ColorMatrixColorFilter(
                        ColorMatrix(
                            floatArrayOf(
                                0f, 0f, 0f, 0f, 0f,
                                0f, 0f, 0f, 0f, 0f,
                                0f, 0f, 0f, 0f, 0f,
                                -1f, 0f, 0f, 1f, 0f
                            )
                        )
                    )
                }
                Canvas(it).drawBitmap(source, 0f, 0f, paint)
            }
        }
        lensRect.set(
            frame.left / pixelsPerPoint,
            frame.top / pixelsPerPoint,
            frame.right / pixelsPerPoint,
            frame.bottom / pixelsPerPoint
        )
        renderer?.setLensSource(lensMask, lensRect)
    }

    var isRenderingEnabled = true
        set(value) {
            if (field == value) return
            field = value
            if (!value) {
                cancelTouch()
                resetParticleInteraction()
            }
            updatePlayback()
        }

    fun updatePlayback() {
        renderer?.setPlayback(
            isRenderingEnabled && isAttachedToWindow && isShown && hasWindowFocus(),
            areAnimationsAllowed()
        )
    }

    private fun areAnimationsAllowed(): Boolean = WGlobalStorage.getAreAnimationsActive() &&
        (Build.VERSION.SDK_INT < Build.VERSION_CODES.O || ValueAnimator.areAnimatorsEnabled()) &&
        (context.getSystemService(Context.POWER_SERVICE) as? PowerManager)?.isPowerSaveMode !=
        true

    override fun onAttachedToWindow() {
        super.onAttachedToWindow()
        mainHandler.removeCallbacks(releaseRetainedSurface)
        retainedSurface?.let {
            retainedSurface = null
            textureView.setSurfaceTexture(it)
        }
        updatePlayback()
    }

    override fun onDetachedFromWindow() {
        resetParticleInteraction()
        cancelTouch()
        removeCallbacks(landingFeedback)
        renderer?.setPlayback(false, false)
        if (retainedSurface != null) mainHandler.post(releaseRetainedSurface)
        super.onDetachedFromWindow()
    }

    override fun onVisibilityChanged(changedView: View, visibility: Int) {
        super.onVisibilityChanged(changedView, visibility)
        if (visibility != VISIBLE) resetParticleInteraction()
        updatePlayback()
    }

    override fun onWindowFocusChanged(hasWindowFocus: Boolean) {
        super.onWindowFocusChanged(hasWindowFocus)
        if (!hasWindowFocus) {
            cancelTouch()
            resetParticleInteraction()
        }
        updatePlayback()
    }

    override fun dispatchTouchEvent(event: MotionEvent): Boolean {
        when (event.actionMasked) {
            MotionEvent.ACTION_DOWN -> particlePointerId = event.getPointerId(0)

            MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL ->
                particlePointerId =
                    MotionEvent.INVALID_POINTER_ID

            MotionEvent.ACTION_POINTER_UP -> if (event.getPointerId(event.actionIndex) ==
                particlePointerId
            ) {
                particlePointerId = MotionEvent.INVALID_POINTER_ID
            }
        }
        onParticleInteraction?.invoke(
            particlePointerId != MotionEvent.INVALID_POINTER_ID,
            isHovered
        )
        return super.dispatchTouchEvent(event) || onParticleInteraction != null
    }

    private fun resetParticleInteraction() {
        particlePointerId = MotionEvent.INVALID_POINTER_ID
        renderer?.setHovered(false)
        onParticleInteraction?.invoke(false, false)
    }

    override fun onTouchEvent(event: MotionEvent): Boolean {
        val restingHalfSize = (restingCanvasSize?.toFloat() ?: (width / maxGrow)) / 2
        if (event.actionMasked == MotionEvent.ACTION_DOWN &&
            (
                renderer == null || hasFailed || !isRenderingEnabled || !areAnimationsAllowed() ||
                    abs(event.x - width / 2f) > restingHalfSize ||
                    abs(event.y - height / 2f) > restingHalfSize
                )
        ) {
            return false
        }
        if (event.actionMasked != MotionEvent.ACTION_DOWN &&
            pointerId == MotionEvent.INVALID_POINTER_ID
        ) {
            return false
        }
        when (event.actionMasked) {
            MotionEvent.ACTION_DOWN -> {
                pointerId = event.getPointerId(0)
                startX = event.x + left
                startY = event.y + top
                lastX = startX
                lastY = startY
                isDragging = false
                removeCallbacks(landingFeedback)
                velocityTracker = VelocityTracker.obtain()
                trackMovement(event)
                parent?.requestDisallowInterceptTouchEvent(true)
                renderer?.press(shouldRotateOnTap)
                if (shouldRotateOnTap) Haptics.play(this, HapticType.LIGHT_TAP)
            }

            MotionEvent.ACTION_MOVE -> {
                val index = event.findPointerIndex(pointerId)
                if (index < 0) {
                    cancelTouch()
                    return true
                }
                trackMovement(event)
                val x = event.getX(index) + left
                val y = event.getY(index) + top
                if (!isDragging && hypot(x - startX, y - startY) > touchSlop) isDragging = true
                if (isDragging || shouldRotateOnTap) {
                    renderer?.drag(x - lastX, y - lastY)
                    lastX = x
                    lastY = y
                }
            }

            MotionEvent.ACTION_UP -> {
                if (pointerId != MotionEvent.INVALID_POINTER_ID) {
                    if (hypot(event.x + left - startX, event.y + top - startY) >
                        touchSlop
                    ) {
                        isDragging = true
                    }
                    if (shouldRotateOnTap && !isDragging) {
                        renderer?.release(
                            fullTurn =
                                event.eventTime - event.downTime <= MAX_TAP_DURATION_MS
                        )
                    } else if (isDragging) {
                        trackMovement(event)
                        val velocity = velocityTracker?.let {
                            it.computeCurrentVelocity(1000)
                            it.getXVelocity(pointerId) / pixelsPerPoint
                        } ?: 0f
                        renderer?.release(
                            flingDirection = if (abs(velocity) >
                                FLING_VELOCITY
                            ) {
                                sign(velocity)
                            } else {
                                null
                            }
                        )
                    } else {
                        renderer?.release(
                            (width / 2f - event.x) / restingHalfSize,
                            (height / 2f - event.y) / restingHalfSize
                        )
                    }
                    val power = renderer?.grip ?: 0f
                    pointerId = MotionEvent.INVALID_POINTER_ID
                    recycleVelocityTracker()
                    parent?.requestDisallowInterceptTouchEvent(false)
                    if (!shouldRotateOnTap && maxGrow > 1 &&
                        power > 0.2f
                    ) {
                        postDelayed(landingFeedback, 200)
                    }
                }
            }

            MotionEvent.ACTION_CANCEL -> cancelTouch()

            MotionEvent.ACTION_POINTER_UP -> if (event.getPointerId(event.actionIndex) ==
                pointerId
            ) {
                cancelTouch()
            }
        }
        return true
    }

    private fun cancelTouch() {
        if (pointerId == MotionEvent.INVALID_POINTER_ID) return
        pointerId = MotionEvent.INVALID_POINTER_ID
        recycleVelocityTracker()
        renderer?.release()
        parent?.requestDisallowInterceptTouchEvent(false)
    }

    private fun trackMovement(event: MotionEvent) {
        val sample = MotionEvent.obtain(event)
        sample.offsetLocation(left.toFloat(), top.toFloat())
        velocityTracker?.addMovement(sample)
        sample.recycle()
    }

    override fun onHoverEvent(event: MotionEvent): Boolean {
        val hovered = event.action != MotionEvent.ACTION_HOVER_EXIT
        isHovered = hovered
        renderer?.setHovered(hovered)
        onParticleInteraction?.invoke(particlePointerId != MotionEvent.INVALID_POINTER_ID, hovered)
        return super.onHoverEvent(event) || onParticleInteraction != null
    }

    private fun recycleVelocityTracker() {
        velocityTracker?.recycle()
        velocityTracker = null
    }

    private companion object {
        const val FLING_VELOCITY = 600f
        const val MAX_TAP_DURATION_MS = 250L
    }
}
