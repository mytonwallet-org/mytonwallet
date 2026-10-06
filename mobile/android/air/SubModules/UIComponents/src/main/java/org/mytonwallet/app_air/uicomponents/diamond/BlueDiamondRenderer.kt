package org.mytonwallet.app_air.uicomponents.diamond

import android.content.res.AssetManager
import android.graphics.SurfaceTexture
import android.opengl.EGL14.EGL_ALPHA_SIZE
import android.opengl.EGL14.EGL_BLUE_SIZE
import android.opengl.EGL14.EGL_CONTEXT_CLIENT_VERSION
import android.opengl.EGL14.EGL_DEFAULT_DISPLAY
import android.opengl.EGL14.EGL_DEPTH_SIZE
import android.opengl.EGL14.EGL_GREEN_SIZE
import android.opengl.EGL14.EGL_NONE
import android.opengl.EGL14.EGL_NO_CONTEXT
import android.opengl.EGL14.EGL_NO_DISPLAY
import android.opengl.EGL14.EGL_NO_SURFACE
import android.opengl.EGL14.EGL_RED_SIZE
import android.opengl.EGL14.EGL_RENDERABLE_TYPE
import android.opengl.EGL14.EGL_SAMPLES
import android.opengl.EGL14.EGL_SAMPLE_BUFFERS
import android.opengl.EGL14.EGL_SURFACE_TYPE
import android.opengl.EGL14.EGL_WINDOW_BIT
import android.opengl.EGL14.eglChooseConfig
import android.opengl.EGL14.eglCreateContext
import android.opengl.EGL14.eglCreateWindowSurface
import android.opengl.EGL14.eglDestroyContext
import android.opengl.EGL14.eglDestroySurface
import android.opengl.EGL14.eglGetDisplay
import android.opengl.EGL14.eglGetError
import android.opengl.EGL14.eglInitialize
import android.opengl.EGL14.eglMakeCurrent
import android.opengl.EGL14.eglReleaseThread
import android.opengl.EGL14.eglSwapBuffers
import android.opengl.EGL14.eglTerminate
import android.opengl.EGLConfig
import android.os.Handler
import android.os.HandlerThread
import android.os.SystemClock
import android.util.Log
import android.view.Surface
import kotlin.math.min

internal class BlueDiamondRenderer(
    private val assets: AssetManager,
    private val texture: SurfaceTexture,
    private var size: Int,
    private val onError: () -> Unit
) {
    private val thread = HandlerThread("BlueDiamond").apply { start() }
    private val handler = Handler(thread.looper)
    private val motion = BlueDiamondMotion()
    private var display = EGL_NO_DISPLAY
    private var eglContext = EGL_NO_CONTEXT
    private var eglSurface = EGL_NO_SURFACE
    private var surface: Surface? = null
    private var scene: BlueDiamondScene? = null
    private var isVisible = false
    private var canAnimate = false
    private var hasFailed = false
    private var time = 0f
    private var lastFrameAt = 0L
    private val drawFrame = Runnable { drawFrame() }

    @Volatile private var isStopped = false

    init {
        handler.post {
            try {
                initialize()
            } catch (error: Exception) {
                fail(error)
            }
        }
    }

    fun setPlayback(isVisible: Boolean, canAnimate: Boolean) {
        handler.post {
            this.isVisible = isVisible
            this.canAnimate = canAnimate
            handler.removeCallbacks(drawFrame)
            lastFrameAt = 0
            if (isVisible) drawFrame()
        }
    }

    fun resize(size: Int) {
        handler.post {
            this.size = size
            if (isVisible && !canAnimate) drawFrame()
        }
    }

    fun press() = handler.post { motion.press() }
    fun drag(dx: Float, dy: Float) = handler.post { motion.drag(dx, dy) }
    fun release(tapX: Float? = null, tapY: Float? = null) =
        handler.post { motion.release(time, tapX, tapY) }

    fun stop() {
        isStopped = true
        handler.post {
            handler.removeCallbacks(drawFrame)
            closeEgl()
            texture.release()
            thread.quitSafely()
        }
    }

    private fun initialize() {
        if (isStopped) return
        display = eglGetDisplay(EGL_DEFAULT_DISPLAY)
        check(display != EGL_NO_DISPLAY)
        check(eglInitialize(display, IntArray(2), 0, IntArray(2), 0))
        val configs = arrayOfNulls<EGLConfig>(1)
        val count = IntArray(1)
        val config = listOf(4, 2, 0).firstNotNullOfOrNull { samples ->
            val found = eglChooseConfig(
                display,
                intArrayOf(
                    EGL_RENDERABLE_TYPE, 0x40, EGL_SURFACE_TYPE, EGL_WINDOW_BIT,
                    EGL_RED_SIZE, 8, EGL_GREEN_SIZE, 8, EGL_BLUE_SIZE, 8, EGL_ALPHA_SIZE, 8,
                    EGL_DEPTH_SIZE, 16,
                    EGL_SAMPLE_BUFFERS, if (samples > 0) 1 else 0,
                    EGL_SAMPLES, samples, EGL_NONE
                ),
                0,
                configs,
                0,
                1,
                count,
                0
            )
            if (found && count[0] > 0) configs[0] else null
        }
        checkNotNull(config)
        eglContext =
            eglCreateContext(
                display,
                config,
                EGL_NO_CONTEXT,
                intArrayOf(EGL_CONTEXT_CLIENT_VERSION, 3, EGL_NONE),
                0
            )
        check(eglContext != EGL_NO_CONTEXT)
        surface = Surface(texture)
        eglSurface = eglCreateWindowSurface(display, config, surface, intArrayOf(EGL_NONE), 0)
        check(eglSurface != EGL_NO_SURFACE)
        check(eglMakeCurrent(display, eglSurface, eglSurface, eglContext))
        scene = BlueDiamondScene(assets)
    }

    private fun drawFrame() {
        if (isStopped || hasFailed || !isVisible) return
        val scene = scene ?: return
        try {
            val now = SystemClock.elapsedRealtimeNanos()
            val frameTime = if (lastFrameAt ==
                0L
            ) {
                1f / 60
            } else {
                min(0.1f, (now - lastFrameAt) / 1_000_000_000f)
            }
            lastFrameAt = now
            if (canAnimate) {
                time += frameTime
                motion.update(time)
            }
            scene.draw(size, time, frameTime, motion.yaw, motion.pitch)
            check(eglSwapBuffers(display, eglSurface)) {
                "Diamond EGL swap failed: ${eglGetError()}"
            }
            if (canAnimate) handler.postDelayed(drawFrame, 16)
        } catch (error: Exception) {
            fail(error)
        }
    }

    private fun fail(error: Exception) {
        Log.w("BlueDiamond", "Unable to render diamond", error)
        hasFailed = true
        handler.removeCallbacks(drawFrame)
        closeEgl()
        onError()
    }

    private fun closeEgl() {
        scene = null
        if (display != EGL_NO_DISPLAY) {
            eglMakeCurrent(display, EGL_NO_SURFACE, EGL_NO_SURFACE, EGL_NO_CONTEXT)
            if (eglSurface != EGL_NO_SURFACE) eglDestroySurface(display, eglSurface)
            if (eglContext != EGL_NO_CONTEXT) eglDestroyContext(display, eglContext)
            eglTerminate(display)
            eglReleaseThread()
        }
        eglSurface = EGL_NO_SURFACE
        eglContext = EGL_NO_CONTEXT
        display = EGL_NO_DISPLAY
        surface?.release()
        surface = null
    }
}
