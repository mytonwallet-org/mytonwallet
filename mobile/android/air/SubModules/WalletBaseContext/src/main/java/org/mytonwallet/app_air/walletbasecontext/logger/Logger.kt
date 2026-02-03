package org.mytonwallet.app_air.walletbasecontext.logger

import android.content.Context
import android.content.Intent
import android.util.Log
import androidx.core.content.FileProvider
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.FileOutputStream
import java.io.IOException
import java.util.Locale
import java.util.concurrent.locks.ReentrantLock
import kotlin.concurrent.withLock

object Logger {
    enum class LogTag(val tag: String) {
        AIR_APPLICATION("Air"),
        LOCALIZATION("Localization"),
        ACCOUNT("Acc"),
        ACTIVITY_LOADER("ActLoader"),
        ACTIVITY_STORE("ActStore"),
        FPS_PERFORMANCE("FPS"),
        HomeVM("Home"),
        //DEEPLINK("Deeplink"),

        //JS_LOG("JSLog"),
        JS_WEBVIEW_BRIDGE("JSBridge"),
        PASSCODE_CONFIRM("PassConf"),
        SCREEN("Screen"),
        SECURE_STORAGE("SecStore"),
        SHIDDevice("SHID"),
        SEND("Send"),
        SWAP("Swap"),
        STAKING("Staking"),
        SETTINGS("Settings"),
    }

    enum class LogLevel(val str: String) {
        INFO("I"), DEBUG("D"), WARN("W"), ERROR("E")
    }

    data class LogEntry(
        val tag: String,
        val level: LogLevel,
        val message: LogMessage,
        val timestamp: Long,
    ) {
        fun composedForFile(): String {
            val relativeTime = (timestamp - appStartTime) / 1000.0
            val messageStr = message.toString().replace("\t", "\\t").replace("\n", "\\n")
            return String.format(
                Locale.US, "%.6f\t%s\t%s\t%s\n",
                relativeTime, level.str, tag, messageStr
            )
        }
    }

    private const val MAX_BUFFER = 1_000_000
    private const val MAX_LOG_FILE = 5_000_000

    private val appStartTime = System.currentTimeMillis()
    private val buffer = ByteArrayOutputStream()
    private val lock = ReentrantLock()
    private var logFile: File? = null
    private val scope = CoroutineScope(Dispatchers.IO + SupervisorJob())

    fun initialize(context: Context) {
        val logsDir = File(context.filesDir, "logs").apply { mkdirs() }
        logFile = File(logsDir, "air-log.tsv")

        val oldHandler = Thread.getDefaultUncaughtExceptionHandler()
        Thread.setDefaultUncaughtExceptionHandler { thread, throwable ->
            e(
                LogTag.AIR_APPLICATION,
                LogMessage("Uncaught exception: ${Log.getStackTraceString(throwable)}")
            )
            synchronize()

            oldHandler?.uncaughtException(thread, throwable)
        }
    }

    // LOG METHODS /////////////////////////////////////////////////////////////////////////////////
    fun e(tag: LogTag, message: LogMessage) {
        Log.e(tag.tag, message.toString())
        log(tag, LogLevel.ERROR, message)
    }

    fun e(tag: LogTag, message: String) {
        e(tag, LogMessage(message))
    }

    fun w(tag: LogTag, message: LogMessage) {
        Log.w(tag.tag, message.toString())
        log(tag, LogLevel.WARN, message)
    }

    fun w(tag: LogTag, message: String) {
        w(tag, LogMessage(message))
    }

    fun d(tag: LogTag, message: LogMessage) {
        Log.d(tag.tag, message.toString())
        log(tag, LogLevel.DEBUG, message)
    }

    fun d(tag: LogTag, message: String) {
        d(tag, LogMessage(message))
    }

    fun i(tag: LogTag, message: LogMessage) {
        Log.i(tag.tag, message.toString())
        log(tag, LogLevel.INFO, message)
    }

    fun i(tag: LogTag, message: String) {
        i(tag, LogMessage(message))
    }

    fun forceSynchronize() {
        scope.launch {
            synchronize()
        }
    }
    ////////////////////////////////////////////////////////////////////////////////////////////////

    private fun log(tag: LogTag, level: LogLevel, message: LogMessage) {
        scope.launch {
            val entry =
                LogEntry(tag.tag, level, message, System.currentTimeMillis())
            write(entry)
        }
    }

    private fun write(entry: LogEntry) {
        val data = entry.composedForFile().toByteArray(Charsets.UTF_8)

        lock.withLock {
            buffer.write(data)
            if (buffer.size() > MAX_BUFFER) {
                synchronize()
            }
        }
    }

    private fun synchronize() {
        lock.withLock {
            if (buffer.size() == 0) return
            val logFile = logFile ?: return

            try {
                if (logFile.exists() && logFile.length() > MAX_LOG_FILE) {
                    val data = logFile.readBytes()
                    val trimmed = data.copyOfRange((MAX_LOG_FILE / 2), data.size)
                    logFile.writeBytes(trimmed)
                }

                val outputStream = FileOutputStream(logFile, true)
                buffer.writeTo(outputStream)
                outputStream.flush()
                outputStream.close()

                buffer.reset()
            } catch (_: IOException) {
                logFile.writeBytes(buffer.toByteArray())
                buffer.reset()
            }
        }
    }

    fun shareLogFile(context: Context) {
        synchronize()
        val logFile = logFile ?: return

        val uri = FileProvider.getUriForFile(
            context,
            "${context.packageName}.fileprovider",
            logFile
        )

        val intent = Intent(Intent.ACTION_SEND).apply {
            type = "text/tab-separated-values"
            putExtra(Intent.EXTRA_STREAM, uri)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }

        context.startActivity(Intent.createChooser(intent, "Share log file"))
    }
}
