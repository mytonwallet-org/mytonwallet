package org.mytonwallet.app_air.uiagent.viewControllers.agent.views

import android.app.ActivityManager
import android.content.Context
import android.graphics.Bitmap
import android.graphics.SurfaceTexture
import android.opengl.EGL14
import android.opengl.EGLConfig
import android.opengl.EGLContext
import android.opengl.EGLDisplay
import android.opengl.EGLSurface
import android.opengl.GLES30
import android.opengl.GLUtils
import android.os.Handler
import android.os.HandlerThread
import java.nio.ByteBuffer
import java.nio.ByteOrder

/**
 * Draws spinning tops with OpenGL ES 3.0: a hollow shell of frosted glass with a blue-to-purple coating and matte
 * highlights, as iOS draws it with Metal. Every top draws on one thread with one context, each into its own
 * TextureView. A grown top sees the content captured behind it, frosted and bent by its shell; elsewhere what is
 * behind the glass is taken as the flat color behind the top: over that color the glass shows as iOS shows it over its
 * captured backdrop, and anything else behind still shows through, unfrosted.
 */
internal object AgentSpinningTopRenderer {
    /** What one frame of a top draws */
    class Frame {
        /** Model to view, column-major */
        val rotation = FloatArray(16)

        /** The model's origin, the top's point, from the canvas's center in pixels, y up */
        var originX = 0f
        var originY = 0f
        var pixelsPerUnit = 0f

        /** How firmly the top is held, 0…1: held, it turns clearer and its highlights stronger */
        var strength = 0f
        var isDark = false

        /** The color behind the top, as sRGB components */
        val backdrop = FloatArray(3)

        /** The content captured behind the top, never changed once given, or null for the flat color */
        var backdropBitmap: Bitmap? = null

        /** Where [backdropBitmap] lies in the canvas, in pixels, y down: left, top, width, height */
        val backdropRect = FloatArray(4)

        /** Draws nothing: the canvas is cleared, as while another canvas shows the top */
        var isEmpty = false

        /** How strongly the thin film over the coating shows, 0…1 */
        var iridescence = 0f

        /** The angle the body turns during an exposure, in radians, which blurs the patterns that turn with it */
        var sweep = 0f

        /** How strongly the rings of a fast spin show, 0…1 */
        var streaks = 0f

        /** A large top stands on the ground, with a shadow or a glow under it and its reflection */
        var showsGround = false

        /** The camera alone, without the top's lean and spin, column-major */
        val groundCamera = FloatArray(16)

        /** The top mirrored in the ground through its point, seen from the camera, column-major */
        val reflection = FloatArray(16)

        /** The ground point under the rim's center, model x and z */
        var bodyX = 0f
        var bodyZ = 0f

        fun copyFrom(other: Frame) {
            other.rotation.copyInto(rotation)
            originX = other.originX
            originY = other.originY
            pixelsPerUnit = other.pixelsPerUnit
            strength = other.strength
            isDark = other.isDark
            other.backdrop.copyInto(backdrop)
            backdropBitmap = other.backdropBitmap
            other.backdropRect.copyInto(backdropRect)
            isEmpty = other.isEmpty
            iridescence = other.iridescence
            sweep = other.sweep
            streaks = other.streaks
            showsGround = other.showsGround
            other.groundCamera.copyInto(groundCamera)
            other.reflection.copyInto(reflection)
            bodyX = other.bodyX
            bodyZ = other.bodyZ
        }
    }

    /** A TextureView's surface the renderer draws into */
    class Target internal constructor(internal val surfaceTexture: SurfaceTexture) {
        private val pending = Frame()
        internal val drawn = Frame()
        private var hasPending = false
        private var isDrawPosted = false
        internal var isReleased = false
        internal var eglSurface: EGLSurface = EGL14.EGL_NO_SURFACE

        /** Draws [frame] on the renderer's thread; a frame not drawn yet gives way to the next */
        fun render(frame: Frame) {
            synchronized(this) {
                if (isReleased) return
                pending.copyFrom(frame)
                hasPending = true
                if (isDrawPosted) return
                isDrawPosted = true
            }
            handler.post { drawPending(this) }
        }

        // Draws the frame just taken once more, as after the context it was drawn with was lost
        internal fun redrawTaken() {
            synchronized(this) {
                if (isReleased || hasPending) return
                pending.copyFrom(drawn)
                hasPending = true
                if (isDrawPosted) return
                isDrawPosted = true
            }
            handler.post { drawPending(this) }
        }

        internal fun takePending(): Boolean = synchronized(this) {
            isDrawPosted = false
            if (!hasPending || isReleased) return false
            drawn.copyFrom(pending)
            hasPending = false
            true
        }

        /** Stops drawing and releases the surface once the renderer's thread no longer draws into it */
        fun release() {
            synchronized(this) {
                if (isReleased) return
                isReleased = true
            }
            handler.post { releaseTarget(this) }
        }
    }

