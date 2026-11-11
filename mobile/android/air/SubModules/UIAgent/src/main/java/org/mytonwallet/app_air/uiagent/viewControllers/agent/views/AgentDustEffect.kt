package org.mytonwallet.app_air.uiagent.viewControllers.agent.views

import android.animation.ValueAnimator
import android.app.ActivityManager
import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.SurfaceTexture
import android.opengl.EGL14
import android.opengl.EGLConfig
import android.opengl.EGLContext
import android.opengl.EGLDisplay
import android.opengl.EGLExt
import android.opengl.EGLSurface
import android.opengl.GLES30
import android.opengl.GLUtils
import android.os.Build
import android.os.Handler
import android.os.HandlerThread
import android.os.Looper
import android.view.Choreographer
import android.view.TextureView
import android.view.View
import android.view.ViewGroup
import androidx.core.animation.doOnEnd
import androidx.core.graphics.createBitmap
import androidx.core.graphics.withTranslation
import java.util.concurrent.atomic.AtomicBoolean
import kotlin.math.max
import kotlin.math.roundToInt
import kotlin.math.sqrt
import org.mytonwallet.app_air.uicomponents.AnimationConstants
import org.mytonwallet.app_air.walletbasecontext.DEBUG_MODE
import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage
import org.mytonwallet.app_air.walletcontext.helpers.DevicePerformanceClassifier

/**
 * Telegram's `ThanosEffect`: views turn to dust in place, each pixel a particle that drifts off
 * and fades, drawn with OpenGL ES 3 on a thread of its own. The effect lays itself over the list
 * whose rows it takes, and removes itself once the dust has settled. Where it can't run, the rows
 * fade instead.
 */
