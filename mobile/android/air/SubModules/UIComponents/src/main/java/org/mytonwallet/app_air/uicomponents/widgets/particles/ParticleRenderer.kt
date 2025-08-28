package org.mytonwallet.app_air.uicomponents.widgets.particles

import android.opengl.GLES20
import android.opengl.GLSurfaceView
import android.os.Handler
import android.os.Looper
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.nio.FloatBuffer
import java.util.concurrent.ConcurrentHashMap
import javax.microedition.khronos.egl.EGLConfig
import javax.microedition.khronos.opengles.GL10
import kotlin.math.cos
import kotlin.math.sin

class ParticleRenderer : GLSurfaceView.Renderer {

    private var program: Int = 0
    private val systems = ConcurrentHashMap<String, ParticleSystem>()
    private val handler = Handler(Looper.getMainLooper())

    // Attribute locations
    private var aStartPosition: Int = 0
    private var aVelocity: Int = 0
    private var aStartTime: Int = 0
    private var aLifetime: Int = 0
    private var aSize: Int = 0
    private var aBaseOpacity: Int = 0

    // Uniform locations
    private var uResolution: Int = 0
    private var uTime: Int = 0
    private var uColor: Int = 0
    private var uCanvasWidth: Int = 0
    private var uCanvasHeight: Int = 0
    private var uAccelerationFactor: Int = 0
    private var uFadeInTime: Int = 0
    private var uFadeOutTime: Int = 0
    private var uEdgeFadeZone: Int = 0
    private var uRotationMatrices: Int = 0
    private var uSpawnCenter: Int = 0

    private var width: Int = 0
    private var height: Int = 0
    private var dpr: Float = 1f

    private var rotationMatricesBuffer: FloatBuffer? = null
    private var bgRed: Float = 0f
    private var bgGreen: Float = 0f
    private var bgBlue: Float = 0f
    private var bgAlpha: Float = 0f

    fun setDisplayDensity(density: Float) {
        dpr = density
    }

    fun setBackgroundColor(r: Float, g: Float, b: Float, a: Float) {
        bgRed = r
        bgGreen = g
        bgBlue = b
        bgAlpha = a
        GLES20.glClearColor(bgRed, bgGreen, bgBlue, bgAlpha)
    }

    override fun onSurfaceCreated(gl: GL10?, config: EGLConfig?) {
        GLES20.glClearColor(bgRed, bgGreen, bgBlue, bgAlpha)

        val vertexShader = loadShader(GLES20.GL_VERTEX_SHADER, ParticleShaders.VERTEX_SHADER)
        val fragmentShader = loadShader(GLES20.GL_FRAGMENT_SHADER, ParticleShaders.FRAGMENT_SHADER)

        program = GLES20.glCreateProgram()
        GLES20.glAttachShader(program, vertexShader)
        GLES20.glAttachShader(program, fragmentShader)
        GLES20.glLinkProgram(program)

        val linkStatus = IntArray(1)
        GLES20.glGetProgramiv(program, GLES20.GL_LINK_STATUS, linkStatus, 0)
        if (linkStatus[0] == 0) {
            throw RuntimeException("Failed to link program: ${GLES20.glGetProgramInfoLog(program)}")
        }

        // Get attribute locations
        aStartPosition = GLES20.glGetAttribLocation(program, "a_startPosition")
        aVelocity = GLES20.glGetAttribLocation(program, "a_velocity")
        aStartTime = GLES20.glGetAttribLocation(program, "a_startTime")
        aLifetime = GLES20.glGetAttribLocation(program, "a_lifetime")
        aSize = GLES20.glGetAttribLocation(program, "a_size")
        aBaseOpacity = GLES20.glGetAttribLocation(program, "a_baseOpacity")

        // Get uniform locations
        uResolution = GLES20.glGetUniformLocation(program, "u_resolution")
        uTime = GLES20.glGetUniformLocation(program, "u_time")
        uColor = GLES20.glGetUniformLocation(program, "u_color")
        uCanvasWidth = GLES20.glGetUniformLocation(program, "u_canvasWidth")
        uCanvasHeight = GLES20.glGetUniformLocation(program, "u_canvasHeight")
        uAccelerationFactor = GLES20.glGetUniformLocation(program, "u_accelerationFactor")
        uFadeInTime = GLES20.glGetUniformLocation(program, "u_fadeInTime")
        uFadeOutTime = GLES20.glGetUniformLocation(program, "u_fadeOutTime")
        uEdgeFadeZone = GLES20.glGetUniformLocation(program, "u_edgeFadeZone")
        uRotationMatrices = GLES20.glGetUniformLocation(program, "u_rotationMatrices")
        uSpawnCenter = GLES20.glGetUniformLocation(program, "u_spawnCenter")

        // Initialize rotation matrices
        initRotationMatrices()

        GLES20.glEnable(GLES20.GL_BLEND)
        GLES20.glBlendFunc(GLES20.GL_ONE, GLES20.GL_ONE_MINUS_SRC_ALPHA)
    }

