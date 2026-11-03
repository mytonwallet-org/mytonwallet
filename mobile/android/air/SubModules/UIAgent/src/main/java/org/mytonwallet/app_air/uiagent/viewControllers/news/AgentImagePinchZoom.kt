package org.mytonwallet.app_air.uiagent.viewControllers.news

import android.animation.Animator
import android.animation.AnimatorListenerAdapter
import android.animation.ValueAnimator
import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Outline
import android.view.MotionEvent
import android.view.View
import android.view.ViewGroup
import android.view.ViewOutlineProvider
import androidx.recyclerview.widget.RecyclerView
import kotlin.math.hypot
import kotlin.math.min
import org.mytonwallet.app_air.uicomponents.helpers.CubicBezierInterpolator
import org.mytonwallet.app_air.uicomponents.image.WCustomImageView
import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage

/** Telegram-style pinch: a copy lifts over the window, zooms up to 10× and springs back once a finger lifts. */
internal class AgentImagePinchZoom(
    private val image: WCustomImageView,
    private val topCornerRadius: Float = 0f
) {
    private var isClaimed = false
    private var firstPointerId = MotionEvent.INVALID_POINTER_ID
    private var secondPointerId = MotionEvent.INVALID_POINTER_ID
    private var startDistance = 0f
    private var startCenterX = 0f
    private var startCenterY = 0f
    private var lift: Lift? = null
    private val hostLocation = IntArray(2)
    private val originLocation = IntArray(2)
    private val imageLocation = IntArray(2)

    /** Returns whether the pinch took [event]; [cancelChildren] then makes the host's views let go. */
    fun onTouchEvent(
        host: View,
        event: MotionEvent,
        cancelChildren: (MotionEvent) -> Unit
    ): Boolean {
        when (event.actionMasked) {
            MotionEvent.ACTION_DOWN -> if (isClaimed) {
                isClaimed = false
                stopTracking()
            }

            MotionEvent.ACTION_POINTER_DOWN -> {
                if (event.pointerCount != 2 || firstPointerId != MotionEvent.INVALID_POINTER_ID) {
                    return isClaimed
                }
                if (!isClaimed) {
                    if (!canStart(host, event)) return false
                    isClaimed = true
                    host.parent?.requestDisallowInterceptTouchEvent(true)
                    stopEnclosingScroll(host)
                    val cancel = MotionEvent.obtain(event).apply {
                        action = MotionEvent.ACTION_CANCEL
                    }
                    cancelChildren(cancel)
                    cancel.recycle()
                }
                if (lift == null) startTracking(host, event)
            }

            MotionEvent.ACTION_MOVE -> if (isClaimed) track(host, event)

            MotionEvent.ACTION_POINTER_UP -> if (isClaimed) {
                val pointerId = event.getPointerId(event.actionIndex)
                if (pointerId == firstPointerId || pointerId == secondPointerId) stopTracking()
            }

            MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> if (isClaimed) {
                stopTracking()
                isClaimed = false
                host.parent?.requestDisallowInterceptTouchEvent(false)
                return true
            }
        }
        return isClaimed
    }

    fun cancel() {
        isClaimed = false
        firstPointerId = MotionEvent.INVALID_POINTER_ID
        secondPointerId = MotionEvent.INVALID_POINTER_ID
        lift?.remove()
        lift = null
    }

    fun canStart(origin: View, event: MotionEvent): Boolean {
        if (lift != null || !image.isImageShown || !image.isShown) return false
        if (image.width == 0 || image.height == 0) return false
        origin.getLocationInWindow(originLocation)
        image.getLocationInWindow(imageLocation)
        val left = imageLocation[0] - originLocation[0]
        val top = imageLocation[1] - originLocation[1]
        return (0 until event.pointerCount).all { index ->
            val x = event.getX(index)
            val y = event.getY(index)
            x >= left && x < left + image.width && y >= top && y < top + image.height
        }
    }

    private fun startTracking(host: View, event: MotionEvent) {
        firstPointerId = event.getPointerId(0)
        secondPointerId = event.getPointerId(1)
        host.getLocationInWindow(hostLocation)
        rebase(event, 0, 1)
    }

    // In window coordinates, as the lifted copy is
    private fun rebase(event: MotionEvent, firstIndex: Int, secondIndex: Int) {
        startDistance = distance(event, firstIndex, secondIndex)
        startCenterX = hostLocation[0] + (event.getX(firstIndex) + event.getX(secondIndex)) / 2f
        startCenterY = hostLocation[1] + (event.getY(firstIndex) + event.getY(secondIndex)) / 2f
    }

    private fun track(host: View, event: MotionEvent) {
        if (firstPointerId == MotionEvent.INVALID_POINTER_ID) return
        val firstIndex = event.findPointerIndex(firstPointerId)
        val secondIndex = event.findPointerIndex(secondPointerId)
        if (firstIndex < 0 || secondIndex < 0) {
            stopTracking()
            return
        }
        host.getLocationInWindow(hostLocation)
        val currentLift = lift
        if (currentLift == null) {
            if (startDistance <= 0f ||
                distance(event, firstIndex, secondIndex) / startDistance <= START_SCALE
            ) {
                return
            }
            rebase(event, firstIndex, secondIndex)
            lift = Lift.start(image, topCornerRadius, startCenterX, startCenterY)
            return
        }
        val centerX = hostLocation[0] + (event.getX(firstIndex) + event.getX(secondIndex)) / 2f
        val centerY = hostLocation[1] + (event.getY(firstIndex) + event.getY(secondIndex)) / 2f
        val zoom = (distance(event, firstIndex, secondIndex) / startDistance)
            .coerceIn(1f, MAX_SCALE)
        currentLift.update(zoom, centerX - startCenterX, centerY - startCenterY)
    }

    private fun stopTracking() {
        firstPointerId = MotionEvent.INVALID_POINTER_ID
        secondPointerId = MotionEvent.INVALID_POINTER_ID
        val currentLift = lift ?: return
        currentLift.release { if (lift === currentLift) lift = null }
    }

    private fun stopEnclosingScroll(host: View) {
        var parent = host.parent
        while (parent is View) {
            if (parent is RecyclerView) parent.stopScroll()
            parent = parent.parent
        }
    }

    private fun distance(event: MotionEvent, firstIndex: Int, secondIndex: Int): Float = hypot(
        event.getX(secondIndex) - event.getX(firstIndex),
        event.getY(secondIndex) - event.getY(firstIndex)
    )

    private class Lift(
        private val root: ViewGroup,
        private val image: WCustomImageView,
        private val topCornerRadius: Float,
        private val anchorX: Float,
        private val anchorY: Float
    ) {
        private val dim = View(root.context).apply { setBackgroundColor(Color.BLACK) }
        private val copy = ImageCopy(root.context, image)
        private val location = IntArray(2)
        private var zoom = 1f
        private var translationX = 0f
        private var translationY = 0f
        private var releaseAnimator: ValueAnimator? = null

        fun update(zoom: Float, translationX: Float, translationY: Float) {
            this.zoom = zoom
            this.translationX = translationX
            this.translationY = translationY
            render()
        }

        fun release(onEnd: () -> Unit) {
            if (releaseAnimator != null) return
            if (!WGlobalStorage.getAreAnimationsActive()) {
                remove()
                onEnd()
                return
            }
            val fromZoom = zoom
            val fromX = translationX
            val fromY = translationY
            releaseAnimator = ValueAnimator.ofFloat(1f, 0f).apply {
                duration = RELEASE_DURATION_MS
                interpolator = CubicBezierInterpolator.DEFAULT
                addUpdateListener {
                    val fraction = it.animatedValue as Float
                    update(1f + (fromZoom - 1f) * fraction, fromX * fraction, fromY * fraction)
                }
                addListener(object : AnimatorListenerAdapter() {
                    override fun onAnimationEnd(animation: Animator) {
                        remove()
                        onEnd()
                    }
                })
                start()
            }
        }

        fun remove() {
            releaseAnimator?.let {
                releaseAnimator = null
                it.removeAllListeners()
                it.cancel()
            }
            root.overlay.remove(dim)
            root.overlay.remove(copy)
            image.alpha = 1f
        }

        private fun attach() {
            dim.layout(0, 0, root.width, root.height)
            dim.alpha = 0f
            root.overlay.add(dim)
            root.overlay.add(copy)
            image.alpha = 0f
            render()
        }

        private fun render() {
            image.getLocationInWindow(location)
            val left = location[0]
            val top = location[1]
            if (copy.left != left || copy.top != top ||
                copy.width != image.width || copy.height != image.height
            ) {
                copy.layout(left, top, left + image.width, top + image.height)
            }
            copy.pivotX = anchorX - left
            copy.pivotY = anchorY - top
            copy.scaleX = zoom
            copy.scaleY = zoom
            copy.translationX = translationX
            copy.translationY = translationY
            val progress = min(1f, zoom - 1f)
            copy.cornerRadius = topCornerRadius * (1f - progress)
            dim.alpha = DIM_ALPHA * progress
        }

        companion object {
            fun start(
                image: WCustomImageView,
                topCornerRadius: Float,
                anchorX: Float,
                anchorY: Float
            ): Lift? {
                val root = image.rootView as? ViewGroup ?: return null
                return Lift(root, image, topCornerRadius, anchorX, anchorY).also { it.attach() }
            }
        }
    }

    @SuppressLint("ViewConstructor")
    private class ImageCopy(context: Context, private val image: View) : View(context) {
        var cornerRadius = 0f
            set(value) {
                if (field == value) return
                field = value
                invalidateOutline()
            }

        init {
            outlineProvider = object : ViewOutlineProvider() {
                override fun getOutline(view: View, outline: Outline) {
                    if (cornerRadius <= 0f) {
                        outline.setRect(0, 0, view.width, view.height)
                    } else {
                        // Square at the bottom: the rounded rect reaches past it
                        outline.setRoundRect(
                            0,
                            0,
                            view.width,
                            view.height + cornerRadius.toInt(),
                            cornerRadius
                        )
                    }
                }
            }
            clipToOutline = true
        }

        override fun onDraw(canvas: Canvas) {
            image.draw(canvas)
        }
    }

    private companion object {
        const val MAX_SCALE = 10f
        const val START_SCALE = 1.005f
        const val DIM_ALPHA = 0.5f
        const val RELEASE_DURATION_MS = 220L
    }
}
