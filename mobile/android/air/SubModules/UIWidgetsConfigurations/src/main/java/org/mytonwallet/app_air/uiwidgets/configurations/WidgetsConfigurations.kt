package org.mytonwallet.app_air.uiwidgets.configurations

import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.PeriodicWorkRequest
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import org.mytonwallet.app_air.widgets.actionsWidget.ActionsWidget
import org.mytonwallet.app_air.widgets.priceWidget.PriceWidget
import java.util.concurrent.TimeUnit

object WidgetsConfigurations {
    const val WIDGET_UPDATE_WORK = "widgetUpdateWork"

    fun scheduleWidgetUpdates(context: Context) {
        val appWidgetManager = AppWidgetManager.getInstance(context)
        val priceWidgetIds =
            appWidgetManager.getAppWidgetIds(ComponentName(context, PriceWidget::class.java))

        val shouldUpdateWidgets = priceWidgetIds.isNotEmpty()

        if (shouldUpdateWidgets) {
            val widgetUpdateRequest = PeriodicWorkRequestBuilder<WidgetUpdateWorker>(
                PeriodicWorkRequest.MIN_PERIODIC_INTERVAL_MILLIS,
                TimeUnit.MILLISECONDS
            ).build()
            WorkManager.getInstance(context.applicationContext).enqueueUniquePeriodicWork(
                WIDGET_UPDATE_WORK,
                ExistingPeriodicWorkPolicy.KEEP,
                widgetUpdateRequest
            )
        } else {
            cancelWidgetUpdates(context)
        }
    }

    fun cancelWidgetUpdates(context: Context) {
        WorkManager.getInstance(context.applicationContext)
            .cancelUniqueWork(WIDGET_UPDATE_WORK)
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

    fun reloadPriceWidgets(
        context: Context,
        onCompletion: ((widgetExists: Boolean) -> Unit)? = null
    ) {
        val appWidgetManager = AppWidgetManager.getInstance(context)
        appWidgetManager
            .getAppWidgetIds(ComponentName(context, PriceWidget::class.java))
            .let { appWidgetIds ->
                PriceWidget().updateAppWidgets(
                    context,
                    appWidgetManager,
                    appWidgetIds,
                    onCompletion = onCompletion?.let {
                        return@let {
                            onCompletion.invoke(appWidgetIds.size > 0)
                        }
                    }
                )
            }
    }
}
