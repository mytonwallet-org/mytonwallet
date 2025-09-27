package org.mytonwallet.app_air.uicomponents.base

import android.app.Activity
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.view.Choreographer
import android.view.FrameMetrics
import android.view.Window
import org.mytonwallet.app_air.walletbasecontext.logger.Logger

class WFramePerformanceMonitor(
    private val activity: Activity,
    private val isEnabled: Boolean = true,
    private val logTag: Logger.LogTag = Logger.LogTag.FPS_PERFORMANCE
) {

    interface PerformanceCallback {
        fun onFrameDropDetected(frameDuration: Long, droppedFrames: Int, context: String? = null)
        fun onSevereFrameDrop(frameDuration: Long, droppedFrames: Int, context: String? = null) {}
        fun onPerformanceSummary(frameDropRate: Float, sessionInfo: String) {}
    }

    private var callback: PerformanceCallback? = null
    private var frameDropDetector: FrameDropDetector? = null
    private var frameMetricsMonitor: FrameMetricsMonitor? = null
    private var contextProvider: (() -> String)? = null
    private var isMonitoring = false

    fun setCallback(callback: PerformanceCallback?) {
        this.callback = callback
    }

    fun setContextProvider(provider: (() -> String)?) {
        this.contextProvider = provider
    }

    fun startMonitoring() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.N)
            return
        if (!isEnabled || isMonitoring) return

        frameDropDetector = FrameDropDetector { frameDuration, droppedFrames ->
            val context = contextProvider?.invoke()

            Logger.w(
                logTag,
                "Frame drop: ${frameDuration / 1_000_000}ms, " +
                    "dropped: $droppedFrames${context?.let { ", $it" } ?: ""}"
            )

            callback?.onFrameDropDetected(frameDuration, droppedFrames, context)

            if (droppedFrames > 3) {
                callback?.onSevereFrameDrop(frameDuration, droppedFrames, context)
            }
        }

        frameMetricsMonitor =
            FrameMetricsMonitor(activity) { totalDuration, droppedFrames, frameMetrics ->
                analyzeDetailedMetrics(frameMetrics, droppedFrames)
            }

        frameDropDetector?.startMonitoring()
        frameMetricsMonitor?.startMonitoring()
        isMonitoring = true
    }

    fun stopMonitoring() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.N)
            return
        if (!isMonitoring) return

        val dropRate = getFrameDropRate()
        val sessionInfo = contextProvider?.invoke() ?: "Session ended"

        if (dropRate > 0) {
            Logger.i(logTag, "Session summary: ${dropRate}% frame drop rate, $sessionInfo")
            callback?.onPerformanceSummary(dropRate, sessionInfo)
        }

        frameDropDetector?.stopMonitoring()
        frameMetricsMonitor?.stopMonitoring()
        isMonitoring = false
    }

    fun getFrameDropRate(): Float {
        return frameDropDetector?.getFrameDropRate() ?: 0f
    }

    fun resetStats() {
        frameDropDetector?.reset()
    }

    private val ignoreNormalFrames = true
    private fun analyzeDetailedMetrics(
        frameMetrics: FrameMetrics,
        droppedFrames: Int
    ) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.N) return
        val totalFrameTime = frameMetrics.getMetric(FrameMetrics.TOTAL_DURATION)
        val deadline = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                frameMetrics.getMetric(FrameMetrics.DEADLINE)
            } else {
                0
            }
        } else 0L
        if (ignoreNormalFrames && totalFrameTime <= deadline)
            return
        if (droppedFrames < 4)
            return

        val unknownDelay = frameMetrics.getMetric(FrameMetrics.UNKNOWN_DELAY_DURATION)
        val inputHandling = frameMetrics.getMetric(FrameMetrics.INPUT_HANDLING_DURATION)
        val animationTime = frameMetrics.getMetric(FrameMetrics.ANIMATION_DURATION)
        val layoutTime = frameMetrics.getMetric(FrameMetrics.LAYOUT_MEASURE_DURATION)
        val drawTime = frameMetrics.getMetric(FrameMetrics.DRAW_DURATION)
        val syncTime = frameMetrics.getMetric(FrameMetrics.SYNC_DURATION)
        val commandIssue = frameMetrics.getMetric(FrameMetrics.COMMAND_ISSUE_DURATION)
        val swapBuffers = frameMetrics.getMetric(FrameMetrics.SWAP_BUFFERS_DURATION)

        val gpuDuration = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                frameMetrics.getMetric(FrameMetrics.GPU_DURATION)
            } else {
                0
            }
        } else 0L

        // Frame state metrics
        val isFirstDraw = frameMetrics.getMetric(FrameMetrics.FIRST_DRAW_FRAME) == 1L
        val intendedVsync = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            frameMetrics.getMetric(FrameMetrics.INTENDED_VSYNC_TIMESTAMP)
        } else {
            0
        }
        val actualVsync = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            frameMetrics.getMetric(FrameMetrics.VSYNC_TIMESTAMP)
        } else {
            0
        }
        val vsyncDelay = actualVsync - intendedVsync

        // Performance thresholds (8ms = 8,000,000 nanoseconds)
        val frameThreshold = 8_000_000L
        val criticalThreshold = 16_000_000L

        if (droppedFrames > 2 || totalFrameTime > frameThreshold) {
            Logger.w(logTag, buildString {
                append("=== FRAME PERFORMANCE ANALYSIS ===\n")

                // Overall frame info
                append("Frame Summary:\n")
                append("  Total: ${totalFrameTime / 1_000_000}ms")
                append(" | Deadline: ${deadline / 1_000_000}ms")
                append(" | Dropped: $droppedFrames")
                append(" | First Draw: $isFirstDraw")
                if (deadline > 0 && totalFrameTime < deadline) {
                    append(" ✓ Met deadline")
                } else if (deadline > 0) {
                    append(" ❌ Missed deadline by ${(totalFrameTime - deadline) / 1_000_000}ms")
                }
                append("\n\n")

                // VSync analysis
                if (vsyncDelay > 1_000_000) {
                    append("⚠️  VSync Delay: ${vsyncDelay / 1_000_000}ms - UI thread blocked\n")
                }

                if (unknownDelay > 1_000_000) {
                    append("⚠️  Unknown Delay: ${unknownDelay / 1_000_000}ms - Thread responsiveness issue\n")
                }

                // Detailed timing breakdown
                append("Timing Breakdown:\n")

                if (inputHandling > 1_000_000) {
                    append("  Input:     ${inputHandling / 1_000_000}ms")
                    if (inputHandling > frameThreshold) append(" ❌ BOTTLENECK")
                    append("\n")
                }

                if (animationTime > 1_000_000) {
                    append("  Animation: ${animationTime / 1_000_000}ms")
                    when {
                        animationTime > criticalThreshold -> append(" 🔴 CRITICAL")
                        animationTime > frameThreshold -> append(" ❌ BOTTLENECK")
                    }
                    append("\n")
                }

                if (layoutTime > 1_000_000) {
                    append("  Layout:    ${layoutTime / 1_000_000}ms")
                    when {
                        layoutTime > criticalThreshold -> append(" 🔴 CRITICAL")
                        layoutTime > frameThreshold -> append(" ❌ BOTTLENECK")
                    }
                    append("\n")
                }

                if (drawTime > 1_000_000) {
                    append("  Draw:      ${drawTime / 1_000_000}ms")
                    when {
                        drawTime > criticalThreshold -> append(" 🔴 CRITICAL")
                        drawTime > frameThreshold -> append(" ❌ BOTTLENECK")
                    }
                    append("\n")
                }

                if (syncTime > 1_000_000) {
                    append("  Sync:      ${syncTime / 1_000_000}ms")
                    if (syncTime > frameThreshold) append(" ❌ BOTTLENECK")
                    append("\n")
                }

                if (commandIssue > 1_000_000) {
                    append("  Command:   ${commandIssue / 1_000_000}ms")
                    if (commandIssue > frameThreshold) append(" ❌ BOTTLENECK")
                    append("\n")
                }

                if (swapBuffers > 1_000_000) {
                    append("  Swap:      ${swapBuffers / 1_000_000}ms")
                    if (swapBuffers > frameThreshold) append(" ❌ BOTTLENECK")
                    append("\n")
                }

                if (gpuDuration > 1_000_000) {
                    append("  GPU:       ${gpuDuration / 1_000_000}ms")
                    if (gpuDuration > frameThreshold) append(" ❌ GPU BOTTLENECK")
                    append("\n")
                }

                // Bottleneck recommendations
                append("\nRecommendations:\n")
                when {
                    layoutTime > frameThreshold -> {
                        append("• Layout bottleneck: Flatten view hierarchy, use ConstraintLayout\n")
                        append("• Avoid wrap_content in complex layouts\n")
                        append("• Consider ViewStub for conditional views\n")
                    }

                    drawTime > frameThreshold -> {
                        append("• Draw bottleneck: Reduce overdraw, optimize custom drawing\n")
                        append("• Cache Paint objects and Paths\n")
                        append("• Use hardware acceleration where possible\n")
                    }

                    animationTime > frameThreshold -> {
                        append("• Animation bottleneck: Use hardware-accelerated properties\n")
                        append("• Animate translationX/Y, scale, alpha, rotation\n")
                        append("• Avoid animating layout properties\n")
                    }

                    inputHandling > frameThreshold -> {
                        append("• Input bottleneck: Optimize touch event handling\n")
                        append("• Consider debouncing rapid input events\n")
                    }

                    syncTime > frameThreshold -> {
                        append("• Sync bottleneck: Reduce DisplayList complexity\n")
                        append("• Optimize view invalidation patterns\n")
                    }

                    commandIssue > frameThreshold -> {
                        append("• Command issue bottleneck: Reduce GPU draw calls\n")
                        append("• Combine drawables, optimize shaders\n")
                    }

                    swapBuffers > frameThreshold -> {
                        append("• Swap buffers bottleneck: Reduce frame buffer complexity\n")
                    }

                    gpuDuration > frameThreshold -> {
                        append("• GPU bottleneck: Optimize shaders and texture usage\n")
                        append("• Reduce fragment shader complexity\n")
                    }

                    vsyncDelay > 1_000_000 -> {
                        append("• VSync delay: Reduce main thread work\n")
                        append("• Move heavy operations to background threads\n")
                    }
                }

                append("=====================================")
            })
        }
    }

    private class FrameDropDetector(
        private val onFrameDrop: (Long, Int) -> Unit
    ) : Choreographer.FrameCallback {

        private var lastFrameTime = 0L
        private var frameCount = 0
        private var droppedFrameCount = 0
        private val targetFrameTime = 8_333_334L // 120 FPS in nanoseconds
        private val frameDropThreshold = targetFrameTime * 1.5

        fun startMonitoring() {
            lastFrameTime = 0L
            Choreographer.getInstance().postFrameCallback(this)
        }

        fun stopMonitoring() {
            Choreographer.getInstance().removeFrameCallback(this)
        }

        override fun doFrame(frameTimeNanos: Long) {
            if (lastFrameTime != 0L) {
                val frameDuration = frameTimeNanos - lastFrameTime
                frameCount++

                if (frameDuration > frameDropThreshold) {
                    droppedFrameCount++
                    val droppedFrames = (frameDuration / targetFrameTime).toInt()
                    onFrameDrop(frameDuration, droppedFrames)
                }
            }

            lastFrameTime = frameTimeNanos
            Choreographer.getInstance().postFrameCallback(this)
        }

        fun getFrameDropRate(): Float {
            return if (frameCount > 0) {
                (droppedFrameCount.toFloat() / frameCount) * 100f
            } else 0f
        }

        fun reset() {
            frameCount = 0
            droppedFrameCount = 0
            lastFrameTime = 0L
        }
    }

    private class FrameMetricsMonitor(
        private val activity: Activity,
        private val onFrameDrop: (Long, Int, FrameMetrics) -> Unit
    ) {

        private val frameMetricsListener =
            Window.OnFrameMetricsAvailableListener { _, frameMetrics, _ ->
                if (Build.VERSION.SDK_INT < Build.VERSION_CODES.N)
                    return@OnFrameMetricsAvailableListener

                val totalDuration = frameMetrics.getMetric(FrameMetrics.TOTAL_DURATION)
                val targetFrameTime = 8_333_334L

                if (totalDuration > targetFrameTime) {
                    val droppedFrames = (totalDuration / targetFrameTime).toInt()
                    onFrameDrop(totalDuration, droppedFrames, frameMetrics)
                }
            }

        fun startMonitoring() {
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.N)
                return
            activity.window.addOnFrameMetricsAvailableListener(
                frameMetricsListener,
                Handler(Looper.getMainLooper())
            )
        }

        fun stopMonitoring() {
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.N)
                return
            activity.window.removeOnFrameMetricsAvailableListener(frameMetricsListener)
        }
    }
}
