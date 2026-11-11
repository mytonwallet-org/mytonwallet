package org.mytonwallet.app_air.uiagent.viewControllers.news

import java.util.Locale
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletcore.pushNotifications.AgentNewsNotificationMode
import org.mytonwallet.app_air.walletcore.pushNotifications.AgentNewsNotificationOutcome
import org.mytonwallet.app_air.walletcore.pushNotifications.AgentNewsNotificationSettings

/** The device's MyPulse notification choice and the digest's hour, which the digest sheet changes */
internal interface AgentDigestNotificationSettings {
    val mode: AgentNewsNotificationMode
    val digestHour: Int

    suspend fun setMode(mode: AgentNewsNotificationMode): AgentNewsNotificationOutcome

    suspend fun setDigestHour(hour: Int): AgentNewsNotificationOutcome

    /** The settings the device keeps */
    object Shared : AgentDigestNotificationSettings {
        private val settings get() = AgentNewsNotificationSettings.shared
        override val mode get() = settings.mode
        override val digestHour get() = settings.digestHour

        override suspend fun setMode(mode: AgentNewsNotificationMode) = settings.setMode(mode)

        override suspend fun setDigestHour(hour: Int) = settings.setDigestHour(hour)
    }
}

/**
 * The digest sheet's state. A notification choice shows once the settings take it: while one is applied no other can
 * be picked, and one turned down keeps the previous choice. A picked hour shows at once and stays, also when applying
 * it fails, since the settings keep it and apply it at the next start; while it is applied no other hour is taken.
 */
internal class AgentDigestSettingsModel(
    private val settings: AgentDigestNotificationSettings,
    private val showError: () -> Unit
) {
    var mode = settings.mode
        private set
    var digestHour = settings.digestHour
        private set

    /** The choice being applied */
    var pendingMode: AgentNewsNotificationMode? = null
        private set
    var isApplyingHour = false
        private set

    /** The system turned notifications down for the app at the last choice that needs them */
    var isPermissionDenied = false
        private set
    var onChange: (() -> Unit)? = null

    suspend fun selectMode(mode: AgentNewsNotificationMode) {
        if (pendingMode != null || mode == this.mode) return
        pendingMode = mode
        onChange?.invoke()
        val outcome = settings.setMode(mode)
        pendingMode = null
        this.mode = settings.mode
        isPermissionDenied = outcome == AgentNewsNotificationOutcome.PermissionDenied
        onChange?.invoke()
        if (outcome == AgentNewsNotificationOutcome.Failed) showError()
    }

    suspend fun selectHour(hour: Int) {
        if (isApplyingHour || hour == digestHour) return
        isApplyingHour = true
        digestHour = hour
        onChange?.invoke()
        val outcome = settings.setDigestHour(hour)
        digestHour = settings.digestHour
        isApplyingHour = false
        onChange?.invoke()
        if (outcome == AgentNewsNotificationOutcome.Failed) showError()
    }

    fun hint(mode: AgentNewsNotificationMode): String = when (mode) {
        AgentNewsNotificationMode.Off ->
            LocaleController.getString("\$agent_digest_notifications_off_hint")

        AgentNewsNotificationMode.Digest ->
            LocaleController.getString("\$agent_digest_notifications_daily_hint")
                .replace("%time%", formatHour(digestHour))

        AgentNewsNotificationMode.News ->
            LocaleController.getString("\$agent_digest_notifications_every_hint")
    }

    companion object {
        val HOURS = 0..23
        val MODES = listOf(
            AgentNewsNotificationMode.Off,
            AgentNewsNotificationMode.Digest,
            AgentNewsNotificationMode.News
        )

        fun formatHour(hour: Int): String = String.format(Locale.US, "%02d:00", hour)

        fun title(mode: AgentNewsNotificationMode): String = LocaleController.getString(
            when (mode) {
                AgentNewsNotificationMode.Off -> "\$agent_digest_notifications_off"
                AgentNewsNotificationMode.Digest -> "\$agent_digest_notifications_daily"
                AgentNewsNotificationMode.News -> "\$agent_digest_notifications_every"
            }
        )
    }
}