internal class AgentDustEffect(
    context: Context,
    private val onFinished: (AgentDustEffect) -> Unit
) : TextureView(context),
    TextureView.SurfaceTextureListener {

    companion object {
        // A device that failed to set the effect up fades from then on
        @Volatile
        private var isBroken = false

        /** Whether the dust can run: animations on, OpenGL ES 3 and not a low-end device */
        fun isSupported(context: Context): Boolean {
            if (isBroken || !WGlobalStorage.getAreAnimationsActive()) return false
            if (DevicePerformanceClassifier.isLowClass) return false
            val manager = context.getSystemService(ActivityManager::class.java) ?: return false
            return manager.deviceConfigurationInfo.reqGlEsVersion >= GLES_3
        }

        private const val GLES_3 = 0x30000
        private const val FADE_MS = AnimationConstants.VERY_QUICK_ANIMATION
    }

    // Rows captured as one picture, in the list's coordinates until the effect knows where it lies
    private class Dust(
        val bitmap: Bitmap,
        var left: Float,
        var top: Float,
        val views: List<View>,
        val source: View,
        val onStarted: () -> Unit,
        val onDone: () -> Unit
    )

    private val mainHandler = Handler(Looper.getMainLooper())
    private val waiting = ArrayList<Dust>()
    private var thread: DustThread? = null
    private var isKilled = false

    // Stopped by its owner, as when the chat closes: nothing more is shown or started
    private var isStopped = false
    private val sourceLocation = IntArray(2)
    private val ownLocation = IntArray(2)

    private val frameCallback = object : Choreographer.FrameCallback {
        override fun doFrame(frameTimeNanos: Long) {
            val thread = thread ?: return
            if (!thread.isRunning) return
            thread.requestDraw()
            Choreographer.getInstance().postFrameCallback(this)
        }
    }

    init {
        isOpaque = false
        importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_NO
        surfaceTextureListener = this
    }

    /**
     * Turns [views], rows of [source], to dust. [onStarted] runs once the dust is on screen, where
     * the rows are to be hidden, and [onDone] once it has settled or was stopped.
     */
    fun dissolve(source: View, views: List<View>, onStarted: () -> Unit, onDone: () -> Unit) {
        val shown = views.filter { it.width > 0 && it.height > 0 && it.isShown }
        // Debug builds skip the dust while system animations are off, to keep E2E runs fast
        if (isKilled || shown.isEmpty() || (DEBUG_MODE && !areSystemAnimatorsEnabled)) {
            onStarted()
            onDone()
            return
        }
        val left = shown.minOf { it.x }
        val top = shown.minOf { it.y }
        val right = shown.maxOf { it.x + it.width }
        val bottom = shown.maxOf { it.y + it.height }
        val width = (right - left).roundToInt().coerceAtLeast(1)
        val height = (bottom - top).roundToInt().coerceAtLeast(1)
        val bitmap = createBitmap(width, height)
        val canvas = Canvas(bitmap)
        for (view in shown) {
            canvas.withTranslation(view.x - left, view.y - top) {
                view.draw(this)
                drawTextureViews(view, view, this)
            }
        }
        val dust = Dust(bitmap, left, top, shown, source, onStarted, onDone)
        val thread = thread
        if (thread == null) waiting.add(dust) else submit(thread, dust)
    }

    // A software canvas leaves out what a `TextureView` shows, as the 3D top of a chat's status, so its frame is
    // drawn over the row where it stands
    private fun drawTextureViews(row: View, view: View, canvas: Canvas) {
        if (view.visibility != VISIBLE) return
        if (view is TextureView) {
            if (!view.isAvailable || view.width <= 0 || view.height <= 0) return
            val frame = view.getBitmap() ?: return
            view.getLocationInWindow(viewLocation)
            row.getLocationInWindow(rowLocation)
            var alpha = 1f
            var current: View? = view
            while (current != null && current !== row) {
                alpha *= current.alpha
                current = current.parent as? View
            }
            texturePaint.alpha = (alpha * 255).roundToInt().coerceIn(0, 255)
            canvas.drawBitmap(
                frame,
                (viewLocation[0] - rowLocation[0]).toFloat(),
                (viewLocation[1] - rowLocation[1]).toFloat(),
                texturePaint
            )
            frame.recycle()
            return
        }
        if (view is ViewGroup) {
            for (index in 0 until view.childCount) {
                drawTextureViews(row, view.getChildAt(index), canvas)
            }
        }
    }

    private val areSystemAnimatorsEnabled: Boolean
        get() = Build.VERSION.SDK_INT < Build.VERSION_CODES.O || ValueAnimator.areAnimatorsEnabled()

    private val viewLocation = IntArray(2)
    private val rowLocation = IntArray(2)
    private val texturePaint = Paint(Paint.FILTER_BITMAP_FLAG)

    /** Whether it still takes rows; once its dust has settled it goes */
    val isActive: Boolean get() = !isKilled

    /** Stops the dust at once, as when its chat closes */
    fun kill() {
        isStopped = true
        if (isKilled) return
        isKilled = true
        Choreographer.getInstance().removeFrameCallback(frameCallback)
        waiting.forEach {
            it.bitmap.recycle()
            it.onDone()
        }
        waiting.clear()
        thread?.kill()
        thread = null
        finish()
    }

    private fun submit(thread: DustThread, dust: Dust) {
        // From the list's coordinates to the effect's
        dust.source.getLocationInWindow(sourceLocation)
        getLocationInWindow(ownLocation)
        dust.left += sourceLocation[0] - ownLocation[0]
        dust.top += sourceLocation[1] - ownLocation[1]
        thread.add(dust)
        Choreographer.getInstance().removeFrameCallback(frameCallback)
        Choreographer.getInstance().postFrameCallback(frameCallback)
    }

    // Without the dust, the rows fade as they did before it; a stopped effect only lets go of them
    private fun fade(dust: Dust) {
        if (!dust.bitmap.isRecycled) dust.bitmap.recycle()
        if (isStopped) {
            dust.onDone()
            return
        }
        ValueAnimator.ofFloat(1f, 0f).apply {
            duration = FADE_MS
            addUpdateListener { animation ->
                val alpha = animation.animatedValue as Float
                dust.views.forEach { it.alpha = alpha }
            }
            doOnEnd {
                dust.onStarted()
                dust.views.forEach { it.alpha = 1f }
                dust.onDone()
            }
            start()
        }
    }

    private fun finish() {
        isKilled = true
        thread = null
        Choreographer.getInstance().removeFrameCallback(frameCallback)
        mainHandler.post { onFinished(this) }
    }

    override fun onSurfaceTextureAvailable(surface: SurfaceTexture, width: Int, height: Int) {
        if (isKilled) {
            surface.release()
            return
        }
        val particleBudget = when {
            DevicePerformanceClassifier.isHighClass -> 120_000
            DevicePerformanceClassifier.isMediumClass -> 60_000
            else -> 30_000
        }
        val thread = DustThread(
            surface,
            width,
            height,
            resources.displayMetrics.density,
            particleBudget
        )
        this.thread = thread
        thread.begin()
        waiting.forEach { submit(thread, it) }
        waiting.clear()
    }

    override fun onSurfaceTextureSizeChanged(surface: SurfaceTexture, width: Int, height: Int) {
        thread?.resize(width, height)
    }

    override fun onSurfaceTextureDestroyed(surface: SurfaceTexture): Boolean {
        // The thread releases the surface as it ends
        thread?.kill()
        thread = null
        if (!isKilled) finish()
        return false
    }

    override fun onSurfaceTextureUpdated(surface: SurfaceTexture) = Unit

    /** Draws the dust; it ends itself once the last of it has settled */
    private inner class DustThread(
        private val surfaceTexture: SurfaceTexture,
        private var width: Int,
        private var height: Int,
        private val density: Float,
        private val particleBudget: Int
    ) : HandlerThread("AgentDustEffect") {
        @Volatile
        var isRunning = true
            private set

        private val isAlive = AtomicBoolean(true)
        private val isDrawRequested = AtomicBoolean(false)
        private var handler: Handler? = null
        private val particles = ArrayList<Particles>()
        private val started = ArrayList<Particles>()
        private var hasDrawn = false
        private var isReady = false

        private var display: EGLDisplay = EGL14.EGL_NO_DISPLAY
        private var eglContext: EGLContext = EGL14.EGL_NO_CONTEXT
        private var eglSurface: EGLSurface = EGL14.EGL_NO_SURFACE
        private var program = 0
        private val uniforms = HashMap<String, Int>()

        /** Starts the thread; work posted from now on runs once OpenGL is set up */
        fun begin() {
            start()
            handler = Handler(looper)
        }

        override fun onLooperPrepared() {
            isReady = try {
                setUp()
            } catch (_: Throwable) {
                false
            }
            if (!isReady) {
                isBroken = true
                release()
            }
        }

        fun add(dust: Dust) {
            val posted = handler?.post {
                if (isReady && isAlive.get()) {
                    addParticles(dust)
                } else {
                    mainHandler.post { fade(dust) }
                }
            } == true
            if (!posted) fade(dust)
        }

        fun requestDraw() {
            if (!isAlive.get() || !isDrawRequested.compareAndSet(false, true)) return
            handler?.post {
                isDrawRequested.set(false)
                draw()
            }
        }

        fun resize(width: Int, height: Int) {
            handler?.post {
                if (!isAlive.get() || !isReady) return@post
                this.width = width
                this.height = height
                GLES30.glViewport(0, 0, width, height)
                GLES30.glUniform2f(findUniform("size"), width.toFloat(), height.toFloat())
            }
        }

        fun kill() {
            isRunning = false
            val isPosted = handler?.post { release() } == true
            if (!isPosted && isAlive.compareAndSet(true, false)) {
                surfaceTexture.release()
                quitSafely()
            }
        }

        private fun findUniform(name: String) =
            uniforms.getOrPut(name) { GLES30.glGetUniformLocation(program, name) }

        private fun setUp(): Boolean {
            if (!isAlive.get()) return false
            display = EGL14.eglGetDisplay(EGL14.EGL_DEFAULT_DISPLAY)
            if (display == EGL14.EGL_NO_DISPLAY) return false
            val version = IntArray(2)
            if (!EGL14.eglInitialize(display, version, 0, version, 1)) return false
            val configs = arrayOfNulls<EGLConfig>(1)
            val count = IntArray(1)
            val attributes = intArrayOf(
                EGL14.EGL_RED_SIZE, 8,
                EGL14.EGL_GREEN_SIZE, 8,
                EGL14.EGL_BLUE_SIZE, 8,
                EGL14.EGL_ALPHA_SIZE, 8,
                EGL14.EGL_RENDERABLE_TYPE, EGLExt.EGL_OPENGL_ES3_BIT_KHR,
                EGL14.EGL_NONE
            )
            val hasConfig = EGL14.eglChooseConfig(display, attributes, 0, configs, 0, 1, count, 0)
            if (!hasConfig || count[0] == 0) return false
            val config = configs[0] ?: return false
            eglContext = EGL14.eglCreateContext(
                display,
                config,
                EGL14.EGL_NO_CONTEXT,
                intArrayOf(EGL14.EGL_CONTEXT_CLIENT_VERSION, 3, EGL14.EGL_NONE),
                0
            )
            if (eglContext == EGL14.EGL_NO_CONTEXT) return false
            eglSurface = EGL14.eglCreateWindowSurface(
                display,
                config,
                surfaceTexture,
                intArrayOf(EGL14.EGL_NONE),
                0
            )
            if (eglSurface == EGL14.EGL_NO_SURFACE) return false
            if (!EGL14.eglMakeCurrent(display, eglSurface, eglSurface, eglContext)) return false

            val vertex = compile(GLES30.GL_VERTEX_SHADER, VERTEX_SHADER) ?: return false
            val fragment = compile(GLES30.GL_FRAGMENT_SHADER, FRAGMENT_SHADER) ?: return false
            program = GLES30.glCreateProgram()
            if (program == 0) return false
            GLES30.glAttachShader(program, vertex)
            GLES30.glAttachShader(program, fragment)
            GLES30.glTransformFeedbackVaryings(
                program,
                arrayOf("outUV", "outPosition", "outVelocity", "outTime"),
                GLES30.GL_INTERLEAVED_ATTRIBS
            )
            GLES30.glLinkProgram(program)
            GLES30.glDeleteShader(vertex)
            GLES30.glDeleteShader(fragment)
            val status = IntArray(1)
            GLES30.glGetProgramiv(program, GLES30.GL_LINK_STATUS, status, 0)
            if (status[0] != GLES30.GL_TRUE) return false
            GLES30.glViewport(0, 0, width, height)
            GLES30.glDisable(GLES30.GL_BLEND)
            GLES30.glClearColor(0f, 0f, 0f, 0f)
            GLES30.glUseProgram(program)
            GLES30.glUniform2f(findUniform("size"), width.toFloat(), height.toFloat())
            return true
        }

        private fun compile(type: Int, source: String): Int? {
            val shader = GLES30.glCreateShader(type)
            if (shader == 0) return null
            GLES30.glShaderSource(shader, source)
            GLES30.glCompileShader(shader)
            val status = IntArray(1)
            GLES30.glGetShaderiv(shader, GLES30.GL_COMPILE_STATUS, status, 0)
            if (status[0] != GLES30.GL_TRUE) {
                GLES30.glDeleteShader(shader)
                return null
            }
            return shader
        }

        private fun addParticles(dust: Dust) {
            if (!isAlive.get()) {
                dust.bitmap.recycle()
                mainHandler.post(dust.onDone)
                return
            }
            val texture = IntArray(1)
            GLES30.glGenTextures(1, texture, 0)
            GLES30.glBindTexture(GLES30.GL_TEXTURE_2D, texture[0])
            val target = GLES30.GL_TEXTURE_2D
            GLES30.glTexParameteri(target, GLES30.GL_TEXTURE_MIN_FILTER, GLES30.GL_LINEAR)
            GLES30.glTexParameteri(target, GLES30.GL_TEXTURE_MAG_FILTER, GLES30.GL_LINEAR)
            GLES30.glTexParameteri(target, GLES30.GL_TEXTURE_WRAP_S, GLES30.GL_CLAMP_TO_EDGE)
            GLES30.glTexParameteri(target, GLES30.GL_TEXTURE_WRAP_T, GLES30.GL_CLAMP_TO_EDGE)
            GLUtils.texImage2D(GLES30.GL_TEXTURE_2D, 0, dust.bitmap, 0)
            GLES30.glBindTexture(GLES30.GL_TEXTURE_2D, 0)
            particles.add(Particles(dust, texture[0], dust.bitmap.width, dust.bitmap.height))
            dust.bitmap.recycle()
            isRunning = true
        }

        private fun draw() {
            if (!isAlive.get() || !isReady) return
            GLES30.glClear(GLES30.GL_COLOR_BUFFER_BIT)
            started.clear()
            val totalHeight = particles.sumOf { it.height }.coerceAtLeast(1)
            val iterator = particles.iterator()
            while (iterator.hasNext()) {
                val item = iterator.next()
                if (item.isFirstDraw) {
                    item.allocate(item.height.toFloat() / totalHeight)
                    started.add(item)
                }
                hasDrawn = true
                item.draw()
                if (item.isDead) {
                    item.release(shouldRunCallback = true)
                    iterator.remove()
                }
            }
            if (!EGL14.eglSwapBuffers(display, eglSurface)) {
                // The surface is gone: what had started is hidden, as it would have been
                isBroken = true
                postStarted()
                release()
                return
            }
            postStarted()
            if (particles.isEmpty() && hasDrawn) release()
        }

        // The rows hide once their dust shows, unless the effect was stopped meanwhile
        private fun postStarted() {
            for (item in started) {
                val onStarted = item.dust.onStarted
                mainHandler.post { if (!isStopped) onStarted() }
            }
            started.clear()
        }

        private fun release() {
            if (!isAlive.compareAndSet(true, false)) return
            isRunning = false
            particles.forEach { it.release(shouldRunCallback = true) }
            particles.clear()
            if (program != 0) {
                GLES30.glDeleteProgram(program)
                program = 0
            }
            if (display != EGL14.EGL_NO_DISPLAY) {
                val none = EGL14.EGL_NO_SURFACE
                EGL14.eglMakeCurrent(display, none, none, EGL14.EGL_NO_CONTEXT)
                if (eglSurface != EGL14.EGL_NO_SURFACE) EGL14.eglDestroySurface(display, eglSurface)
                if (eglContext != EGL14.EGL_NO_CONTEXT) EGL14.eglDestroyContext(display, eglContext)
                EGL14.eglReleaseThread()
            }
            surfaceTexture.release()
            val ended = this
            mainHandler.post { if (thread === ended) finish() }
            quitSafely()
        }

        /** One picture's particles: one per few pixels, each carrying its texel */
        private inner class Particles(
            val dust: Dust,
            private val texture: Int,
            val width: Int,
            val height: Int
        ) {
            var isFirstDraw = true
                private set
            private var time = 0f
            private var lastDrawNanos = -1L
            private val buffers = IntArray(2)
            private var currentBuffer = 0
            private var count = 0
            private var gridWidth = 1
            private var gridHeight = 1
            private var gridSize = 1f
            private val seed = (Math.random() * 2).toFloat()
            private val matrix = FloatArray(9)
            private var hasBuffers = false

            val isDead: Boolean get() = time > LONGEVITY + TAIL

            fun allocate(share: Float) {
                val pixel = max(PARTICLE_DP * density, 1f)
                count = (width * height / (pixel * pixel)).toInt()
                    .coerceIn(MIN_PARTICLES, max(MIN_PARTICLES, (particleBudget * share).toInt()))
                val aspect = width.toFloat() / height
                gridHeight = sqrt(count / aspect).roundToInt().coerceAtLeast(1)
                gridWidth = (count.toFloat() / gridHeight).roundToInt().coerceAtLeast(1)
                while (gridWidth * gridHeight < count) {
                    if (gridWidth.toFloat() / gridHeight < aspect) gridWidth++ else gridHeight++
                }
                count = gridWidth * gridHeight
                gridSize = max(width.toFloat() / gridWidth, height.toFloat() / gridHeight)
                GLES30.glGenBuffers(2, buffers, 0)
                hasBuffers = true
                for (buffer in buffers) {
                    GLES30.glBindBuffer(GLES30.GL_ARRAY_BUFFER, buffer)
                    val bytes = count * STRIDE
                    GLES30.glBufferData(GLES30.GL_ARRAY_BUFFER, bytes, null, GLES30.GL_DYNAMIC_DRAW)
                }
                // The unit square onto the picture's place, column by column
                matrix[0] = width.toFloat()
                matrix[4] = height.toFloat()
                matrix[6] = dust.left
                matrix[7] = dust.top
                matrix[8] = 1f
            }

            fun draw() {
                val now = System.nanoTime()
                val delta = if (lastDrawNanos < 0) 0f else (now - lastDrawNanos) / 1_000_000_000f
                lastDrawNanos = now
                time += delta * TIME_SCALE
                GLES30.glUniformMatrix3fv(findUniform("matrix"), 1, false, matrix, 0)
                GLES30.glUniform1f(findUniform("reset"), if (isFirstDraw) 1f else 0f)
                GLES30.glUniform1f(findUniform("time"), time)
                GLES30.glUniform1f(findUniform("deltaTime"), delta * TIME_SCALE)
                GLES30.glUniform1f(findUniform("particlesCount"), count.toFloat())
                GLES30.glUniform3f(
                    findUniform("gridSize"),
                    gridWidth.toFloat(),
                    gridHeight.toFloat(),
                    gridSize
                )
                GLES30.glUniform2f(findUniform("offset"), 0f, 0f)
                GLES30.glUniform1f(findUniform("scale"), 1f)
                GLES30.glUniform1f(findUniform("uvOffset"), UV_OFFSET)
                GLES30.glUniform2f(findUniform("rectSize"), width.toFloat(), height.toFloat())
                GLES30.glUniform1f(findUniform("seed"), seed)
                GLES30.glUniform1f(findUniform("dp"), density)
                GLES30.glUniform1f(findUniform("longevity"), LONGEVITY)
                GLES30.glActiveTexture(GLES30.GL_TEXTURE0)
                GLES30.glBindTexture(GLES30.GL_TEXTURE_2D, texture)
                GLES30.glUniform1i(findUniform("tex"), 0)

                GLES30.glBindBuffer(GLES30.GL_ARRAY_BUFFER, buffers[currentBuffer])
                bindAttributes()
                val feedback = buffers[1 - currentBuffer]
                GLES30.glBindBufferBase(GLES30.GL_TRANSFORM_FEEDBACK_BUFFER, 0, feedback)
                GLES30.glBeginTransformFeedback(GLES30.GL_POINTS)
                GLES30.glDrawArrays(GLES30.GL_POINTS, 0, count)
                GLES30.glEndTransformFeedback()
                GLES30.glBindBuffer(GLES30.GL_ARRAY_BUFFER, 0)
                GLES30.glBindBuffer(GLES30.GL_TRANSFORM_FEEDBACK_BUFFER, 0)
                isFirstDraw = false
                currentBuffer = 1 - currentBuffer
            }

            private fun bindAttributes() {
                // Initial UV, position, velocity, time
                GLES30.glVertexAttribPointer(0, 2, GLES30.GL_FLOAT, false, STRIDE, 0)
                GLES30.glEnableVertexAttribArray(0)
                GLES30.glVertexAttribPointer(1, 2, GLES30.GL_FLOAT, false, STRIDE, 8)
                GLES30.glEnableVertexAttribArray(1)
                GLES30.glVertexAttribPointer(2, 2, GLES30.GL_FLOAT, false, STRIDE, 16)
                GLES30.glEnableVertexAttribArray(2)
                GLES30.glVertexAttribPointer(3, 1, GLES30.GL_FLOAT, false, STRIDE, 24)
                GLES30.glEnableVertexAttribArray(3)
            }

            fun release(shouldRunCallback: Boolean) {
                if (hasBuffers) GLES30.glDeleteBuffers(2, buffers, 0)
                hasBuffers = false
                GLES30.glDeleteTextures(1, intArrayOf(texture), 0)
                if (shouldRunCallback) mainHandler.post(dust.onDone)
            }
        }
    }
}

