package org.mytonwallet.app_air.uicomponents.extensions

import android.os.SystemClock
import androidx.lifecycle.LifecycleOwner
import androidx.lifecycle.ViewModel
import androidx.lifecycle.lifecycleScope
import androidx.lifecycle.viewModelScope
import java.util.concurrent.atomic.AtomicLong
import kotlinx.coroutines.FlowPreview
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.debounce
import kotlinx.coroutines.flow.launchIn
import kotlinx.coroutines.flow.onEach

fun <T> LifecycleOwner.collectFlow(flow: Flow<T>, action: suspend (T) -> Unit): Job =
    flow.onEach(action).launchIn(lifecycleScope)

fun <T> ViewModel.collectFlow(flow: Flow<T>, action: suspend (T) -> Unit): Job =
    flow.onEach(action).launchIn(viewModelScope)

@FlowPreview
fun <T> Flow<T>.throttle(milliseconds: Long): Flow<T> {
    val last = AtomicLong()
    return this.debounce {
        val uptime = SystemClock.uptimeMillis()
        val prevUptime = last.getAndSet(uptime)

        val d = maxOf(0, milliseconds - (uptime - prevUptime))

        d
    }
}