    private const val EGL_OPENGL_ES3_BIT = 0x40
    private const val GLES_3 = 0x30000

    private var isSupportChecked = false
    private var isDeviceSupported = false

    /** Set on the renderer's thread when the device can't draw the top after all; tops draw the flat mark then */
    @Volatile
    var hasFailed = false
        private set

    /** Whether tops can draw in 3D here */
    fun isAvailable(context: Context): Boolean {
        if (hasFailed) return false
        if (!isSupportChecked) {
            isSupportChecked = true
            val manager = context.getSystemService(Context.ACTIVITY_SERVICE) as? ActivityManager
            isDeviceSupported = (manager?.deviceConfigurationInfo?.reqGlEsVersion ?: 0) >= GLES_3
        }
        return isDeviceSupported
    }

    private val handler: Handler by lazy {
        val thread = HandlerThread("AgentSpinningTop").apply { start() }
        Handler(thread.looper)
    }

    fun createTarget(surfaceTexture: SurfaceTexture) = Target(surfaceTexture)

    /** Lets go of the content a grown top captured, once it shrinks back; the texture takes the next one */
    fun forgetBackdrop() {
        handler.post { uploadedBackdrop = null }
    }

    // The renderer's thread's state, touched only there

    private var display: EGLDisplay = EGL14.EGL_NO_DISPLAY
    private var context: EGLContext = EGL14.EGL_NO_CONTEXT
    private var config: EGLConfig? = null
    private var program = 0
    private var vertexArray = 0
    private var indexCount = 0
    private var rotationLocation = 0
    private var placementLocation = 0
    private var sizeLocation = 0
    private var materialLocation = 0
    private var boxCenterLocation = 0
    private var backdropLocation = 0
    private var backdropRectLocation = 0
    private var hasBackdropLocation = 0
    private var backdropTextureLocation = 0
    private var effectsLocation = 0
    private var groundProgram = 0
    private var groundVertexArray = 0
    private var groundCameraLocation = 0
    private var groundPlacementLocation = 0
    private var groundSizeLocation = 0
    private var groundBodyLocation = 0
    private var groundShadowLocation = 0
    private var groundColorLocation = 0
    private val surfaceSize = IntArray(1)

    // One grown top shows at a time: its backdrop is the one texture, uploaded when the bitmap changes
    private var backdropTexture = 0
    private var uploadedBackdrop: Bitmap? = null

    // Contexts lost in a row; the device draws the flat mark after too many
    private var contextLossCount = 0

    private fun drawPending(target: Target) {
        if (hasFailed || !target.takePending()) return
        if (!prepareContext()) return fail()
        val isNewSurface = target.eglSurface == EGL14.EGL_NO_SURFACE
        if (isNewSurface) {
            target.eglSurface = try {
                EGL14.eglCreateWindowSurface(
                    display,
                    config,
                    target.surfaceTexture,
                    intArrayOf(EGL14.EGL_NONE),
                    0
                )
            } catch (_: IllegalArgumentException) {
                EGL14.EGL_NO_SURFACE
            }
            // A surface already abandoned by its view is left alone; its view releases it
            if (target.eglSurface == EGL14.EGL_NO_SURFACE) return
        }
        if (!EGL14.eglMakeCurrent(display, target.eglSurface, target.eglSurface, context)) {
            val error = EGL14.eglGetError()
            destroySurface(target)
            if (error == EGL14.EGL_CONTEXT_LOST) loseContext(target)
            return
        }
        // A view that doesn't take a frame in time misses it rather than holding up the other tops
        if (isNewSurface) EGL14.eglSwapInterval(display, 0)
        if (program == 0 && !prepareResources()) return fail()
        EGL14.eglQuerySurface(display, target.eglSurface, EGL14.EGL_WIDTH, surfaceSize, 0)
        val width = surfaceSize[0]
        EGL14.eglQuerySurface(display, target.eglSurface, EGL14.EGL_HEIGHT, surfaceSize, 0)
        val height = surfaceSize[0]
        if (width <= 0 || height <= 0) return
        draw(target.drawn, width, height)
        if (EGL14.eglSwapBuffers(display, target.eglSurface)) {
            contextLossCount = 0
            return
        }
        val error = EGL14.eglGetError()
        destroySurface(target)
        if (error == EGL14.EGL_CONTEXT_LOST) loseContext(target)
    }

    // A lost context takes its program, mesh and texture with it: they are made again for the next frame, which
    // redraws the lost one
    private fun loseContext(target: Target) {
        EGL14.eglDestroyContext(display, context)
        context = EGL14.EGL_NO_CONTEXT
        program = 0
        vertexArray = 0
        backdropTexture = 0
        uploadedBackdrop = null
        contextLossCount += 1
        if (contextLossCount > MAX_CONTEXT_LOSSES) return fail()
        target.redrawTaken()
    }

