package org.mytonwallet.app_air.widgets.utils

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent
import android.widget.RemoteViews
import androidx.core.net.toUri

object DeeplinkUtils {
    const val ACTION_UPDATE = "UPDATE"
    const val MTW_DEEPLINK = "MTW_DEEPLINK"

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

    fun setOnClickDeeplinkWithWidgetUpdate(
        context: Context,
        remoteViews: RemoteViews,
        viewId: Int,
        link: String,
        widgetClass: Class<*>,
        appWidgetId: Int?
    ) {
        val appWidgetId = appWidgetId ?: return

        val intent = Intent(context, widgetClass).apply {
            action = ACTION_UPDATE
            putExtra(AppWidgetManager.EXTRA_APPWIDGET_IDS, intArrayOf(appWidgetId))
            putExtra(MTW_DEEPLINK, link)
        }

        val pendingIntent = PendingIntent.getBroadcast(
            context,
            appWidgetId,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        remoteViews.setOnClickPendingIntent(viewId, pendingIntent)
    }
}
