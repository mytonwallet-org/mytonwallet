package org.mytonwallet.app_air.uicomponents.commonViews.cardMotion

import android.content.Context
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import kotlin.math.abs
import kotlin.math.acos

/** Latest fused attitude is read by the card frame, without queuing motion samples. */
internal class CardMotionSensor(context: Context) : SensorEventListener {
    private val manager = context.getSystemService(Context.SENSOR_SERVICE) as? SensorManager
    private val quaternion = FloatArray(4)
    private var lastTimestamp = 0L
    var sample: Attitude? = null
        private set
    var angularSpeed = 0.0
        private set
    private var listening = false

    fun start() {
        if (listening) return
        val sensor = manager?.getDefaultSensor(Sensor.TYPE_GAME_ROTATION_VECTOR)
            ?: manager?.getDefaultSensor(Sensor.TYPE_ROTATION_VECTOR) ?: return
        listening = manager?.registerListener(this, sensor, 16_667) == true
    }

    fun stop(reset: Boolean) {
        if (listening) manager?.unregisterListener(this)
        listening = false
        lastTimestamp = 0L
        angularSpeed = 0.0
        if (reset) sample = null
    }

    override fun onSensorChanged(event: SensorEvent) {
        SensorManager.getQuaternionFromVector(quaternion, event.values)
        val next = Attitude(
            quaternion[1].toDouble(),
            quaternion[2].toDouble(),
            quaternion[3].toDouble(),
            quaternion[0].toDouble()
        )
        val previous = sample
        val dt = (event.timestamp - lastTimestamp) / 1e9
        angularSpeed = if (previous != null && lastTimestamp != 0L && dt > .001 && dt < .5) {
            2 *
                acos(
                    abs(
                        previous.x * next.x + previous.y * next.y + previous.z * next.z +
                            previous.w * next.w
                    ).coerceIn(0.0, 1.0)
                ) /
                dt
        } else {
            0.0
        }
        sample = next
        lastTimestamp = event.timestamp
    }

    override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) = Unit
}
