package org.mytonwallet.app_air.uicomponents.commonViews

import android.graphics.Bitmap
import android.graphics.BitmapShader
import android.graphics.ColorSpace
import android.graphics.HardwareRenderer
import android.graphics.Matrix
import android.graphics.Paint
import android.graphics.RenderNode
import android.graphics.RuntimeShader
import android.graphics.Shader
import android.hardware.DataSpace
import android.hardware.HardwareBuffer
import android.media.Image
import android.media.ImageReader
import android.os.Handler
import android.os.Looper
import kotlin.math.roundToInt

/** A GPU-only background texture. Star-only changes do not submit another background pass. */
@androidx.annotation.RequiresApi(33)
internal class CardSurfaceBackdropCache(
    private val createShader: () -> RuntimeShader,
    private val applyFrame: (RuntimeShader, CardSurfaceFrame) -> Unit,
    private val onReady: () -> Unit
) {
    private class Entry(
        val key: CardSurfaceFrame.BackgroundKey,
        val shader: BitmapShader,
        val renderer: HardwareRenderer,
        val reader: ImageReader,
        val image: Image
    ) {
        fun close() {
            renderer.destroy()
            image.close()
            reader.close()
        }
    }

    private val main = Handler(Looper.getMainLooper())
    private var entry: Entry? = null
    private var pending: CardSurfaceFrame.BackgroundKey? = null
    private var observed: CardSurfaceFrame.BackgroundKey? = null
    private var observedAt = 0L
    private var failedKey: CardSurfaceFrame.BackgroundKey? = null

    @Volatile private var closed = false

    @Volatile private var suspended = false
    var backgroundPassCount = 0
        private set

    fun shaderFor(
        frame: CardSurfaceFrame,
        key: CardSurfaceFrame.BackgroundKey,
        now: Long
    ): Shader? {
        if (closed) return null
        suspended = false
        entry?.takeIf { it.key == key }?.let { return it.shader }
        if (observed != key) {
            observed = key
            observedAt = now
        }
        // Moving light renders directly; cache a stable pose without creating a second pass per frame.
        if (pending == null && failedKey != key && now - observedAt >= 80L) {
            pending = key
            CardSurfaceResources.renderSurface {
                val rendered = if (!closed && !suspended) render(frame, key) else null
                main.post {
                    pending = null
                    if (closed || suspended || observed != key) {
                        rendered?.let { CardSurfaceResources.renderSurface(it::close) }
                    } else if (rendered != null) {
                        val old = entry
                        entry = rendered
                        backgroundPassCount++
                        old?.let { CardSurfaceResources.renderSurface(it::close) }
                        onReady()
                    } else {
                        failedKey = key
                    }
                }
            }
        }
        return null
    }

    private fun render(frame: CardSurfaceFrame, key: CardSurfaceFrame.BackgroundKey): Entry? {
        val w = (frame.width * frame.density).roundToInt().coerceAtLeast(1)
        val h = (frame.height * frame.density).roundToInt().coerceAtLeast(1)
        var reader: ImageReader? = null
        var renderer: HardwareRenderer? = null
        var image: Image? = null
        var retained = false
        return try {
            val target = ImageReader.Builder(w, h)
                .setDefaultHardwareBufferFormat(HardwareBuffer.RGBA_8888)
                .setDefaultDataSpace(DataSpace.DATASPACE_SRGB)
                .setMaxImages(2)
                .setUsage(
                    HardwareBuffer.USAGE_GPU_SAMPLED_IMAGE or HardwareBuffer.USAGE_GPU_COLOR_OUTPUT
                )
                .build().also { reader = it }
            val node = RenderNode("Card background cache")
            node.setPosition(0, 0, w, h)
            val shader = createShader()
            applyFrame(shader, frame)
            val canvas = node.beginRecording(w, h)
            canvas.scale(frame.density, frame.density)
            canvas.drawRect(
                0f,
                0f,
                frame.width,
                frame.height,
                Paint().apply {
                    this.shader = shader
                }
            )
            node.endRecording()
            val gpu = HardwareRenderer().also { renderer = it }
            gpu.setSurface(target.surface)
            gpu.setContentRoot(node)
            gpu.setOpaque(true)
            if (closed || suspended) return null
            val result = gpu.createRenderRequest().setWaitForPresent(true).syncAndDraw()
            if (result != HardwareRenderer.SYNC_OK) return null
            val pixels = target.acquireLatestImage()?.also { image = it } ?: return null
            val buffer = pixels.hardwareBuffer ?: return null
            val bitmap = try {
                Bitmap.wrapHardwareBuffer(buffer, ColorSpace.get(ColorSpace.Named.SRGB))
            } finally {
                buffer.close()
            } ?: return null
            val cached = BitmapShader(bitmap, Shader.TileMode.CLAMP, Shader.TileMode.CLAMP).apply {
                setFilterMode(BitmapShader.FILTER_MODE_LINEAR)
                setLocalMatrix(Matrix().apply { setScale(1 / frame.density, 1 / frame.density) })
            }
            retained = true
            Entry(key, cached, gpu, target, pixels)
        } catch (_: RuntimeException) {
            null
        } finally {
            if (!retained) {
                renderer?.destroy()
                image?.close()
                reader?.close()
            }
        }
    }

    fun close() {
        closed = true
        observed = null
        val old = entry
        entry = null
        old?.let { CardSurfaceResources.renderSurface(it::close) }
    }

    fun pause() {
        suspended = true
        observed = null
    }
}
