package org.mytonwallet.app_air.uicomponents.diamond

import android.animation.ValueAnimator
import android.annotation.SuppressLint
import android.content.Context
import android.graphics.SurfaceTexture
import android.graphics.drawable.Drawable
import android.os.Build
import android.os.PowerManager
import android.view.MotionEvent
import android.view.TextureView
import android.view.View
import android.view.ViewConfiguration
import android.widget.ImageView
import kotlin.math.hypot
import kotlin.math.min
import org.mytonwallet.app_air.uicomponents.widgets.WView
import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage

@SuppressLint("ViewConstructor", "ClickableViewAccessibility")
class WBlueDiamondView(context: Context) : WView(context) {
    private var renderer: BlueDiamondRenderer? = null
    private var hasFailed = false
    private val preview = ImageView(context).apply {
        id = generateViewId()
        context.assets.open("blue_diamond/preview.webp").use {
            setImageDrawable(Drawable.createFromStream(it, null))
        }
        scaleType = ImageView.ScaleType.FIT_CENTER
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
                val current = BlueDiamondRenderer(context.assets, surface, min(width, height)) {
                    post {
                        if (surfaceTexture !== surface) return@post
                        hasFailed = true
                        alpha = 0f
                        preview.alpha = 1f
                    }
                }
                renderer = current
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
                val current = renderer
                renderer = null
                current?.stop()
                return current == null
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

    init {
        importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_NO_HIDE_DESCENDANTS
        addView(preview, LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.MATCH_PARENT))
        addView(textureView, LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.MATCH_PARENT))
        setConstraints {
            allEdges(preview)
            allEdges(textureView)
        }
    }

    fun updatePlayback() {
        renderer?.setPlayback(
            isAttachedToWindow && isShown && hasWindowFocus(),
            areAnimationsAllowed()
        )
    }

    private fun areAnimationsAllowed(): Boolean = WGlobalStorage.getAreAnimationsActive() &&
        (Build.VERSION.SDK_INT < Build.VERSION_CODES.O || ValueAnimator.areAnimatorsEnabled()) &&
        (context.getSystemService(Context.POWER_SERVICE) as? PowerManager)?.isPowerSaveMode !=
        true

    override fun onAttachedToWindow() {
        super.onAttachedToWindow()
        updatePlayback()
    }

    override fun onDetachedFromWindow() {
        cancelTouch()
        renderer?.setPlayback(false, false)
        super.onDetachedFromWindow()
    }

    override fun onVisibilityChanged(changedView: View, visibility: Int) {
        super.onVisibilityChanged(changedView, visibility)
        updatePlayback()
    }

    override fun onWindowFocusChanged(hasWindowFocus: Boolean) {
        super.onWindowFocusChanged(hasWindowFocus)
        if (!hasWindowFocus) cancelTouch()
        updatePlayback()
    }

    override fun onTouchEvent(event: MotionEvent): Boolean {
        if (event.actionMasked == MotionEvent.ACTION_DOWN &&
            (renderer == null || hasFailed || !areAnimationsAllowed())
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
                startX = event.x
                startY = event.y
                lastX = startX
                lastY = startY
                isDragging = false
                parent?.requestDisallowInterceptTouchEvent(true)
                renderer?.press()
            }

            MotionEvent.ACTION_MOVE -> {
                val index = event.findPointerIndex(pointerId)
                if (index < 0) {
                    cancelTouch()
                    return true
                }
                val x = event.getX(index)
                val y = event.getY(index)
                if (!isDragging && hypot(x - startX, y - startY) > touchSlop) isDragging = true
                if (isDragging) {
                    renderer?.drag(x - lastX, y - lastY)
                    lastX = x
                    lastY = y
                }
            }

            MotionEvent.ACTION_UP -> {
                if (pointerId != MotionEvent.INVALID_POINTER_ID) {
                    if (isDragging) {
                        renderer?.release()
                    } else {
                        val halfSize = width / 2f
                        renderer?.release(
                            (halfSize - event.x) / halfSize,
                            (halfSize - event.y) / halfSize
                        )
                    }
                    pointerId = MotionEvent.INVALID_POINTER_ID
                    parent?.requestDisallowInterceptTouchEvent(false)
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
        renderer?.release()
        parent?.requestDisallowInterceptTouchEvent(false)
    }
}
