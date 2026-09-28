package org.mytonwallet.app_air.uicomponents.helpers

import android.content.Context
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.os.SystemClock
import android.view.Choreographer
import android.view.Surface
import android.view.WindowManager
import kotlin.math.abs
import kotlin.math.asin
import kotlin.math.exp
import org.mytonwallet.app_air.walletbasecontext.utils.ApplicationContextHolder

object TiltSensorManager {
    interface TiltObserver {
        fun onTilt(x: Float, y: Float, pitch: Float, roll: Float, recentered: Boolean)
    }

    private val observers = mutableSetOf<TiltObserver>()

    private var sensorManager: SensorManager? = null
    private var sensor: Sensor? = null
    private var usesRotationVector = false
    private val windowManager by lazy {
        ApplicationContextHolder.applicationContext.getSystemService(
            Context.WINDOW_SERVICE
        ) as? WindowManager
    }
    private var isListening = false
    private var appPaused = false

    private const val UPDATE_INTERVAL_US = 33_333
    private const val MIN_FRAME_INTERVAL_NANOS = 16_000_000L
    private const val TILT_RESPONSE_SECONDS = 0.1f
    private const val START_THRESHOLD = 0.005f
    private const val SETTLED_THRESHOLD = 0.0005f
    private const val CONTINUE_TILT_WINDOW_MS = 10_000L

    private var lastX = 0f
    private var lastY = 0f
    private var lastPitch = 0f
    private var lastRoll = 0f
    private var targetX = 0f
    private var targetY = 0f
    private var targetPitch = 0f
    private var targetRoll = 0f
    private var needsRebase = true
    private var referenceX: Float? = null
    private var referenceY: Float? = null
    private var smoothedX = 0f
    private var smoothedY = 0f
    private var smoothedPitch = 0f
    private var smoothedRoll = 0f
    private var lastRotation = -1
    private var stoppedAt = 0L
    private val quaternion = FloatArray(4)
    private var referenceQuaternion: FloatArray? = null
    private var framePosted = false
    private var lastFrameNanos = 0L
    private val frameCallback = Choreographer.FrameCallback { frameTimeNanos ->
        framePosted = false
        if (lastFrameNanos != 0L && frameTimeNanos - lastFrameNanos < MIN_FRAME_INTERVAL_NANOS) {
            scheduleFrame()
            return@FrameCallback
        }
        val dt = if (lastFrameNanos == 0L) {
            1f / 60f
        } else {
            ((frameTimeNanos - lastFrameNanos) / 1_000_000_000f).coerceIn(0f, 0.1f)
        }
        lastFrameNanos = frameTimeNanos
        val smoothing = 1f - exp(-dt / TILT_RESPONSE_SECONDS)
        smoothedX += (targetX - smoothedX) * smoothing
        smoothedY += (targetY - smoothedY) * smoothing
        if (needsRebase) {
            smoothedPitch = targetPitch
            smoothedRoll = targetRoll
        } else {
            smoothedPitch += (targetPitch - smoothedPitch) * smoothing
            smoothedRoll += (targetRoll - smoothedRoll) * smoothing
        }
        val settled = abs(targetX - smoothedX) < SETTLED_THRESHOLD &&
            abs(targetY - smoothedY) < SETTLED_THRESHOLD &&
            abs(targetPitch - smoothedPitch) < SETTLED_THRESHOLD &&
            abs(targetRoll - smoothedRoll) < SETTLED_THRESHOLD
        if (settled) {
            smoothedX = targetX
            smoothedY = targetY
            smoothedPitch = targetPitch
            smoothedRoll = targetRoll
        }
        val tiltX = smoothedX.coerceIn(-1f, 1f)
        val tiltY = smoothedY.coerceIn(-1f, 1f)
        if (needsRebase ||
            abs(tiltX - lastX) >= SETTLED_THRESHOLD ||
            abs(tiltY - lastY) >= SETTLED_THRESHOLD ||
            abs(smoothedPitch - lastPitch) >= SETTLED_THRESHOLD ||
            abs(smoothedRoll - lastRoll) >= SETTLED_THRESHOLD
        ) {
            lastX = tiltX
            lastY = tiltY
            lastPitch = smoothedPitch
            lastRoll = smoothedRoll
            observers.forEach { it.onTilt(tiltX, tiltY, smoothedPitch, smoothedRoll, needsRebase) }
            needsRebase = false
        }
        if (settled) {
            lastFrameNanos = 0L
        } else {
            scheduleFrame()
        }
    }

    private fun scheduleFrame() {
        if (framePosted || !isListening) return
        framePosted = true
        Choreographer.getInstance().postFrameCallback(frameCallback)
    }

    private fun cancelFrame() {
        if (framePosted) Choreographer.getInstance().removeFrameCallback(frameCallback)
        framePosted = false
        lastFrameNanos = 0L
    }