    private fun draw(frame: Frame, width: Int, height: Int) {
        GLES30.glViewport(0, 0, width, height)
        GLES30.glClearColor(0f, 0f, 0f, 0f)
        GLES30.glDepthMask(true)
        GLES30.glClear(GLES30.GL_COLOR_BUFFER_BIT or GLES30.GL_DEPTH_BUFFER_BIT)
        if (frame.isEmpty || frame.pixelsPerUnit <= 0f) return
        val placementX = width / 2f + frame.originX
        val placementY = height / 2f + frame.originY
        val ground = if (frame.isDark) darkGround else lightGround
        GLES30.glEnable(GLES30.GL_BLEND)
        GLES30.glBlendFunc(GLES30.GL_ONE, GLES30.GL_ONE_MINUS_SRC_ALPHA)
        if (frame.showsGround) {
            // The ground draws under everything, without depth
            GLES30.glUseProgram(groundProgram)
            GLES30.glUniformMatrix4fv(groundCameraLocation, 1, false, frame.groundCamera, 0)
            GLES30.glUniform3f(groundPlacementLocation, placementX, placementY, frame.pixelsPerUnit)
            GLES30.glUniform2f(groundSizeLocation, width.toFloat(), height.toFloat())
            GLES30.glUniform2f(groundBodyLocation, frame.bodyX, frame.bodyZ)
            GLES30.glUniform4f(
                groundShadowLocation,
                ground.contact,
                ground.body,
                ground.radius,
                if (ground.isGlow) 1f else 0f
            )
            val color = ground.color
            GLES30.glUniform3f(groundColorLocation, color[0], color[1], color[2])
            GLES30.glDisable(GLES30.GL_DEPTH_TEST)
            GLES30.glDisable(GLES30.GL_CULL_FACE)
            GLES30.glBindVertexArray(groundVertexArray)
            GLES30.glDrawArrays(GLES30.GL_TRIANGLE_STRIP, 0, 4)
        }

        GLES30.glUseProgram(program)
        GLES30.glUniform3f(placementLocation, placementX, placementY, frame.pixelsPerUnit)
        GLES30.glUniform2f(sizeLocation, width.toFloat(), height.toFloat())
        GLES30.glUniform3f(
            materialLocation,
            frame.strength,
            if (frame.isDark) 1f else 0f,
            HIGHLIGHT_BOOST * frame.strength
        )
        GLES30.glUniform2f(
            boxCenterLocation,
            -AgentSpinningTopGeometry.RESTING_OFFSET_X,
            -AgentSpinningTopGeometry.RESTING_OFFSET_Y
        )
        val backdrop = frame.backdrop
        GLES30.glUniform3f(backdropLocation, backdrop[0], backdrop[1], backdrop[2])
        val hasBackdrop = bindBackdrop(frame.backdropBitmap)
        GLES30.glUniform1f(hasBackdropLocation, if (hasBackdrop) 1f else 0f)
        if (hasBackdrop) {
            val rect = frame.backdropRect
            GLES30.glUniform4f(backdropRectLocation, rect[0], rect[1], rect[2], rect[3])
        }
        GLES30.glBindVertexArray(vertexArray)
        GLES30.glEnable(GLES30.GL_DEPTH_TEST)
        GLES30.glDepthFunc(GLES30.GL_LESS)
        GLES30.glEnable(GLES30.GL_CULL_FACE)
        if (frame.showsGround) {
            // The mirror flips the winding, so the reflection's outside faces clockwise; it takes the farther half
            // of the depth range, so the top always draws over it
            drawShell(frame, frame.reflection, GLES30.GL_CW, ground.reflection)
        }
        drawShell(frame, frame.rotation, GLES30.GL_CCW, 0f)
        GLES30.glBindVertexArray(0)
    }

    // The mesh is closed and wound counter-clockwise from outside. The hollow shell draws its back wall first, seen
    // from inside, then its front wall over it; the depth test keeps the nearest of each.
    private fun drawShell(
        frame: Frame,
        rotation: FloatArray,
        frontFace: Int,
        reflectionOpacity: Float
    ) {
        GLES30.glUniformMatrix4fv(rotationLocation, 1, false, rotation, 0)
        GLES30.glUniform4f(
            effectsLocation,
            frame.iridescence,
            frame.sweep,
            frame.streaks,
            reflectionOpacity
        )
        GLES30.glFrontFace(frontFace)
        for (culledFace in intArrayOf(GLES30.GL_FRONT, GLES30.GL_BACK)) {
            GLES30.glCullFace(culledFace)
            GLES30.glDrawElements(GLES30.GL_TRIANGLES, indexCount, GLES30.GL_UNSIGNED_INT, 0)
        }
    }

