package org.mytonwallet.app_air.uicomponents.extensions

import android.annotation.SuppressLint
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.ColorSpace
import android.graphics.HardwareRenderer
import android.graphics.PixelFormat
import android.graphics.RenderNode
import android.graphics.SurfaceTexture
import android.hardware.HardwareBuffer
import android.media.ImageReader
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.view.MotionEvent
import android.view.PixelCopy
import android.view.Surface
import android.view.View
import android.view.ViewGroup
import android.widget.FrameLayout
import androidx.annotation.RequiresApi
import kotlin.math.roundToInt
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.utils.Vec2i
import org.mytonwallet.app_air.walletbasecontext.utils.vec2i

@SuppressLint("ClickableViewAccessibility")
fun View.setOnLongHoldListener(delayMs: Long, action: () -> Unit) {
    var runnable: Runnable? = null
    setOnTouchListener { v, event ->
        when (event.action) {
            MotionEvent.ACTION_DOWN -> {
                runnable?.let { v.removeCallbacks(it) }
                runnable =
                    Runnable {
                        runnable = null
                        action()
                    }.also { v.postDelayed(it, delayMs) }
            }

            MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> {
                runnable?.let { v.removeCallbacks(it) }
                runnable = null
            }
        }
        false
    }
}

fun View.setOnClickListener(listener: (() -> Unit)?) {
    listener?.let { l ->
        this.setOnClickListener { l.invoke() }
    } ?: run {
        this.setOnClickListener(null)
    }
}

fun View.disableInteraction() {
    isEnabled = false
    isClickable = false
}

fun View.setPaddingDp(left: Float, top: Float, right: Float, bottom: Float) {
    this.setPadding(
        left.dp.roundToInt(),
        top.dp.roundToInt(),
        right.dp.roundToInt(),
        bottom.dp.roundToInt()
    )
}

fun View.setPaddingDp(left: Int, top: Int, right: Int, bottom: Int) {
    this.setPadding(
        left.dp,
        top.dp,
        right.dp,
        bottom.dp
    )
}

fun View.setPaddingDp(size: Int) {
    setPaddingDp(size, size, size, size)
}

fun View.setPaddingDp(size: Float) {
    setPaddingDp(size, size, size, size)
}

fun View.setPaddingLocalized(start: Int, top: Int, end: Int, bottom: Int) {
    setPadding(
        if (LocaleController.isRTL) end else start,
        top,
        if (LocaleController.isRTL) start else end,
        bottom
    )
}

fun View.setPaddingDpLocalized(start: Int, top: Int, end: Int, bottom: Int) {
    setPaddingLocalized(
        start.dp,
        top.dp,
        end.dp,
        bottom.dp
    )
}

fun ViewGroup.suppressLayoutCompat(suppress: Boolean) {
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
        suppressLayout(suppress)
    }
}

fun FrameLayout.LayoutParams.setMarginsDp(left: Float, top: Float, right: Float, bottom: Float) {
    this.setMargins(
        left.dp.roundToInt(),
        top.dp.roundToInt(),
        right.dp.roundToInt(),
        bottom.dp.roundToInt()
    )
}

fun FrameLayout.LayoutParams.setMarginsDp(left: Int, top: Int, right: Int, bottom: Int) {
    this.setMargins(
        left.dp,
        top.dp,
        right.dp,
        bottom.dp
    )
}

fun FrameLayout.LayoutParams.setMarginsDp(size: Int) {
    setMarginsDp(size, size, size, size)
}

fun FrameLayout.LayoutParams.setPaddingDp(size: Float) {
    setMarginsDp(size, size, size, size)
}

fun View.asImage(): Bitmap? {
    if (width == 0 || height == 0) return null
    val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
    val canvas = Canvas(bitmap)
    draw(canvas)
    return bitmap
}

// Captures GPU-rendered content such as WebViews.
fun View.captureHardwareImage(onResult: (Bitmap?) -> Unit) {
    if (width == 0 || height == 0) {
        onResult(null)
        return
    }
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
        onResult(asImage())
        return
    }
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
        captureHardwareBuffer(onResult)
        return
    }
    val surfaceTexture = SurfaceTexture(false)
    surfaceTexture.setDefaultBufferSize(width, height)
    val surface = Surface(surfaceTexture)
    val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
    try {
        val canvas = surface.lockHardwareCanvas()
        draw(canvas)
        surface.unlockCanvasAndPost(canvas)
    } catch (_: Exception) {
        surface.release()
        surfaceTexture.release()
        bitmap.recycle()
        onResult(null)
        return
    }
    PixelCopy.request(
        surface,
        bitmap,
        { result ->
            surface.release()
            surfaceTexture.release()
            if (result == PixelCopy.SUCCESS) {
                onResult(bitmap)
            } else {
                bitmap.recycle()
                onResult(null)
            }
        },
        Handler(Looper.getMainLooper())
    )
}

private const val NO_FRAME_SYNC_RESULTS =
    HardwareRenderer.SYNC_LOST_SURFACE_REWARD_IF_FOUND or
        HardwareRenderer.SYNC_CONTEXT_IS_STOPPED or
        HardwareRenderer.SYNC_FRAME_DROPPED

// Zero-copy GPU capture.
@RequiresApi(Build.VERSION_CODES.Q)
private fun View.captureHardwareBuffer(onResult: (Bitmap?) -> Unit) {
    val reader = ImageReader.newInstance(
        width,
        height,
        PixelFormat.RGBA_8888,
        1,
        HardwareBuffer.USAGE_GPU_SAMPLED_IMAGE or HardwareBuffer.USAGE_GPU_COLOR_OUTPUT
    )
    val node = RenderNode("capture")
    val renderer = HardwareRenderer()
    fun release() {
        renderer.destroy()
        node.discardDisplayList()
        reader.close()
    }
    try {
        node.setPosition(0, 0, width, height)
        draw(node.beginRecording())
        node.endRecording()
        renderer.isOpaque = false
        renderer.setSurface(reader.surface)
        renderer.setContentRoot(node)
        reader.setOnImageAvailableListener({
            val bitmap = try {
                it.acquireLatestImage()?.use { image ->
                    image.hardwareBuffer?.use { buffer ->
                        Bitmap.wrapHardwareBuffer(buffer, ColorSpace.get(ColorSpace.Named.SRGB))
                    }
                }
            } catch (_: Exception) {
                null
            }
            release()
            onResult(bitmap)
        }, Handler(Looper.getMainLooper()))
        val result = renderer.createRenderRequest().syncAndDraw()
        if (result and NO_FRAME_SYNC_RESULTS != 0) {
            release()
            onResult(null)
        }
    } catch (_: Exception) {
        release()
        onResult(null)
    }
}

fun View.getLocationOnScreen(out: Vec2i = vec2i()): Vec2i {
    getLocationOnScreen(out)
    return out
}

fun View.getLocationInWindow(out: Vec2i = vec2i()): Vec2i {
    getLocationInWindow(out)
    return out
}

inline val Int.exactly: Int
    get() = View.MeasureSpec.makeMeasureSpec(this, View.MeasureSpec.EXACTLY)

inline val Int.atMost: Int
    get() = View.MeasureSpec.makeMeasureSpec(this, View.MeasureSpec.AT_MOST)

inline val Int.unspecified: Int
    get() = View.MeasureSpec.makeMeasureSpec(this, View.MeasureSpec.UNSPECIFIED)
