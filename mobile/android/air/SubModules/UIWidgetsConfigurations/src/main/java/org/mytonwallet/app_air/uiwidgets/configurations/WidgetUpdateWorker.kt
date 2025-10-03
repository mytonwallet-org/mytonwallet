package org.mytonwallet.app_air.uiwidgets.configurations

import android.content.Context
import androidx.work.CoroutineWorker
import androidx.work.WorkerParameters
import kotlin.coroutines.resume
import kotlin.coroutines.suspendCoroutine

class WidgetUpdateWorker(
    private val applicationContext: Context,
    workerParams: WorkerParameters
) : CoroutineWorker(applicationContext, workerParams) {

    override suspend fun doWork(): Result {
        return try {
            suspendCoroutine { cont ->
                WidgetsConfigurations.reloadPriceWidgets(applicationContext) { widgetExists ->
                    if (!widgetExists) {
                        WidgetsConfigurations.cancelWidgetUpdates(applicationContext)
                    }
                    cont.resume(Result.success())
                }
            }
        } catch (_: Exception) {
            Result.failure()
        }
    }
}
