package org.mytonwallet.app_air.uicomponents.helpers

import android.content.Context
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.os.SystemClock
import android.view.Surface
import android.view.WindowManager
import kotlin.math.abs
import kotlin.math.asin
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

    private const val UPDATE_INTERVAL_MS = 33
    private const val TILT_THRESHOLD = 0.005f
    private const val CONTINUE_TILT_WINDOW_MS = 10_000L

    private var lastUpdateTime = 0L
    private var lastX = 0f
    private var lastY = 0f
    private var lastPitch = 0f
    private var lastRoll = 0f
    private var needsRebase = true
    private var referenceX: Float? = null
    private var referenceY: Float? = null
    private var smoothedX = 0f
    private var smoothedY = 0f
    private var lastRotation = -1
    private var stoppedAt = 0L
    private val quaternion = FloatArray(4)
    private var referenceQuaternion: FloatArray? = null

    private val sensorListener = object : SensorEventListener {
        override fun onSensorChanged(event: SensorEvent?) {
            event ?: return

            val now = System.currentTimeMillis()
            if (now - lastUpdateTime < UPDATE_INTERVAL_MS) return
            lastUpdateTime = now

            val rotation = windowManager?.defaultDisplay?.rotation ?: Surface.ROTATION_0
            if (rotation != lastRotation) {
                referenceX = null
                referenceY = null
                referenceQuaternion = null
                smoothedX = 0f
                smoothedY = 0f
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
            smoothedX += (x * (if (usesRotationVector) 1.5f else 1f) - smoothedX) * 0.25f
            smoothedY += (y * (if (usesRotationVector) 1.5f else 1f) - smoothedY) * 0.25f
            val tiltX = smoothedX.coerceIn(-1f, 1f)
            val tiltY = smoothedY.coerceIn(-1f, 1f)

            if (abs(tiltX - lastX) < TILT_THRESHOLD && abs(tiltY - lastY) < TILT_THRESHOLD) return
            lastX = tiltX
            lastY = tiltY
            lastPitch = y
            lastRoll = x

            observers.forEach { it.onTilt(tiltX, tiltY, y, x, needsRebase) }
            needsRebase = false
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
                lastRotation = -1
                lastX = 0f
                lastY = 0f
                lastPitch = 0f
                lastRoll = 0f
                needsRebase = true
            }
            lastUpdateTime = 0L
            isListening = sensorManager?.registerListener(
                sensorListener,
                it,
                UPDATE_INTERVAL_MS * 1000
            ) == true
        }
    }

    private fun stop() {
        if (!isListening) return
        sensorManager?.unregisterListener(sensorListener)
        isListening = false
        stoppedAt = SystemClock.uptimeMillis()
    }
}
