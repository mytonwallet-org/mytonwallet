package org.mytonwallet.app_air.walletcore.deeplink

import android.app.Activity
import android.content.Intent

object LaunchSender {
    /**
     * Whether the system reports this app's own package as the sender of `activity.intent`, as it
     * does for a notification `PendingIntent` created in this process. In `onNewIntent`, call it
     * after `setIntent` and before the callback returns: only then does the referrer belong to the
     * new intent.
     */
    @JvmStatic
    fun isOwnPackage(activity: Activity): Boolean = try {
        val intent = activity.intent
        isOwnPackage(
            removeExtra = { intent?.removeExtra(it) },
            readReferrer = { activity.referrer?.toString() },
            packageName = activity.packageName
        )
    } catch (_: RuntimeException) {
        // Extras that fail to unparcel come from a sender this app does not control
        false
    }

    /**
     * `Activity.getReferrer` prefers the sender-supplied `EXTRA_REFERRER` and `EXTRA_REFERRER_NAME`,
     * so they are removed before [readReferrer] reports the package the system recorded.
     */
    internal fun isOwnPackage(
        removeExtra: (String) -> Unit,
        readReferrer: () -> String?,
        packageName: String
    ): Boolean {
        removeExtra(Intent.EXTRA_REFERRER)
        removeExtra(Intent.EXTRA_REFERRER_NAME)
        return readReferrer() == "android-app://$packageName"
    }
}
