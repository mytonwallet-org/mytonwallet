package org.mytonwallet.app_air.walletcore

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.webkit.WebView
import com.android.installreferrer.api.InstallReferrerClient
import com.android.installreferrer.api.InstallReferrerStateListener
import java.lang.ref.WeakReference
import java.util.concurrent.atomic.AtomicReference
import org.mytonwallet.app_air.walletcontext.installationStorage.PlaySnapshot
import org.mytonwallet.app_air.walletcontext.installationStorage.WInstallationStorage

internal data class ReferrerSnapshot(val raw: String?, val seconds: Long, val version: String?)

internal interface ReferrerService {
    fun start(callback: (Int) -> Unit)
    fun read(): ReferrerSnapshot
    fun close()
}

internal class ReferrerCollection(
    private val create: () -> ReferrerService,
    private val enqueue: (() -> Unit) -> Boolean,
    private val persist: (PlaySnapshot) -> Unit,
    private val onPersistFailure: () -> Unit,
    private val scheduleRetry: ((() -> Unit) -> Unit)
) {
    private val attempt = AtomicReference<Any?>()
    private val retrying = Any()
    private val settled = Any()

    private fun retry(notify: () -> Unit): Unit = scheduleRetry {
        val accepted = enqueue {
            if (!attempt.compareAndSet(retrying, null)) return@enqueue
            collect(false, notify)
        }
        if (!accepted && attempt.get() === retrying) retry(notify)
    }

    fun collect(isCompleted: Boolean, notify: () -> Unit) {
        if (isCompleted) return
        val token = Any()
        if (!attempt.compareAndSet(null, token)) return
        var service: ReferrerService? = null
        fun finish(status: String, details: ReferrerSnapshot? = null) {
            if (!attempt.compareAndSet(token, settled)) return
            val isPersisted = try {
                val source = details?.let { sanitizeInstallAttribution(it.raw) }
                val metadata = details?.let {
                    readPlayInstallMetadata(it.seconds, it.version)
                }
                persist(
                    PlaySnapshot(
                        null,
                        metadata?.installedAt,
                        metadata?.installVersion ?: "",
                        status,
                        source
                    )
                )
                true
            } catch (_: Exception) {
                attempt.set(null)
                false
            } finally {
                runCatching { service?.close() }
            }
            if (isPersisted) {
                if (status != "ok") attempt.set(null)
                notify()
            } else {
                onPersistFailure()
            }
        }
        try {
            service = create()
            service.start { code ->
                val accepted = enqueue {
                    if (attempt.get() !== token) return@enqueue
                    if (code == 0) {
                        val details = try {
                            service.read()
                        } catch (_: Exception) {
                            finish("read_exception")
                            return@enqueue
                        }
                        finish("ok", details)
                    } else {
                        finish(
                            when (code) {
                                -1 -> "service_disconnected"
                                1 -> "service_unavailable"
                                2 -> "feature_not_supported"
                                3 -> "developer_error"
                                else -> "unexpected_response"
                            }
                        )
                    }
                }
                if (!accepted && attempt.compareAndSet(token, retrying)) {
                    runCatching { service.close() }
                    retry(notify)
                }
            }
        } catch (_: Exception) {
            finish("connection_exception")
        }
    }
}

object InstallReferrerChannel {
    private var collection: ReferrerCollection? = null
    private val bridges = mutableListOf<WeakReference<WebView>>()
    private var context: Context? = null
    private val retryHandler by lazy { Handler(Looper.getMainLooper()) }
    private val retryStart = Runnable {
        if (!WInstallationStorage.enqueue(::start)) postRetryStart(500)
    }
    private var retryDelay = 500L

    fun deliver(context: Context, webView: WebView) = WInstallationStorage.enqueue {
        this.context = context.applicationContext
        synchronized(bridges) {
            bridges.removeAll { it.get() == null || it.get() === webView }
            bridges.add(WeakReference(webView))
        }
        start()
    }

    private fun start() {
        val applicationContext = checkNotNull(context)
        val owner = collection ?: ReferrerCollection(
            create = {
                val client = InstallReferrerClient.newBuilder(applicationContext).build()
                object : ReferrerService {
                    override fun start(callback: (Int) -> Unit) {
                        client.startConnection(object : InstallReferrerStateListener {
                            override fun onInstallReferrerSetupFinished(responseCode: Int) {
                                callback(responseCode)
                            }
                            override fun onInstallReferrerServiceDisconnected() {
                                callback(-1)
                            }
                        })
                    }
                    override fun read(): ReferrerSnapshot {
                        val details = client.installReferrer
                        return ReferrerSnapshot(
                            details.installReferrer,
                            details.installBeginTimestampServerSeconds,
                            details.installVersion
                        )
                    }
                    override fun close() = client.endConnection()
                }
            },
            enqueue = WInstallationStorage::enqueue,
            persist = WInstallationStorage::observe,
            onPersistFailure = ::scheduleStartRetry,
            scheduleRetry = { Handler(applicationContext.mainLooper).postDelayed(it, 500) }
        ).also { collection = it }
        if (runCatching { WInstallationStorage.ensureOpen(applicationContext) }.isFailure) {
            scheduleStartRetry()
            return
        }
        notifyBridges()
        owner.collect(WInstallationStorage.hasSuccessfulObservation()) {
            retryDelay = 500L
            notifyBridges()
        }
    }

    private fun scheduleStartRetry() {
        postRetryStart(retryDelay)
        retryDelay = minOf(retryDelay * 2, 60_000L)
    }

    private fun postRetryStart(delay: Long) {
        retryHandler.removeCallbacks(retryStart)
        retryHandler.postDelayed(retryStart, delay)
    }

    fun notifyBridges() {
        val current = synchronized(bridges) { bridges.mapNotNull { it.get() } }
        current.forEach { bridge ->
            bridge.post {
                runCatching {
                    bridge.evaluateJavascript(
                        "window.airBridge?.handleInstallationStateChange?.()",
                        null
                    )
                }
            }
        }
    }
}