    private fun bindBackdrop(bitmap: Bitmap?): Boolean {
        if (bitmap == null || bitmap.isRecycled) return false
        if (backdropTexture == 0) {
            val textures = IntArray(1)
            GLES30.glGenTextures(1, textures, 0)
            backdropTexture = textures[0]
            GLES30.glBindTexture(GLES30.GL_TEXTURE_2D, backdropTexture)
            val linear = GLES30.GL_LINEAR
            val clamp = GLES30.GL_CLAMP_TO_EDGE
            GLES30.glTexParameteri(GLES30.GL_TEXTURE_2D, GLES30.GL_TEXTURE_MIN_FILTER, linear)
            GLES30.glTexParameteri(GLES30.GL_TEXTURE_2D, GLES30.GL_TEXTURE_MAG_FILTER, linear)
            GLES30.glTexParameteri(GLES30.GL_TEXTURE_2D, GLES30.GL_TEXTURE_WRAP_S, clamp)
            GLES30.glTexParameteri(GLES30.GL_TEXTURE_2D, GLES30.GL_TEXTURE_WRAP_T, clamp)
        }
        GLES30.glActiveTexture(GLES30.GL_TEXTURE0)
        GLES30.glBindTexture(GLES30.GL_TEXTURE_2D, backdropTexture)
        if (uploadedBackdrop !== bitmap) {
            GLUtils.texImage2D(GLES30.GL_TEXTURE_2D, 0, bitmap, 0)
            uploadedBackdrop = bitmap
        }
        GLES30.glUniform1i(backdropTextureLocation, 0)
        return true
    }

    private fun prepareContext(): Boolean {
        if (context != EGL14.EGL_NO_CONTEXT) return true
        display = EGL14.eglGetDisplay(EGL14.EGL_DEFAULT_DISPLAY)
        if (display == EGL14.EGL_NO_DISPLAY) return false
        val version = IntArray(2)
        if (!EGL14.eglInitialize(display, version, 0, version, 1)) return false
        // Multisampled where the device offers it, for edges as smooth as iOS's
        config = chooseConfig(samples = 4) ?: chooseConfig(samples = 0) ?: return false
        context = EGL14.eglCreateContext(
            display,
            config,
            EGL14.EGL_NO_CONTEXT,
            intArrayOf(EGL14.EGL_CONTEXT_CLIENT_VERSION, 3, EGL14.EGL_NONE),
            0
        )
        return context != EGL14.EGL_NO_CONTEXT
    }

    private fun chooseConfig(samples: Int): EGLConfig? {
        val attributes = mutableListOf(
            EGL14.EGL_RED_SIZE, 8,
            EGL14.EGL_GREEN_SIZE, 8,
            EGL14.EGL_BLUE_SIZE, 8,
            EGL14.EGL_ALPHA_SIZE, 8,
            EGL14.EGL_DEPTH_SIZE, 16,
            EGL14.EGL_RENDERABLE_TYPE, EGL_OPENGL_ES3_BIT,
            EGL14.EGL_SURFACE_TYPE, EGL14.EGL_WINDOW_BIT
        )
        if (samples > 0) {
            attributes += listOf(EGL14.EGL_SAMPLE_BUFFERS, 1, EGL14.EGL_SAMPLES, samples)
        }
        attributes += EGL14.EGL_NONE
        val configs = arrayOfNulls<EGLConfig>(1)
        val count = IntArray(1)
        val isChosen = EGL14.eglChooseConfig(
            display,
            attributes.toIntArray(),
            0,
            configs,
            0,
            1,
            count,
            0
        )
        return configs[0]?.takeIf { isChosen && count[0] > 0 }
    }

