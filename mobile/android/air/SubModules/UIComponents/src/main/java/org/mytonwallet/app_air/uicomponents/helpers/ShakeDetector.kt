package org.mytonwallet.app_air.uicomponents.helpers

import android.content.Context
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import org.mytonwallet.app_air.walletbasecontext.utils.ApplicationContextHolder
import kotlin.math.sqrt

object ShakeDetector {
    var onShake: (() -> Unit)? = null

    private var sensorManager: SensorManager? = null
    private var accelerometer: Sensor? = null
    private var isListening = false
    private var appPaused = false

    private const val SHAKE_THRESHOLD_GRAVITY = 3.5f
    private const val MIN_INTERVAL_MS = 1000L
    private const val SAMPLE_INTERVAL_MS = 80L

    private var lastSampleTime = 0L
    private var lastShakeTime = 0L

    private val sensorListener = object : SensorEventListener {
        override fun onSensorChanged(event: SensorEvent?) {
            event ?: return
            val now = System.currentTimeMillis()
            if (now - lastSampleTime < SAMPLE_INTERVAL_MS) return
            lastSampleTime = now

            val x = event.values[0]
            val y = event.values[1]
            val z = event.values[2]
            val gForce = sqrt(x * x + y * y + z * z) / SensorManager.GRAVITY_EARTH
            if (gForce < SHAKE_THRESHOLD_GRAVITY) return
            if (now - lastShakeTime < MIN_INTERVAL_MS) return
            lastShakeTime = now
            onShake?.invoke()
        }

        override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) {}
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
        if (appPaused || isListening || onShake == null) return
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