    override fun onSurfaceChanged(gl: GL10?, width: Int, height: Int) {
        this.width = width
        this.height = height
        GLES20.glViewport(0, 0, width, height)
    }

    override fun onDrawFrame(gl: GL10?) {
        GLES20.glClear(GLES20.GL_COLOR_BUFFER_BIT)

        if (systems.isEmpty()) return

        GLES20.glUseProgram(program)

        // Set static uniforms
        GLES20.glUniform2f(uResolution, width.toFloat(), height.toFloat())
        rotationMatricesBuffer?.let {
            GLES20.glUniformMatrix2fv(uRotationMatrices, 18, false, it)
        }

        val currentTime = System.currentTimeMillis()

        systems.values.forEach { system ->
            val systemTime = (currentTime - system.startTime) / 1000f

            // Set uniforms for this system
            GLES20.glUniform1f(uTime, systemTime)
            GLES20.glUniform3fv(uColor, 1, system.config.color, 0)
            GLES20.glUniform1f(uCanvasWidth, system.config.width * dpr)
            GLES20.glUniform1f(uCanvasHeight, system.config.height * dpr)
            GLES20.glUniform1f(uAccelerationFactor, system.config.accelerationFactor)
            GLES20.glUniform1f(uFadeInTime, system.config.fadeInTime)
            GLES20.glUniform1f(uFadeOutTime, system.config.fadeOutTime)
            GLES20.glUniform1f(uEdgeFadeZone, system.config.edgeFadeZone * dpr)
            GLES20.glUniform2f(uSpawnCenter, system.centerX * dpr, system.centerY * dpr)

            // Bind attributes for this system
            bindAttribute(aStartPosition, 2, system.startPositionBuffer)
            bindAttribute(aVelocity, 2, system.velocityBuffer)
            bindAttribute(aStartTime, 1, system.startTimeBuffer)
            bindAttribute(aLifetime, 1, system.lifetimeBuffer)
            bindAttribute(aSize, 1, system.sizeBuffer)
            bindAttribute(aBaseOpacity, 1, system.baseOpacityBuffer)

            // Draw particles
            GLES20.glDrawArrays(GLES20.GL_POINTS, 0, system.config.particleCount)
        }
    }

    private fun bindAttribute(location: Int, size: Int, buffer: FloatBuffer) {
        GLES20.glEnableVertexAttribArray(location)
        GLES20.glVertexAttribPointer(location, size, GLES20.GL_FLOAT, false, 0, buffer)
    }

    private fun loadShader(type: Int, shaderCode: String): Int {
        val shader = GLES20.glCreateShader(type)
        GLES20.glShaderSource(shader, shaderCode)
        GLES20.glCompileShader(shader)

        val compileStatus = IntArray(1)
        GLES20.glGetShaderiv(shader, GLES20.GL_COMPILE_STATUS, compileStatus, 0)
        if (compileStatus[0] == 0) {
            throw RuntimeException("Failed to compile shader: ${GLES20.glGetShaderInfoLog(shader)}")
        }

        return shader
    }

    private fun initRotationMatrices() {
        val rotationCount = 18
        val rotationAngleDegrees = 220f
        val matrices = FloatArray(rotationCount * 4) // mat2 = 4 floats

        for (i in 0 until rotationCount) {
            val angle = (rotationAngleDegrees * Math.PI / 180f * i).toFloat()
            val cos = cos(angle)
            val sin = sin(angle)

            // mat2 in column-major order: [cos, sin, -sin, cos]
            matrices[i * 4] = cos
            matrices[i * 4 + 1] = sin
            matrices[i * 4 + 2] = -sin
            matrices[i * 4 + 3] = cos
        }

        rotationMatricesBuffer = ByteBuffer.allocateDirect(matrices.size * 4)
            .order(ByteOrder.nativeOrder())
            .asFloatBuffer()
            .put(matrices)
            .apply { position(0) }
    }

    fun addSystem(config: ParticleConfig): String {
        val system = ParticleSystem(config = config)
        system.initializeBuffers(dpr)

        systems[system.id] = system

        if (config.selfDestroyTime > 0) {
            system.selfDestroyTimeout = Runnable {
                removeSystem(system.id)
            }
            handler.postDelayed(
                system.selfDestroyTimeout!!,
                (config.selfDestroyTime * 1000).toLong()
            )
        }

        return system.id
    }

    fun removeSystem(id: String) {
        systems[id]?.let { system ->
            system.selfDestroyTimeout?.let {
                handler.removeCallbacks(it)
            }
            systems.remove(id)
        }
    }

    fun clearAllSystems() {
        systems.values.forEach { system ->
            system.selfDestroyTimeout?.let {
                handler.removeCallbacks(it)
            }
        }
        systems.clear()
    }
}
