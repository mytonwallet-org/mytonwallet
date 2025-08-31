package org.mytonwallet.app_air.walletcontext.helpers

import android.app.ActivityManager
import android.content.Context
import android.os.Build
import java.io.File

object DevicePerformanceClassifier {
    enum class PerformanceClass {
        LOW,
        MEDIUM,
        HIGH,
    }

    var performanceClass: PerformanceClass? = null

    val isLowClass: Boolean
        get() {
            return performanceClass == PerformanceClass.LOW
        }
    val isMediumClass: Boolean
        get() {
            return performanceClass == PerformanceClass.MEDIUM
        }
    val isHighClass: Boolean
        get() {
            return performanceClass == PerformanceClass.HIGH
        }

    val isAboveAverage: Boolean
        get() {
            return !isLowClass
        }

    fun init(context: Context) {
        val androidVersion = Build.VERSION.SDK_INT
        val cpuCount = Runtime.getRuntime().availableProcessors()
        val memoryClass = getMemoryClass(context)
        val maxCpuFreq = getMaxCpuFreqMHz()
        val totalRamBytes = getTotalRamBytes()

        val isLow = androidVersion < 21 ||
            cpuCount <= 2 ||
            memoryClass <= 100 ||
            (cpuCount <= 4 && maxCpuFreq != -1 && maxCpuFreq <= 1250) ||
            (cpuCount <= 4 && maxCpuFreq <= 1600 && memoryClass <= 128 && androidVersion <= 21) ||
            (cpuCount <= 4 && maxCpuFreq <= 1300 && memoryClass <= 128 && androidVersion <= 24) ||
            (totalRamBytes != -1L && totalRamBytes < 2L * 1024 * 1024 * 1024)

        val isAverage = !isLow && (
            cpuCount < 8 ||
                memoryClass <= 160 ||
                (maxCpuFreq != -1 && maxCpuFreq <= 2055) ||
                (maxCpuFreq == -1 && cpuCount == 8 && androidVersion <= 23)
            )

        performanceClass = when {
            isLow -> PerformanceClass.LOW
            isAverage -> PerformanceClass.MEDIUM
            else -> PerformanceClass.HIGH
        }
    }

    private fun getMemoryClass(context: Context): Int {
        val activityManager = context.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
        return activityManager.memoryClass // MB
    }

    private fun getTotalRamBytes(): Long {
        return try {
            val reader = File("/proc/meminfo").bufferedReader()
            val line = reader.readLine()
            val parts = line.split(Regex("\\s+"))
            val memTotalKb = parts[1].toLong()
            memTotalKb * 1024
        } catch (_: Exception) {
            -1L
        }
    }

    private fun getMaxCpuFreqMHz(): Int {
        val cpuCount = Runtime.getRuntime().availableProcessors()
        var totalFreq = 0
        var resolved = 0

        for (i in 0 until cpuCount) {
            try {
                val path = "/sys/devices/system/cpu/cpu$i/cpufreq/cpuinfo_max_freq"
                val file = File(path)
                if (file.exists()) {
                    val line = file.bufferedReader().use { it.readLine() }
                    if (!line.isNullOrEmpty()) {
                        val freqKHz = line.trim().toIntOrNull()
                        if (freqKHz != null) {
                            totalFreq += freqKHz / 1000 // MHz
                            resolved++
                        }
                    }
                }
            } catch (_: Throwable) {
            }
        }

        return if (resolved > 0) totalFreq / resolved else -1
    }
}
