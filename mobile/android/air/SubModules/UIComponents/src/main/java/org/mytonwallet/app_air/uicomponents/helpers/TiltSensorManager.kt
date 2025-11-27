package org.mytonwallet.app_air.uicomponents.helpers

import android.content.Context
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import org.mytonwallet.app_air.walletbasecontext.utils.ApplicationContextHolder
import org.mytonwallet.app_air.walletcontext.helpers.DevicePerformanceClassifier
import kotlin.math.abs
import kotlin.math.pow

object TiltSensorManager {
    interface TiltObserver {
        fun onTilt(x: Float, y: Float)
    }

    private val observers = mutableSetOf<TiltObserver>()

    private var sensorManager: SensorManager? = null
    private var accelerometer: Sensor? = null
    private var isListening = false
    private var appPaused = false

    private const val UPDATE_INTERVAL_MS = 24
    private const val TILT_THRESHOLD = 0.05f

    private var lastUpdateTime = 0L
    private var lastX = 0f
    private var lastY = 0f
    private fun normalizedTilt(value: Float): Float {
        val normalized = (value / 9.8f).coerceIn(-1f, 1f)
        val power = 3f
        return normalized.pow(power)
    }

    private val sensorListener = object : SensorEventListener {
        override fun onSensorChanged(event: SensorEvent?) {
            event ?: return

            val now = System.currentTimeMillis()
            if (now - lastUpdateTime < UPDATE_INTERVAL_MS) return
            lastUpdateTime = now

            val x = normalizedTilt(event.values[0])
            val y = normalizedTilt(event.values[1])

            if (abs(x - lastX) < TILT_THRESHOLD && abs(y - lastY) < TILT_THRESHOLD) return
            lastX = x
            lastY = y

            observers.forEach { it.onTilt(x, y) }
        }

        override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) {}
    }

    fun addObserver(observer: TiltObserver) {
        observers.add(observer)
        start()
    }

    fun removeObserver(observer: TiltObserver) {
        observers.remove(observer)
        if (observers.isEmpty())
            stop()
    }

    fun onAppPause() {
        appPaused = true
        stop()
    }

    fun onAppResume() {
        appPaused = false
        start()
    }

    private fun start() {
        if (appPaused ||
            isListening ||
            observers.isEmpty() ||
            !DevicePerformanceClassifier.isHighClass
        ) return

        val context = ApplicationContextHolder.applicationContext
        sensorManager = context.getSystemService(Context.SENSOR_SERVICE) as? SensorManager
        accelerometer = sensorManager?.getDefaultSensor(Sensor.TYPE_ACCELEROMETER)
        accelerometer?.let {
            sensorManager?.registerListener(sensorListener, it, SensorManager.SENSOR_DELAY_UI)
            isListening = true
        }
    }

    private fun stop() {
        if (!isListening) return
        sensorManager?.unregisterListener(sensorListener)
        isListening = false
    }
}