    private fun prepareResources(): Boolean {
        val linked = linkProgram(VERTEX_SHADER, FRAGMENT_SHADER) { linking ->
            GLES30.glBindAttribLocation(linking, POSITION_ATTRIBUTE, "aPosition")
            GLES30.glBindAttribLocation(linking, NORMAL_ATTRIBUTE, "aNormal")
        }
        val linkedGround = linkProgram(GROUND_VERTEX_SHADER, GROUND_FRAGMENT_SHADER)
        if (linked == 0 || linkedGround == 0) return false
        effectsLocation = GLES30.glGetUniformLocation(linked, "uEffects")
        groundCameraLocation = GLES30.glGetUniformLocation(linkedGround, "uCamera")
        groundPlacementLocation = GLES30.glGetUniformLocation(linkedGround, "uPlacement")
        groundSizeLocation = GLES30.glGetUniformLocation(linkedGround, "uSize")
        groundBodyLocation = GLES30.glGetUniformLocation(linkedGround, "uBody")
        groundShadowLocation = GLES30.glGetUniformLocation(linkedGround, "uShadow")
        groundColorLocation = GLES30.glGetUniformLocation(linkedGround, "uColor")
        // The ground's corners come from the vertex index, with no attributes
        val groundArrays = IntArray(1)
        GLES30.glGenVertexArrays(1, groundArrays, 0)
        groundVertexArray = groundArrays[0]
        groundProgram = linkedGround
        rotationLocation = GLES30.glGetUniformLocation(linked, "uRotation")
        placementLocation = GLES30.glGetUniformLocation(linked, "uPlacement")
        sizeLocation = GLES30.glGetUniformLocation(linked, "uSize")
        materialLocation = GLES30.glGetUniformLocation(linked, "uMaterial")
        boxCenterLocation = GLES30.glGetUniformLocation(linked, "uBoxCenter")
        backdropLocation = GLES30.glGetUniformLocation(linked, "uBackdrop")
        backdropRectLocation = GLES30.glGetUniformLocation(linked, "uBackdropRect")
        hasBackdropLocation = GLES30.glGetUniformLocation(linked, "uHasBackdrop")
        backdropTextureLocation = GLES30.glGetUniformLocation(linked, "uBackdropTexture")

        val mesh = AgentSpinningTopGeometry.buildMesh()
        val buffers = IntArray(2)
        GLES30.glGenBuffers(2, buffers, 0)
        val arrays = IntArray(1)
        GLES30.glGenVertexArrays(1, arrays, 0)
        GLES30.glBindVertexArray(arrays[0])
        GLES30.glBindBuffer(GLES30.GL_ARRAY_BUFFER, buffers[0])
        val vertices = ByteBuffer.allocateDirect(mesh.vertices.size * Float.SIZE_BYTES)
            .order(ByteOrder.nativeOrder())
        vertices.asFloatBuffer().put(mesh.vertices)
        GLES30.glBufferData(
            GLES30.GL_ARRAY_BUFFER,
            vertices.capacity(),
            vertices,
            GLES30.GL_STATIC_DRAW
        )
        val stride = AgentSpinningTopGeometry.FLOATS_PER_VERTEX * Float.SIZE_BYTES
        GLES30.glEnableVertexAttribArray(POSITION_ATTRIBUTE)
        GLES30.glVertexAttribPointer(POSITION_ATTRIBUTE, 3, GLES30.GL_FLOAT, false, stride, 0)
        GLES30.glEnableVertexAttribArray(NORMAL_ATTRIBUTE)
        GLES30.glVertexAttribPointer(
            NORMAL_ATTRIBUTE,
            3,
            GLES30.GL_FLOAT,
            false,
            stride,
            3 * Float.SIZE_BYTES
        )
        GLES30.glBindBuffer(GLES30.GL_ELEMENT_ARRAY_BUFFER, buffers[1])
        val indices = ByteBuffer.allocateDirect(mesh.indices.size * Int.SIZE_BYTES)
            .order(ByteOrder.nativeOrder())
        indices.asIntBuffer().put(mesh.indices)
        GLES30.glBufferData(
            GLES30.GL_ELEMENT_ARRAY_BUFFER,
            indices.capacity(),
            indices,
            GLES30.GL_STATIC_DRAW
        )
        GLES30.glBindVertexArray(0)
        indexCount = mesh.indices.size
        vertexArray = arrays[0]
        program = linked
        return GLES30.glGetError() == GLES30.GL_NO_ERROR
    }

    private fun linkProgram(
        vertexSource: String,
        fragmentSource: String,
        bindAttributes: (Int) -> Unit = {}
    ): Int {
        val vertexShader = compileShader(GLES30.GL_VERTEX_SHADER, vertexSource)
        val fragmentShader = compileShader(GLES30.GL_FRAGMENT_SHADER, fragmentSource)
        if (vertexShader == 0 || fragmentShader == 0) return 0
        val linked = GLES30.glCreateProgram()
        GLES30.glAttachShader(linked, vertexShader)
        GLES30.glAttachShader(linked, fragmentShader)
        bindAttributes(linked)
        GLES30.glLinkProgram(linked)
        GLES30.glDeleteShader(vertexShader)
        GLES30.glDeleteShader(fragmentShader)
        val status = IntArray(1)
        GLES30.glGetProgramiv(linked, GLES30.GL_LINK_STATUS, status, 0)
        if (status[0] == 0) {
            GLES30.glDeleteProgram(linked)
            return 0
        }
        return linked
    }

    private fun compileShader(type: Int, source: String): Int {
        val shader = GLES30.glCreateShader(type)
        if (shader == 0) return 0
        GLES30.glShaderSource(shader, source)
        GLES30.glCompileShader(shader)
        val status = IntArray(1)
        GLES30.glGetShaderiv(shader, GLES30.GL_COMPILE_STATUS, status, 0)
        if (status[0] == 0) {
            GLES30.glDeleteShader(shader)
            return 0
        }
        return shader
    }

    private fun destroySurface(target: Target) {
        if (target.eglSurface == EGL14.EGL_NO_SURFACE) return
        EGL14.eglMakeCurrent(
            display,
            EGL14.EGL_NO_SURFACE,
            EGL14.EGL_NO_SURFACE,
            EGL14.EGL_NO_CONTEXT
        )
        EGL14.eglDestroySurface(display, target.eglSurface)
        target.eglSurface = EGL14.EGL_NO_SURFACE
    }

    private fun releaseTarget(target: Target) {
        destroySurface(target)
        target.surfaceTexture.release()
    }

    private fun fail() {
        hasFailed = true
    }

