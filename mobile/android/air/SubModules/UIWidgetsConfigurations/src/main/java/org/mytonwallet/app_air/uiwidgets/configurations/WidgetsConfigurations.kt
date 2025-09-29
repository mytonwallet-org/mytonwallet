package org.mytonwallet.app_air.uiwidgets.configurations

import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import org.mytonwallet.app_air.widgets.actionsWidget.ActionsWidget
import org.mytonwallet.app_air.widgets.priceWidget.PriceWidget

object WidgetsConfigurations {
    fun reloadWidgets(context: Context) {
        val appWidgetManager = AppWidgetManager.getInstance(context)
        appWidgetManager
            .getAppWidgetIds(ComponentName(context, ActionsWidget::class.java))
            .let { appWidgetIds ->
                ActionsWidget().onUpdate(context, appWidgetManager, appWidgetIds)
            }
        appWidgetManager
            .getAppWidgetIds(ComponentName(context, PriceWidget::class.java))
            .let { appWidgetIds ->
                PriceWidget().onUpdate(context, appWidgetManager, appWidgetIds)
            }
    }
}
