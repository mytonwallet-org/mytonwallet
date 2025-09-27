package org.mytonwallet.app_air.widgets.utils

import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.widget.RemoteViews
import androidx.core.net.toUri

object DeeplinkUtils {
    fun setOnClickDeeplink(
        context: Context,
        remoteViews: RemoteViews,
        viewId: Int,
        link: String
    ) {
        val intent = Intent(Intent.ACTION_VIEW, link.toUri())
        intent.setFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
        val pendingIntent = PendingIntent.getActivity(
            context,
            0,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        remoteViews.setOnClickPendingIntent(viewId, pendingIntent)
    }
}
