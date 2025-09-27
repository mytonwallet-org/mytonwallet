package org.mytonwallet.app_air.walletsdk.utils

import java.io.BufferedReader
import java.io.InputStreamReader
import java.io.OutputStream
import java.net.HttpURLConnection
import java.net.URL

object NetworkUtils {
    enum class Method(val value: String) {
        GET("GET"),
        POST("POST"),
        PUT("PUT")
    }

    fun request(
        urlString: String,
        method: Method,
        headers: Map<String, String> = emptyMap(),
        body: String? = null
    ): String? {
        var connection: HttpURLConnection? = null
        return try {
            val url = URL(urlString)
            connection = url.openConnection() as HttpURLConnection
            connection.requestMethod = method.value
            connection.doInput = true

            connection.setRequestProperty("Accept", "application/json")
            for ((key, value) in headers) {
                connection.setRequestProperty(key, value)
            }

            if ((method == Method.POST || method == Method.PUT) && body != null) {
                connection.doOutput = true
                val bytes = body.toByteArray(Charsets.UTF_8)
                connection.outputStream.use { os: OutputStream ->
                    os.write(bytes, 0, bytes.size)
                }
            }

            val reader = if (connection.responseCode in 200..299) {
                BufferedReader(InputStreamReader(connection.inputStream))
            } else {
                BufferedReader(InputStreamReader(connection.errorStream))
            }

            val response = StringBuilder()
            reader.useLines { lines ->
                lines.forEach { response.append(it) }
            }
            response.toString()

        } catch (e: Exception) {
            e.printStackTrace()
            null
        } finally {
            connection?.disconnect()
        }
    }
}