    private const val POSITION_ATTRIBUTE = 0
    private const val NORMAL_ATTRIBUTE = 1
    private const val HIGHLIGHT_BOOST = 0.25f
    private const val MAX_CONTEXT_LOSSES = 3

    /**
     * The ground under a large top: a contact spot under the point and a soft shadow of the body under its rim, as
     * strong as these, the body's this wide in model units, and the reflection in the ground this strong at the point
     */
    private class GroundLook(
        val contact: Float,
        val body: Float,
        val radius: Float,
        val isGlow: Boolean,
        val color: FloatArray,
        val reflection: Float
    )

    private val lightGround = GroundLook(0.5f, 0.16f, 0.3f, false, floatArrayOf(0f, 0f, 0f), 0.45f)

    // On dark, where a shadow can't darken anything, a faint blue glow pools there instead
    private val darkGround =
        GroundLook(0.35f, 0.16f, 0.32f, true, floatArrayOf(0.2f, 0.5f, 1f), 0.6f)

    private const val VERTEX_SHADER = """#version 300 es
layout(location = 0) in vec3 aPosition;
layout(location = 1) in vec3 aNormal;
uniform mat4 uRotation;
// xy: the model's origin in pixels, y up; z: pixels per model unit
uniform vec3 uPlacement;
uniform vec2 uSize;
// w: the reflection's opacity, while the reflection is drawn
uniform vec4 uEffects;
out vec3 vViewPosition;
out vec3 vModelPosition;
out vec3 vModelNormal;

void main() {
    vec3 viewPosition = (uRotation * vec4(aPosition, 1.0)).xyz;
    vec2 pixel = uPlacement.xy + viewPosition.xy * uPlacement.z;
    // The top takes the nearer half of the depth range and its reflection the farther, so the top
    // always draws over its reflection, each hiding its own far side
    float depth = -viewPosition.z * 0.5;
    gl_Position = vec4(
        pixel / uSize * 2.0 - 1.0,
        uEffects.w > 0.0 ? 0.5 + 0.5 * depth : 0.5 * depth - 0.5,
        1.0
    );
    vViewPosition = viewPosition;
    vModelPosition = aPosition;
    vModelNormal = aNormal;
}
"""

