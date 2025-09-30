package org.mytonwallet.app_air.uiwidgets.configurations

import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.PeriodicWorkRequest
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import org.mytonwallet.app_air.walletbasecontext.WBaseStorage
import org.mytonwallet.app_air.widgets.actionsWidget.ActionsWidget
import org.mytonwallet.app_air.widgets.priceWidget.PriceWidget
import java.util.concurrent.TimeUnit

object WidgetsConfigurations {
    fun scheduleWidgetUpdates(context: Context) {
        val widgetUpdateRequest = PeriodicWorkRequestBuilder<WidgetUpdateWorker>(
            PeriodicWorkRequest.MIN_PERIODIC_INTERVAL_MILLIS,
            TimeUnit.MILLISECONDS
        ).build()
        WorkManager.getInstance(context.applicationContext).enqueueUniquePeriodicWork(
            "widgetUpdateWork",
            ExistingPeriodicWorkPolicy.KEEP,
            widgetUpdateRequest
        )
    }

    fun reloadWidgets(context: Context) {
        reloadActionsWidgets(context)
        reloadPriceWidgets(context)
    }

    fun reloadActionsWidgets(context: Context) {
        val appWidgetManager = AppWidgetManager.getInstance(context)
        appWidgetManager
            .getAppWidgetIds(ComponentName(context, ActionsWidget::class.java))
            .let { appWidgetIds ->
                ActionsWidget().onUpdate(context, appWidgetManager, appWidgetIds)
            }
    }

    fun reloadPriceWidgets(context: Context, onCompletion: (() -> Unit)? = null) {
        val appWidgetManager = AppWidgetManager.getInstance(context)
        appWidgetManager
            .getAppWidgetIds(ComponentName(context, PriceWidget::class.java))
            .let { appWidgetIds ->
                PriceWidget().updateAppWidgets(
                    context,
                    appWidgetManager,
                    appWidgetIds,
                    onCompletion
                )
            }
    }

    fun isWidgetConfigured(appWidgetId: Int): Boolean {
        return WBaseStorage.getWidgetConfigurations(appWidgetId) != null
    }
}
