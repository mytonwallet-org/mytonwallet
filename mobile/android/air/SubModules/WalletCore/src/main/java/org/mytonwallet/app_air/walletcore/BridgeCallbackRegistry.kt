package org.mytonwallet.app_air.walletcore

import com.squareup.moshi.JsonReader
import okio.Buffer
import org.mytonwallet.app_air.walletcore.models.MBridgeError

internal typealias BridgeCallback = (result: String?, error: MBridgeError?) -> Unit

internal class BridgeCallbackRegistry {
    private val callbacks = HashMap<Int, BridgeCallback>()

    internal val pendingCount: Int
        get() = callbacks.size

    fun register(identifier: Int, callback: BridgeCallback) {
        callbacks[identifier] = callback
    }

    fun complete(identifier: Int, success: Boolean, result: String) {
        val callback = callbacks.remove(identifier) ?: return
        val error = if (success) null else parseError(result)
        callback(result, error)
    }

    fun failAll(error: MBridgeError = MBridgeError.Type.UNKNOWN) {
        val pendingCallbacks = callbacks.values.toList()
        callbacks.clear()
        for (callback in pendingCallbacks) {
            callback(null, error)
        }
    }

    private fun parseError(result: String): MBridgeError {
        return try {
            val root = JsonReader.of(Buffer().writeUtf8(result)).use { reader ->
                reader.readJsonValue() as? Map<*, *>
            } ?: return MBridgeError.Type.UNKNOWN
            val rawError = root["error"]
            val errorObject = rawError as? Map<*, *> ?: root["err"] as? Map<*, *>
            val errorName = (errorObject?.get("name") as? String)?.takeIf { it.isNotBlank() }
                ?: (rawError as? String)?.takeIf { it.isNotBlank() }
                ?: (root["name"] as? String)?.takeIf { it.isNotBlank() }
            MBridgeError.fromErrorName(errorName)
                ?: (errorObject?.get("displayError") as? String)
                    ?.takeIf { it.isNotBlank() }
                    ?.let(MBridgeError.Type.UNKNOWN::withCustomMessage)
                ?: MBridgeError.Type.UNKNOWN
        } catch (_: Exception) {
            MBridgeError.Type.UNKNOWN
        }
    }
}