    private const val FRAGMENT_SHADER = """#version 300 es
precision highp float;
uniform mat4 uRotation;
// x: hold strength 0…1; y: dark appearance; z: highlight boost
uniform vec3 uMaterial;
// The box's center relative to the model's origin, in view units
uniform vec2 uBoxCenter;
// The color behind the top
uniform vec3 uBackdrop;
// xy: the model's origin in pixels, y up; z: pixels per model unit
uniform vec3 uPlacement;
uniform vec2 uSize;
// The content captured behind a grown top, where uHasBackdrop is 1
uniform sampler2D uBackdropTexture;
// Where the captured content lies in the canvas, in pixels, y down: origin, size
uniform vec4 uBackdropRect;
uniform float uHasBackdrop;
// x: the thin film, 0…1; y: the angle the body turns during an exposure, radians; z: the rings of
// a fast spin, 0…1; w: the reflection's opacity, while the reflection is drawn
uniform vec4 uEffects;
in vec3 vViewPosition;
in vec3 vModelPosition;
in vec3 vModelNormal;
out vec4 fragColor;

vec3 computeGradient(float t) {
    vec3 c0 = vec3(0.0, 0.533, 1.0);
    vec3 c1 = vec3(0.0, 0.745, 1.0);
    vec3 c2 = vec3(0.714, 0.337, 1.0);
    return t < 0.476 ? mix(c0, c1, t / 0.476) : mix(c1, c2, (t - 0.476) / 0.524);
}

// The thin film's colors, cyclic in t: cyan, blue, violet and a short touch of pink, each blended
// into the next
vec3 computeFilm(float t) {
    vec3 cyan = vec3(0.0, 0.86, 1.0);
    vec3 blue = vec3(0.10, 0.45, 1.0);
    vec3 violet = vec3(0.58, 0.36, 1.0);
    vec3 pink = vec3(0.98, 0.50, 0.92);
    t = fract(t);
    if (t < 0.30) return mix(cyan, blue, smoothstep(0.0, 0.30, t));
    if (t < 0.60) return mix(blue, violet, smoothstep(0.30, 0.60, t));
    if (t < 0.75) return mix(violet, pink, smoothstep(0.60, 0.75, t));
    return mix(pink, cyan, smoothstep(0.75, 1.0, t));
}

// How much of its contrast a pattern of k cycles per turn keeps, averaged over a sweep of delta
// radians as the body turns during an exposure: 1 when nothing blurs
float computeSweepKept(float k, float delta) {
    float x = 0.5 * k * delta;
    return x < 1e-4 ? 1.0 : sin(x) / x;
}

// The reflection in the ground fades with height, strongest at the point and gone by the rim; the
// top itself is whole
vec4 fadeReflection(vec4 color) {
    return uEffects.w > 0.0 ? color * uEffects.w * exp(-5.0 * max(vModelPosition.y, 0.0)) : color;
}

// A broad soft window above and a cool fill below, as a matte surface blurs them
vec3 computeStudio(vec3 d) {
    float window = smoothstep(0.2, 0.95, d.y) * (0.55 + 0.45 * smoothstep(-0.7, 0.5, -d.x));
    float fill = smoothstep(-0.1, -0.9, d.y) * 0.2;
    return vec3(1.0) * window + vec3(0.55, 0.75, 1.0) * fill;
}

// The content behind the top seen through frosted glass: a disc of samples around `position`, in
// canvas pixels, y down, spread by `radius` pixels on a golden-angle spiral
vec3 computeFrosted(vec2 position, float radius) {
    vec3 sum = vec3(0.0);
    for (int i = 0; i < 10; i++) {
        float r = radius * sqrt((float(i) + 0.5) / 10.0);
        float a = float(i) * 2.39996;
        vec2 uv = (position + r * vec2(cos(a), sin(a)) - uBackdropRect.xy) / uBackdropRect.zw;
        sum += texture(uBackdropTexture, uv).rgb;
    }
    return sum / 10.0;
}

// A hollow top of frosted glass with a colored coating sprayed on: thin where the shell faces
// the viewer, so what is behind shows through tinted, dense where the shell turns away, and
// soft, matte highlights. The back wall draws first, the front over it.
void main() {
    float strength = clamp(uMaterial.x, 0.0, 1.0);
    bool isDark = uMaterial.y > 0.5;

    // A smooth shell without facets. Soft twisted bands in the coating turn with the body and
    // show the spin; they fade out toward the thin stem and the point, where they would flicker.
    vec3 modelNormal = normalize(vModelNormal);
    float radial = length(vModelPosition.xz);
    float azimuth = atan(vModelPosition.z, vModelPosition.x);
    float swirl = sin(2.0 * azimuth + vModelPosition.y * 4.0) * smoothstep(0.08, 0.3, radial)
        * computeSweepKept(2.0, uEffects.y);

    vec3 outward = normalize((uRotation * vec4(modelNormal, 0.0)).xyz);
    // The side of the shell that faces the viewer: the outside of the front wall, the inside of
    // the back wall
    vec3 n = gl_FrontFacing ? outward : -outward;
    vec3 v = vec3(0.0, 0.0, 1.0);
    float grazing = 1.0 - clamp(n.z, 0.0, 1.0);
    float fresnel = pow(grazing, 2.2);

    vec2 fromCenter = vViewPosition.xy - uBoxCenter;
    float t = clamp(dot(fromCenter, vec2(0.96, -0.27)) * 0.55 + 0.5 + 0.07 * swirl, 0.0, 1.0);
    vec3 base = computeGradient(t);
    // The coating is a little uneven, as sprayed on
    float coatDensity = 1.0 + 0.12 * swirl;

    // A thin film over the coating, shifting through its colors as the top turns and toward the
    // silhouette
    float iridescence = clamp(uEffects.x, 0.0, 1.0);
    float thickness = 0.45
        + 0.22 * sin(azimuth + 3.0 * vModelPosition.y) * computeSweepKept(1.0, uEffects.y)
        + 0.12 * sin(3.0 * azimuth - 5.0 * vModelPosition.y) * computeSweepKept(3.0, uEffects.y);
    vec3 film = computeFilm(thickness + 0.55 * grazing);

    vec3 light = normalize(vec3(-0.45, 0.75, 0.5));
    float diffuse = 0.7 + 0.3 * clamp(dot(n, light), 0.0, 1.0);
    float halfway = clamp(dot(n, normalize(light + v)), 0.0, 1.0);
    // Frosted glass scatters its highlights: wide and soft, no sharp glint
    float sheen = (pow(halfway, 10.0) * 0.16 + pow(halfway, 36.0) * 0.12) * (1.0 + uMaterial.z);

    if (!gl_FrontFacing) {
        // The back wall, seen through the hollow: what is behind, tinted by the coating it passes,
        // which gathers where the wall turns away, under a milky veil
        float wall = mix(isDark ? 0.2 : 0.16, 0.55, fresnel) * coatDensity
            * mix(1.0, 0.7, strength);
        vec3 wallColor = mix(base * (isDark ? 0.78 : 0.9), film, 0.35 * iridescence * fresnel);
        vec3 transmittance = mix(vec3(1.0), base, 0.55);
        float veil = isDark ? 0.05 : 0.1;
        if (uHasBackdrop > 0.5) {
            // The captured content, frosted and bent a little where the thin shell turns away,
            // magnified a little more while held. The lens centers on the box, the model's origin
            // being its point.
            vec2 pixel = vec2(gl_FragCoord.x, uSize.y - gl_FragCoord.y);
            vec2 center = vec2(
                uPlacement.x + uBoxCenter.x * uPlacement.z,
                uSize.y - (uPlacement.y + uBoxCenter.y * uPlacement.z)
            );
            float lens = mix(0.4, 1.0, strength);
            vec2 bend = vec2(-outward.x, outward.y) * uPlacement.z * 0.28 * grazing * grazing * lens;
            vec2 samplePosition = center + (pixel - center) * (1.0 - 0.13 * lens) + bend;
            float frost = uPlacement.z * mix(0.034, 0.022, strength);
            vec3 behind = computeFrosted(samplePosition, frost);
            vec3 shown = mix(behind * transmittance, vec3(isDark ? 0.75 : 1.0), veil);
            fragColor = fadeReflection(vec4(mix(shown, wallColor, wall), 1.0));
            return;
        }
        vec3 transmitted = mix(uBackdrop * transmittance, vec3(isDark ? 0.75 : 1.0), veil);
        vec3 seen = mix(transmitted, wallColor, wall);
        // The share of what is behind that still shows: over the backdrop's color the wall shows
        // exactly `seen`
        float clearest = min(transmittance.r, min(transmittance.g, transmittance.b));
        float clearness = (1.0 - wall) * (1.0 - veil) * clearest;
        float opacity = 1.0 - clearness;
        fragColor = fadeReflection(vec4(clamp(seen - uBackdrop * clearness, 0.0, opacity), opacity));
        return;
    }

    // The front wall: a thin colored coat over the hollow, denser toward the silhouette, with the
    // matte sheen and a soft rim where the frosted surface scatters the light around it
    vec3 coat = mix(base * diffuse, film, iridescence * (0.18 + 0.5 * fresnel));
    coat += computeStudio(reflect(-v, n)) * (0.06 + 0.22 * fresnel);
    coat = mix(coat, vec3(1.0), fresnel * (isDark ? 0.18 : 0.24));
    vec3 sheenColor = mix(vec3(1.0), film, 0.7 * iridescence);
    // A fast spin smears the surface into fine rings around the body
    float band = 46.0 * vModelPosition.y + 1.7 * sin(13.0 * vModelPosition.y);
    float rings = pow(0.5 + 0.5 * sin(band), 6.0) * smoothstep(0.08, 0.3, radial)
        * clamp(uEffects.z, 0.0, 1.0);
    coat = clamp(coat + sheenColor * sheen * (1.0 + 0.8 * iridescence) + 0.35 * rings, 0.0, 1.0);
    float facing = mix(isDark ? 0.34 : 0.3, 0.16, strength);
    float coverage = mix(facing, 0.82, smoothstep(0.05, 0.95, grazing));
    float opacity = clamp(coverage * coatDensity + sheen + 0.12 * rings, 0.0, 1.0);
    vec4 color = vec4(coat * opacity, opacity);
    // A rim light along the silhouette in the film's colors: added light on dark, a tint on light,
    // where added light wouldn't show
    float rim = pow(grazing, 3.5) * iridescence;
    if (isDark) {
        color.rgb += film * rim * 0.9;
    } else {
        color.rgb = mix(color.rgb, film * color.a, clamp(0.8 * rim, 0.0, 1.0));
    }
    fragColor = fadeReflection(color);
}
"""

