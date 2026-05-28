package org.mytonwallet.app_air.uicomponents.helpers

import android.content.Context
import android.os.Build
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.view.HapticFeedbackConstants
import android.view.View

/**
 * Standardized haptic feedback types used throughout the app.
 * Mirrors the iOS HapticType enum for cross-platform consistency.
 */
enum class HapticType {
    /** Light "tick" for selection changes (pickers, carousels, menus) */
    SELECTION,

    /** Light tap for copy actions and soft confirmations */
    LIGHT_TAP,

    /** UI state transitions (expand/collapse, modal present) */
    TRANSITION,

    /** Drag and drop, reordering operations */
    DRAG,

    /** Successful completion of an action */
    SUCCESS,

    /** Error or failure notification */
    ERROR
}

/**
 * Centralized haptic feedback manager for consistent tactile feedback.
 * Mirrors the iOS Haptics enum for cross-platform consistency.
 */
object Haptics {

    /**
     * Play haptic feedback using a View (preferred - respects system settings)
     */
    @JvmStatic
    fun play(view: View?, type: HapticType) {
        view ?: return

        val constant = when (type) {
            HapticType.SELECTION -> {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
                    HapticFeedbackConstants.TEXT_HANDLE_MOVE
                } else {
                    HapticFeedbackConstants.CLOCK_TICK
                }
            }

            HapticType.LIGHT_TAP -> {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                    HapticFeedbackConstants.CONFIRM
                } else {
                    HapticFeedbackConstants.KEYBOARD_TAP
                }
            }

            HapticType.TRANSITION -> {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                    HapticFeedbackConstants.CONTEXT_CLICK
                } else {
                    HapticFeedbackConstants.VIRTUAL_KEY
                }
            }

            HapticType.DRAG -> HapticFeedbackConstants.LONG_PRESS
            HapticType.SUCCESS -> {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                    HapticFeedbackConstants.CONFIRM
                } else {
                    HapticFeedbackConstants.VIRTUAL_KEY
                }
            }

            HapticType.ERROR -> {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                    HapticFeedbackConstants.REJECT
                } else {
                    // Fall back to vibrator for error on older APIs
                    playWithVibrator(view.context, type)
                    return
                }
            }
        }

        view.performHapticFeedback(constant)
    }

    /**
     * Play haptic feedback using Context (fallback when no View available)
     */
    @JvmStatic
    fun play(context: Context?, type: HapticType) {
        context ?: return
        playWithVibrator(context, type)
    }

    private fun playWithVibrator(context: Context, type: HapticType) {
        try {
            val vibrator = getVibrator(context) ?: return

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                // Use predefined effects on API 29+
                val effect = when (type) {
                    HapticType.SELECTION -> VibrationEffect.EFFECT_TICK
                    HapticType.LIGHT_TAP -> VibrationEffect.EFFECT_CLICK
                    HapticType.TRANSITION -> VibrationEffect.EFFECT_CLICK
                    HapticType.DRAG -> VibrationEffect.EFFECT_HEAVY_CLICK
                    HapticType.SUCCESS -> VibrationEffect.EFFECT_HEAVY_CLICK
                    HapticType.ERROR -> {
                        // Custom waveform for error
                        val waveform = VibrationEffect.createWaveform(
                            longArrayOf(0, 50, 80, 50),
                            intArrayOf(0, 180, 0, 180),
                            -1
                        )
                        vibrator.vibrate(waveform)
                        return
                    }
                }
                vibrator.vibrate(VibrationEffect.createPredefined(effect))
            } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                // Use VibrationEffect on API 26+
                val (duration, amplitude) = when (type) {
                    HapticType.SELECTION -> 10L to 80
                    HapticType.LIGHT_TAP -> 20L to 100
                    HapticType.TRANSITION -> 25L to 120
                    HapticType.DRAG -> 35L to 180
                    HapticType.SUCCESS -> 30L to 150
                    HapticType.ERROR -> {
                        val waveform = VibrationEffect.createWaveform(
                            longArrayOf(0, 50, 80, 50),
                            -1
                        )
                        vibrator.vibrate(waveform)
                        return
                    }
                }
                vibrator.vibrate(VibrationEffect.createOneShot(duration, amplitude))
            } else {
                // Legacy vibration
                @Suppress("DEPRECATION")
                val duration = when (type) {
                    HapticType.SELECTION -> 10L
                    HapticType.LIGHT_TAP -> 20L
                    HapticType.TRANSITION -> 25L
                    HapticType.DRAG -> 35L
                    HapticType.SUCCESS -> 30L
                    HapticType.ERROR -> {
                        @Suppress("DEPRECATION")
                        vibrator.vibrate(longArrayOf(0, 50, 80, 50), -1)
                        return
                    }
                }
                @Suppress("DEPRECATION")
                vibrator.vibrate(duration)
            }
        } catch (e: Exception) {
            // Silently ignore - haptics are non-critical
        }
    }

    private fun getVibrator(context: Context): Vibrator? {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val vibratorManager =
                context.getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as? VibratorManager
            vibratorManager?.defaultVibrator
        } else {
            @Suppress("DEPRECATION")
            context.getSystemService(Context.VIBRATOR_SERVICE) as? Vibrator
        }
    }
}



