package org.mytonwallet.app_air.walletcontext.installationStorage

import android.system.ErrnoException
import android.system.Os
import android.system.OsConstants
import android.util.AtomicFile
import com.squareup.moshi.JsonAdapter
import com.squareup.moshi.Moshi
import java.io.File
import java.nio.ByteBuffer
import java.util.concurrent.ArrayBlockingQueue
import java.util.concurrent.RejectedExecutionException
import java.util.concurrent.ThreadPoolExecutor
import java.util.concurrent.TimeUnit

internal val storageMoshi: Moshi = Moshi.Builder().build()

internal class AtomicJsonFile<T>(
    directory: File,
    name: String,
    private val adapter: JsonAdapter<T>,
    private val maxBytes: Int,
    private val checkpoint: (String) -> Unit = {}
) {
    private val file = AtomicFile(File(directory, name))

    fun exists(): Boolean {
        check(OsConstants.S_ISDIR(Os.stat(file.baseFile.parent!!).st_mode))
        return listOf("", ".bak", ".new").map { suffix ->
            try {
                Os.lstat(file.baseFile.path + suffix)
                true
            } catch (error: ErrnoException) {
                if (error.errno != OsConstants.ENOENT) throw error
                false
            }
        }.any { it }
    }

    fun read(): T = file.openRead().use { source ->
        val bytes = ByteArray(maxBytes + 1)
        var length = 0
        while (length < bytes.size) {
            val count = source.read(bytes, length, bytes.size - length)
            if (count < 0) break
            length += count
        }
        require(length <= maxBytes)
        val text = Charsets.UTF_8.newDecoder().decode(ByteBuffer.wrap(bytes, 0, length)).toString()
        require(text.none { it.code == 0 })
        // Canonical encoding rejects coercion and fields the native writer cannot produce.
        requireNotNull(adapter.fromJson(text)).also {
            require(adapter.toJson(it) == text) { "Noncanonical storage document" }
        }
    }

    fun write(value: T) {
        val stream = file.startWrite()
        var isCommitted = false
        try {
            val bytes = adapter.toJson(value).toByteArray(Charsets.UTF_8)
            require(bytes.size <= maxBytes)
            stream.write(bytes)
            checkpoint("writing")
            stream.fd.sync()
            file.finishWrite(stream)
            isCommitted = true
            check(read() == value) { "Atomic JSON commit was not persisted" }
        } catch (error: Throwable) {
            if (!isCommitted) file.failWrite(stream)
            throw error
        }
    }
}

internal fun boundedSerialWorker(name: String) = ThreadPoolExecutor(
    1,
    1,
    0L,
    TimeUnit.MILLISECONDS,
    ArrayBlockingQueue(32),
    { task -> Thread(task, name).apply { isDaemon = true } }
)

internal fun ThreadPoolExecutor.accept(operation: () -> Unit): Boolean = try {
    execute { runCatching(operation) }
    true
} catch (_: RejectedExecutionException) {
    false
}
