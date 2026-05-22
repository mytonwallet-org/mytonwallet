package org.mytonwallet.app_air.uicomponents.commonViews.toast

import androidx.annotation.DrawableRes
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.receiveAsFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.withTimeoutOrNull
import kotlin.time.Duration
import kotlin.time.Duration.Companion.seconds

object ToastManager {

    data class Toast(
        @param:DrawableRes
        val iconResId: Int? = null,
        val text: CharSequence,
        val actionTitle: CharSequence? = null,
        val duration: Duration = DURATION_DEFAULT,
        val onAction: (() -> Unit)? = null
    ) {

        companion object {
            val DURATION_DEFAULT: Duration = 5.seconds
        }
    }

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
    private val toastsChannel = Channel<Toast>(Channel.RENDEZVOUS)
    val toastsFlow: Flow<Toast> = toastsChannel.receiveAsFlow()

    fun show(toast: Toast) {
        scope.launch {
            withTimeoutOrNull(5.seconds) {
                toastsChannel.send(toast)
            }
        }
    }
}
