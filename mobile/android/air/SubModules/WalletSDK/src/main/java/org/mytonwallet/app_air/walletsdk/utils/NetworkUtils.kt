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
        body: String? = null,
        connectTimeout: Int = 10_000,
        readTimeout: Int = 10_000,
        maxRetries: Int = 10,
        retryDelay: Long = 100L
    ): String? {
        var attempt = 0

        while (attempt < maxRetries) {
            var connection: HttpURLConnection? = null
            try {
                val url = URL(urlString)
                connection = url.openConnection() as HttpURLConnection
                connection.requestMethod = method.value
                connection.doInput = true
                connection.connectTimeout = connectTimeout
                connection.readTimeout = readTimeout

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
                return response.toString()

            } catch (e: Exception) {
                e.printStackTrace()
                attempt++
                if (attempt < maxRetries) {
                    Thread.sleep(retryDelay * attempt)
                }
            } finally {
                connection?.disconnect()
            }
        }

        return null
    }
}
