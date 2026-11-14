package org.mytonwallet.app_air.uiagent.viewControllers.news

import java.util.Locale
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletcore.pushNotifications.AgentNewsNotificationMode
import org.mytonwallet.app_air.walletcore.pushNotifications.AgentNewsNotificationOutcome
import org.mytonwallet.app_air.walletcore.pushNotifications.AgentNewsNotificationSettings

/** The digest's local time of day: an hour and its minute 0, 15, 30 or 45 */
internal data class AgentDigestTime(val hour: Int, val minute: Int)

/** The device's MyPulse notification choice and the digest's time, which the digest sheet changes */
internal interface AgentDigestNotificationSettings {
    val mode: AgentNewsNotificationMode
    val digestTime: AgentDigestTime

    suspend fun setMode(mode: AgentNewsNotificationMode): AgentNewsNotificationOutcome

    suspend fun setDigestTime(time: AgentDigestTime): AgentNewsNotificationOutcome

    /** The settings the device keeps */
    object Shared : AgentDigestNotificationSettings {
        private val settings get() = AgentNewsNotificationSettings.shared
        override val mode get() = settings.mode
        override val digestTime get() = AgentDigestTime(settings.digestHour, settings.digestMinute)

        override suspend fun setMode(mode: AgentNewsNotificationMode) = settings.setMode(mode)

        override suspend fun setDigestTime(time: AgentDigestTime) =
            settings.setDigestTime(time.hour, time.minute)
    }
}

/**
 * The digest sheet's state. A notification choice and a time show at once. A choice or a time picked while another is
 * applied goes next across sheets, the last one picked winning; a choice the settings turn down gives way to the one
 * they keep. A picked time stays also when applying it fails, since the settings keep it and apply it at the next start.
 */
internal class AgentDigestSettingsModel(
    private val settings: AgentDigestNotificationSettings,
    private val pendingState: PendingState
) {
    val mode get() = pendingState.queuedMode ?: pendingMode ?: settings.mode
    val digestTime get() = pendingState.queuedTime ?: pendingState.time ?: settings.digestTime

    /** The choice being applied */
    val pendingMode get() = pendingState.mode
    val isApplyingTime get() = pendingState.time != null

    /** The system turned notifications down for the app at the last choice that needs them */
    val isPermissionDenied get() = pendingState.isPermissionDenied
    var onChange: (() -> Unit)?
        get() = pendingState.onChange
        set(value) {
            pendingState.onChange = value
        }
    var onError: (() -> Unit)?
        get() = pendingState.onError
        set(value) {
            pendingState.onError = value
        }

    init {
        if (pendingMode == null) pendingState.isPermissionDenied = false
    }

    suspend fun selectMode(mode: AgentNewsNotificationMode) {
        if (mode == this.mode) return
        pendingState.isPermissionDenied = false
        if (pendingMode != null) {
            pendingState.queuedMode = mode
            onChange?.invoke()
            return
        }
        var next: AgentNewsNotificationMode? = mode
        while (next != null) {
            pendingState.queuedMode = null
            pendingState.mode = next
            onChange?.invoke()
            val outcome = settings.setMode(next)
            next = pendingState.queuedMode
            // Only the last choice's outcome is told: an earlier one is already replaced
            if (next == null) {
                pendingState.isPermissionDenied =
                    outcome == AgentNewsNotificationOutcome.PermissionDenied
                if (outcome == AgentNewsNotificationOutcome.Failed) onError?.invoke()
            }
        }
        pendingState.mode = null
        onChange?.invoke()
    }

    /** Applies [time], its hour and minute at once */
    suspend fun selectTime(time: AgentDigestTime) {
        if (time == digestTime) return
        if (isApplyingTime) {
            pendingState.queuedTime = time
            onChange?.invoke()
            return
        }
        var next: AgentDigestTime? = time
        while (next != null) {
            pendingState.queuedTime = null
            pendingState.time = next
            onChange?.invoke()
            if (settings.setDigestTime(next) ==
                AgentNewsNotificationOutcome.Failed
            ) {
                onError?.invoke()
            }
            next = pendingState.queuedTime
        }
        pendingState.time = null
        onChange?.invoke()
    }

    /** Only the digest's choice has a hint, which tells its time */
    fun hint(mode: AgentNewsNotificationMode): String? = when (mode) {
        AgentNewsNotificationMode.Digest ->
            LocaleController.getString("\$agent_digest_notifications_daily_hint")
                .replace("%time%", formatTime(digestTime))

        AgentNewsNotificationMode.Off, AgentNewsNotificationMode.News -> null
    }

    class PendingState {
        var mode: AgentNewsNotificationMode? = null
        var queuedMode: AgentNewsNotificationMode? = null
        var time: AgentDigestTime? = null
        var queuedTime: AgentDigestTime? = null
        var isPermissionDenied = false
        var onChange: (() -> Unit)? = null
        var onError: (() -> Unit)? = null
    }

    companion object {
        val sharedPendingState = PendingState()

        val HOURS = 0..23
        val MODES = listOf(
            AgentNewsNotificationMode.Off,
            AgentNewsNotificationMode.Digest,
            AgentNewsNotificationMode.News
        )

        fun formatTime(time: AgentDigestTime): String =
            String.format(Locale.US, "%02d:%02d", time.hour, time.minute)

        /** An hour or a minute alone, as the time wheel shows it */
        fun formatWheelValue(value: Int): String = String.format(Locale.US, "%02d", value)

        fun title(mode: AgentNewsNotificationMode): String = LocaleController.getString(
            when (mode) {
                AgentNewsNotificationMode.Off -> "\$agent_digest_notifications_off"
                AgentNewsNotificationMode.Digest -> "\$agent_digest_notifications_daily"
                AgentNewsNotificationMode.News -> "\$agent_digest_notifications_every"
            }
        )
    }
}
