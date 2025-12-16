package org.mytonwallet.app_air.uicomponents.helpers

import android.content.Context
import android.os.Build
import android.os.VibrationEffect
import android.os.Vibrator

/**
 * @deprecated Use [Haptics] instead for consistent haptic feedback across the app.
 *
 * Migration guide:
 * - `HapticFeedbackHelper(context).provideHapticFeedback()` → `Haptics.play(view, HapticType.LIGHT_TAP)`
 * - `HapticFeedbackHelper(context).provideErrorFeedback()` → `Haptics.play(view, HapticType.ERROR)`
 */
@Deprecated("Use Haptics object instead", ReplaceWith("Haptics.play(view, HapticType.LIGHT_TAP)"))
class HapticFeedbackHelper(val context: Context) {
    @Deprecated("Use Haptics.play(view, HapticType.LIGHT_TAP)", ReplaceWith("Haptics.play(view, HapticType.LIGHT_TAP)"))
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

    @Deprecated("Use Haptics.play(view, HapticType.ERROR)", ReplaceWith("Haptics.play(view, HapticType.ERROR)"))
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