    // The ground under a large top, in the plane through its point, seen from the camera alone
    private const val GROUND_VERTEX_SHADER = """#version 300 es
uniform mat4 uCamera;
// xy: the top's point in pixels, y up; z: pixels per model unit
uniform vec3 uPlacement;
uniform vec2 uSize;
out vec2 vGround;

void main() {
    vec2 ground = vec2(gl_VertexID % 2 == 0 ? -1.6 : 1.6, gl_VertexID < 2 ? -1.6 : 1.6);
    vec3 viewPosition = (uCamera * vec4(ground.x, 0.0, ground.y, 1.0)).xyz;
    vec2 pixel = uPlacement.xy + viewPosition.xy * uPlacement.z;
    gl_Position = vec4(pixel / uSize * 2.0 - 1.0, 0.0, 1.0);
    vGround = ground;
}
"""

    // A contact spot under the point and a soft shadow of the body under its rim, which follows the
    // lean. On dark, where a shadow can't darken anything, it pools faint light.
    private const val GROUND_FRAGMENT_SHADER = """#version 300 es
precision highp float;
// The ground point under the rim's center, model x and z
uniform vec2 uBody;
// x: the contact spot's strength; y: the body's; z: the body's radius, model units; w: a glow
uniform vec4 uShadow;
uniform vec3 uColor;
in vec2 vGround;
out vec4 fragColor;

void main() {
    float contact = exp(-dot(vGround, vGround) / (2.0 * 0.045 * 0.045));
    vec2 fromBody = vGround - uBody;
    float body = exp(-dot(fromBody, fromBody) / (2.0 * uShadow.z * uShadow.z));
    float amount = clamp(uShadow.x * contact + uShadow.y * body, 0.0, 1.0);
    // Premultiplied: a shadow darkens what is behind, a glow adds light to it
    fragColor = uShadow.w > 0.5 ? vec4(uColor * amount, 0.0) : vec4(uColor * amount, amount);
}
"""
}
