package org.mytonwallet.app_air.uicomponents.helpers

import android.content.Context
import android.os.Build
import android.os.VibrationEffect
import android.os.Vibrator

class HapticFeedbackHelper(val context: Context) {
    fun provideHapticFeedback(duration: Long = 35) {
        try {
            val vibrator = context.getSystemService(Context.VIBRATOR_SERVICE) as Vibrator
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                val vibrationEffect =
                    VibrationEffect.createOneShot(duration, VibrationEffect.DEFAULT_AMPLITUDE)
                vibrator.vibrate(vibrationEffect)
            } else {
                vibrator.vibrate(duration)
            }
        } catch (ignore: Exception) {
        }
    }

    fun provideErrorFeedback() {
        try {
            val vibrator = context.getSystemService(Context.VIBRATOR_SERVICE) as Vibrator
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                val vibrationEffect =
                    VibrationEffect.createWaveform(longArrayOf(0, 50, 100, 50, 100), -1)
                vibrator.vibrate(vibrationEffect)
            } else {
                vibrator.vibrate(longArrayOf(0, 50, 100, 50, 100), -1)
            }
        } catch (ignore: Exception) {
        }
    }
}
