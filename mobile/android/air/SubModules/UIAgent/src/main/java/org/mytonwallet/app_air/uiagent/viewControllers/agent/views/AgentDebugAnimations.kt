package org.mytonwallet.app_air.uiagent.viewControllers.agent.views

import android.content.ContentResolver
import android.content.Context
import android.database.ContentObserver
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import org.mytonwallet.app_air.walletbasecontext.DEBUG_MODE

/**
 * The system animator scale for the Agent's looping views, which in debug builds stop while it is
 * zero, so E2E runs with animations off get an idle main thread. Listeners run on the main thread
 * when the scale changes.
 */
internal object AgentDebugAnimations {
    private val listeners = LinkedHashSet<() -> Unit>()
    private var observer: ContentObserver? = null
    private var isScaleAboveZero = true

    fun areSystemAnimationsOn(context: Context): Boolean {
        if (!DEBUG_MODE) return true
        if (observer == null) isScaleAboveZero = readIsScaleAboveZero(context.contentResolver)
        return isScaleAboveZero
    }

    fun addListener(context: Context, listener: () -> Unit) {
        if (!DEBUG_MODE) return
        listeners.add(listener)
        if (observer != null) return
        val resolver = context.applicationContext.contentResolver
        isScaleAboveZero = readIsScaleAboveZero(resolver)
        val newObserver = object : ContentObserver(Handler(Looper.getMainLooper())) {
            override fun onChange(selfChange: Boolean) {
                isScaleAboveZero = readIsScaleAboveZero(resolver)
                listeners.toList().forEach { it() }
            }
        }
        resolver.registerContentObserver(
            Settings.Global.getUriFor(Settings.Global.ANIMATOR_DURATION_SCALE),
            false,
            newObserver
        )
        observer = newObserver
    }

    fun removeListener(context: Context, listener: () -> Unit) {
        if (!listeners.remove(listener) || listeners.isNotEmpty()) return
        observer?.let { context.applicationContext.contentResolver.unregisterContentObserver(it) }
        observer = null
    }

    private fun readIsScaleAboveZero(resolver: ContentResolver) =
        Settings.Global.getFloat(resolver, Settings.Global.ANIMATOR_DURATION_SCALE, 1f) > 0f
}
