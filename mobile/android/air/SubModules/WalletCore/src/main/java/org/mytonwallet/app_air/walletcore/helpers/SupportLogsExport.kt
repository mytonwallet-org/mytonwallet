package org.mytonwallet.app_air.walletcore.helpers

import android.content.Context
import android.content.Intent
import android.util.Log
import androidx.core.content.FileProvider
import java.io.File
import java.util.concurrent.atomic.AtomicBoolean
import java.util.zip.ZipEntry
import java.util.zip.ZipOutputStream
import kotlin.coroutines.cancellation.CancellationException
import kotlin.time.Duration.Companion.milliseconds
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.TimeoutCancellationException
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeout
import org.mytonwallet.app_air.walletbasecontext.logger.Logger
import org.mytonwallet.app_air.walletbasecontext.utils.ApplicationContextHolder
import org.mytonwallet.app_air.walletcore.JSWebViewBridge
import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.moshi.api.ApiMethod

object SupportLogsExport {
    private const val NATIVE_LOGS_FILENAME = "native-logs.tsv"
    private const val DIAGNOSTICS_FILENAME = "diagnostics.json"
    private const val SDK_LOGS_FILENAME = "sdk-logs.json"
    private const val SDK_LOGS_ERROR_FILENAME = "sdk-logs-error.txt"
    private const val EMPTY_SDK_LOGS = "[]\n"
    private const val SDK_LOGS_TIMEOUT_MILLIS = 5_000L

    private val isExporting = AtomicBoolean(false)

    suspend fun share(context: Context) {
        if (!isExporting.compareAndSet(false, true)) return
        try {
            exportAndShare(context)
        } finally {
            isExporting.set(false)
        }
    }

    private suspend fun exportAndShare(context: Context) {
        val diagnostics = withContext(Dispatchers.IO) { collectDiagnostics(context) }
        val sdkLogs = collectSdkLogs()
        try {
            val archive = withContext(Dispatchers.IO) {
                createArchive(context, diagnostics, sdkLogs)
            }
            val uri = FileProvider.getUriForFile(
                context,
                "${context.packageName}.fileprovider",
                archive
            )
            val intent = Intent(Intent.ACTION_SEND).apply {
                type = "application/zip"
                putExtra(Intent.EXTRA_STREAM, uri)
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            }
            withContext(Dispatchers.Main) {
                context.startActivity(Intent.createChooser(intent, "Share logs"))
            }
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            Logger.e(Logger.LogTag.AIR_APPLICATION, "Failed to share logs archive: $e")
        }
    }

    private fun collectDiagnostics(context: Context): String = try {
        SupportDiagnosticsReport.collect(context).toString(2) + "\n"
    } catch (e: Exception) {
        Logger.e(
            Logger.LogTag.AIR_APPLICATION,
            "Failed to collect diagnostics: ${e.javaClass.name}"
        )
        "{\"error\":\"diagnostics collection failed\"}\n"
    }

    private suspend fun collectSdkLogs(): SdkLogsCollection {
        if (!WalletCore.isBridgeReady) {
            return SdkLogsCollection(
                EMPTY_SDK_LOGS,
                "SDK bridge not ready"
            )
        }
        return try {
            val logs = withTimeout(SDK_LOGS_TIMEOUT_MILLIS.milliseconds) {
                WalletCore.call(ApiMethod.Other.GetLogs())
            }
            SdkLogsCollection(logs?.toString(2)?.plus("\n") ?: EMPTY_SDK_LOGS, null)
        } catch (_: TimeoutCancellationException) {
            Logger.e(Logger.LogTag.AIR_APPLICATION, "Timed out collecting SDK logs")
            SdkLogsCollection(EMPTY_SDK_LOGS, "Timed out after ${SDK_LOGS_TIMEOUT_MILLIS}ms")
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            Logger.e(Logger.LogTag.AIR_APPLICATION, "Failed to collect SDK logs: $e")
            val error = if (e is JSWebViewBridge.ApiError) {
                "ApiError method=${e.methodName} parsed=${e.parsed} raw=${e.raw}"
            } else {
                Log.getStackTraceString(e)
            }
            SdkLogsCollection(EMPTY_SDK_LOGS, error)
        }
    }

    private fun createArchive(
        context: Context,
        diagnostics: String,
        sdkLogs: SdkLogsCollection
    ): File {
        val logsDir = File(context.filesDir, "logs").apply { mkdirs() }
        val archivePrefix = if (ApplicationContextHolder.isGramApp) "gram-logs-" else "mw-logs-"
        logsDir.listFiles { file -> file.name.startsWith(archivePrefix) }
            ?.forEach { it.delete() }

        val archive = File(logsDir, "$archivePrefix${System.currentTimeMillis()}.zip")
        ZipOutputStream(archive.outputStream().buffered()).use { zip ->
            zip.putFile(NATIVE_LOGS_FILENAME, Logger.readLogText())
            zip.putFile(DIAGNOSTICS_FILENAME, diagnostics)
            zip.putFile(SDK_LOGS_FILENAME, sdkLogs.data)
            sdkLogs.error?.let { zip.putFile(SDK_LOGS_ERROR_FILENAME, "$it\n") }
        }
        return archive
    }

    private fun ZipOutputStream.putFile(name: String, content: String) {
        putNextEntry(ZipEntry(name))
        write(content.toByteArray(Charsets.UTF_8))
        closeEntry()
    }

    private class SdkLogsCollection(val data: String, val error: String?)
}