// Telegram's dust: how long a particle lives and how fast time runs, in seconds of the effect
private const val LONGEVITY = 1.5f
private const val TAIL = 0.9f
private const val TIME_SCALE = 1.15f
private const val UV_OFFSET = 0.6f
private const val PARTICLE_DP = 0.4f
private const val MIN_PARTICLES = 10

// Bytes per particle: UV, position and velocity (two floats each) and time
private const val STRIDE = 28

private const val VERTEX_SHADER = """#version 300 es
precision highp float;

layout(location = 0) in vec2 inUV;
layout(location = 1) in vec2 inPosition;
layout(location = 2) in vec2 inVelocity;
layout(location = 3) in float inTime;

out vec2 outUV;
out vec2 outPosition;
out vec2 outVelocity;
out float outTime;

out vec2 uvcenter;
out vec2 uvsize;
out float alpha;

uniform mat3 matrix;
uniform vec2 rectSize;
uniform float reset;
uniform float time;
uniform float deltaTime;
uniform float particlesCount;
uniform vec2 size;
uniform vec3 gridSize;
uniform float seed;
uniform float longevity;
uniform float dp;
uniform vec2 offset;
uniform float scale;
uniform float uvOffset;

float rand(vec2 n) {
  return fract(sin(dot(n, vec2(12.9898, 4.1414 - seed * .42))) * 43758.5453);
}

void main() {
  vec2 uv = inUV;
  vec2 position = inPosition;
  vec2 velocity = inVelocity;
  float particleTime = inTime;

  float id = float(gl_VertexID);
  if (reset > 0.) {
    uv = vec2(mod(id, gridSize.x), floor(id / gridSize.x)) / gridSize.xy;
    position = (matrix * vec3(uv + .5 / gridSize.xy, 1.0)).xy;
    float direction = rand(3. * uv) * (3.14159265 * 2.0);
    velocity = vec2(cos(direction), sin(direction)) * (0.1 + rand(5. * uv) * (0.2 - 0.1)) * 260.0 * scale * dp;
    particleTime = (0.7 + rand(uv) * (1.5 - 0.7)) / 1.15;
  }

  float effectFraction = max(0.0, min(0.35, time)) / 0.35;
  float particleFraction = max(0.0, min(0.2, .1 + time - uv.x * uvOffset)) / 0.2;
  position += velocity * deltaTime * particleFraction;
  velocity += vec2(19.0 * (velocity.x > 0.0 ? 1.0 : -1.0) * (1.0 - effectFraction), -65.0) * deltaTime * dp * particleFraction;
  particleTime = max(0.0, particleTime - 1.2 * deltaTime * particleFraction);

  outUV = uv;
  outPosition = position;
  outVelocity = velocity;
  outTime = particleTime;

  alpha = max(0.0, min(0.55, particleTime) / 0.55);
  gl_PointSize = (gridSize.z + 1.);
  position.y = size.y - position.y;
  gl_Position = vec4((position + offset) / size * 2.0 - vec2(1.0), 0.0, 1.0);
  uvcenter = uv;
  uvsize = (vec2(gridSize.z + 1.) / rectSize.xy);
}
"""

private const val FRAGMENT_SHADER = """#version 300 es
precision highp float;

in vec2 uvcenter;
in vec2 uvsize;
in float alpha;

out vec4 fragColor;

uniform sampler2D tex;

void main() {
  if (alpha <= 0.0) {
    discard;
  }
  fragColor = texture(tex, uvcenter + gl_PointCoord * uvsize).rgba * alpha;
}
"""