    private val sensorListener = object : SensorEventListener {
        override fun onSensorChanged(event: SensorEvent?) {
            event ?: return

            val rotation = windowManager?.defaultDisplay?.rotation ?: Surface.ROTATION_0
            if (rotation != lastRotation) {
                cancelFrame()
                referenceX = null
                referenceY = null
                referenceQuaternion = null
                smoothedX = 0f
                smoothedY = 0f
                smoothedPitch = 0f
                smoothedRoll = 0f
                targetX = 0f
                targetY = 0f
                targetPitch = 0f
                targetRoll = 0f
                lastPitch = 0f
                lastRoll = 0f
                needsRebase = true
                lastRotation = rotation
            }
            val (x, y) = if (usesRotationVector) {
                SensorManager.getQuaternionFromVector(quaternion, event.values)
                val reference = referenceQuaternion
                if (reference == null) {
                    referenceQuaternion = quaternion.copyOf()
                    return
                }
                val (w, qx, qy, qz) = quaternion
                val (rw, rx, ry, rz) = reference
                val relativeX = rw * qx - rx * w - ry * qz + rz * qy
                val relativeY = rw * qy + rx * qz - ry * w - rz * qx
                val relativeW = rw * w + rx * qx + ry * qy + rz * qz
                val sign = if (relativeW < 0) -1f else 1f
                val horizontal = 2f * asin((relativeY * sign).coerceIn(-1f, 1f))
                val vertical = 2f * asin((relativeX * sign).coerceIn(-1f, 1f))
                when (rotation) {
                    Surface.ROTATION_90 -> vertical to -horizontal
                    Surface.ROTATION_180 -> -horizontal to -vertical
                    Surface.ROTATION_270 -> -vertical to horizontal
                    else -> horizontal to vertical
                }
            } else {
                val (screenX, screenY) = when (rotation) {
                    Surface.ROTATION_90 -> event.values[1] to -event.values[0]
                    Surface.ROTATION_180 -> -event.values[0] to -event.values[1]
                    Surface.ROTATION_270 -> -event.values[1] to event.values[0]
                    else -> event.values[0] to event.values[1]
                }
                if (referenceX == null || referenceY == null) {
                    referenceX = screenX
                    referenceY = screenY
                    return
                }
                (screenX - referenceX!!) / 6f to (screenY - referenceY!!) / 6f
            }
            targetX = (x * if (usesRotationVector) 1.5f else 1f).coerceIn(-1f, 1f)
            targetY = (y * if (usesRotationVector) 1.5f else 1f).coerceIn(-1f, 1f)
            targetPitch = y
            targetRoll = x
            if (needsRebase ||
                abs(targetX - lastX) >= START_THRESHOLD ||
                abs(targetY - lastY) >= START_THRESHOLD ||
                abs(targetPitch - lastPitch) >= START_THRESHOLD ||
                abs(targetRoll - lastRoll) >= START_THRESHOLD
            ) {
                scheduleFrame()
            }
        }

        override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) {}
    }

    fun addObserver(observer: TiltObserver) {
        if (!observers.add(observer)) return
        start()
        observer.onTilt(lastX, lastY, lastPitch, lastRoll, true)
    }

    fun removeObserver(observer: TiltObserver) {
        observers.remove(observer)
        if (observers.isEmpty()) stop()
    }

    fun onAppPause() {
        appPaused = true
        stop()
        stoppedAt = 0L
    }

    fun onAppResume() {
        appPaused = false
        start()
    }

    private fun start() {
        if (appPaused ||
            isListening ||
            observers.isEmpty()
        ) {
            return
        }

        val context = ApplicationContextHolder.applicationContext
        sensorManager = context.getSystemService(Context.SENSOR_SERVICE) as? SensorManager
        sensor = sensorManager?.getDefaultSensor(Sensor.TYPE_GAME_ROTATION_VECTOR)
            ?: sensorManager?.getDefaultSensor(Sensor.TYPE_ROTATION_VECTOR)
            ?: sensorManager?.getDefaultSensor(Sensor.TYPE_ACCELEROMETER)
        usesRotationVector = sensor?.type == Sensor.TYPE_GAME_ROTATION_VECTOR ||
            sensor?.type == Sensor.TYPE_ROTATION_VECTOR
        sensor?.let {
            if (stoppedAt == 0L ||
                SystemClock.uptimeMillis() - stoppedAt > CONTINUE_TILT_WINDOW_MS
            ) {
                referenceX = null
                referenceY = null
                referenceQuaternion = null
                smoothedX = 0f
                smoothedY = 0f
                smoothedPitch = 0f
                smoothedRoll = 0f
                targetX = 0f
                targetY = 0f
                targetPitch = 0f
                targetRoll = 0f
                lastRotation = -1
                lastX = 0f
                lastY = 0f
                lastPitch = 0f
                lastRoll = 0f
                needsRebase = true
            }
            isListening = sensorManager?.registerListener(
                sensorListener,
                it,
                UPDATE_INTERVAL_US
            ) == true
        }
    }

    private fun stop() {
        if (!isListening) return
        sensorManager?.unregisterListener(sensorListener)
        isListening = false
        cancelFrame()
        stoppedAt = SystemClock.uptimeMillis()
    }
}
