package org.mytonwallet.app_air.widgets.priceWidget

import android.annotation.SuppressLint
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.widget.RemoteViews
import org.mytonwallet.app_air.walletbasecontext.WBaseStorage
import org.mytonwallet.app_air.walletbasecontext.models.MBaseCurrency
import org.mytonwallet.app_air.walletbasecontext.utils.toString
import org.mytonwallet.app_air.walletsdk.methods.SDKApiMethod
import org.mytonwallet.app_air.widgets.R
import org.mytonwallet.app_air.widgets.utils.DeeplinkUtils
import org.mytonwallet.app_air.widgets.utils.FontUtils
import org.mytonwallet.app_air.widgets.utils.TextUtils
import org.mytonwallet.app_air.widgets.utils.colorWithAlpha

class PriceWidget : AppWidgetProvider() {

    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)
        if (intent.action == Intent.ACTION_CONFIGURATION_CHANGED) {
            val appWidgetManager = AppWidgetManager.getInstance(context)
            val ids = appWidgetManager.getAppWidgetIds(ComponentName(context, javaClass))
            onUpdate(context, appWidgetManager, ids)
        }
    }

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray
    ) {
        val baseCurrency = WBaseStorage.getBaseCurrency() ?: MBaseCurrency.USD

        SDKApiMethod.Token.PriceChart("TON", "1D", baseCurrency.currencyCode)
            .call(object : SDKApiMethod.ApiCallback<Array<Array<Double>>> {
                override fun onSuccess(result: Array<Array<Double>>) {
                    for (appWidgetId in appWidgetIds) {
                        updateAppWidget(
                            context,
                            appWidgetManager,
                            appWidgetId,
                            baseCurrency,
                            result
                        )
                    }
                }

                override fun onError(error: Throwable) {

                }
            })
    }

    fun updateAppWidget(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetId: Int,
        baseCurrency: MBaseCurrency,
        priceChartData: Array<Array<Double>>
    ) {
        appWidgetManager.updateAppWidget(
            appWidgetId,
            generateRemoteViews(
                context,
                baseCurrency,
                priceChartData
            )
        )
    }

    @SuppressLint("DefaultLocale")
    private fun generateRemoteViews(
        context: Context,
        baseCurrency: MBaseCurrency,
        priceChartData: Array<Array<Double>>
    ): RemoteViews {
        val views = RemoteViews(context.packageName, R.layout.price_widget)
        DeeplinkUtils.setOnClickDeeplink(context, views, R.id.container, "mtw://")
        views.setImageViewBitmap(
            R.id.text_symbol, TextUtils.textToBitmap(
                context,
                TextUtils.DrawableText(
                    "TON",
                    size = 20,
                    color = Color.WHITE,
                    FontUtils.semiBold(context)
                )
            )
        )

        views.setImageViewBitmap(
            R.id.text_price, TextUtils.textToBitmap(
                context,
                TextUtils.DrawableText(
                    priceChartData
                        .lastOrNull()
                        ?.get(1)
                        ?.toString(9, baseCurrency.sign, 9, true) ?: "",
                    size = 32,
                    color = Color.WHITE,
                    FontUtils.nunitoExtraBold(context)
                )
            )
        )

        var priceChangeValue: Double? = null
        val priceChangePercent = if (priceChartData.size > 1) {
            val firstPrice = priceChartData.firstOrNull {
                it[1] != 0.0
            }?.get(1)
            firstPrice?.let {
                priceChangeValue = priceChartData.last()[1] - firstPrice
                priceChangeValue * 100 / firstPrice
            }
        } else null
        priceChangePercent?.let {
            val sign = if (priceChangePercent > 0) "+" else ""
            views.setImageViewBitmap(
                R.id.text_price_change, TextUtils.textToBitmap(
                    context,
                    TextUtils.DrawableText(
                        "$sign${
                            String.format(
                                "%.2f",
                                priceChangePercent
                            )
                        }% · ${
                            priceChangeValue?.toString(
                                decimals = 9,
                                currency = baseCurrency.sign,
                                currencyDecimals = 9,
                                smartDecimals = true
                            )
                        }",
                        size = 15,
                        color = Color.WHITE.colorWithAlpha(191),
                        FontUtils.regular(context)
                    )
                )
            )
        }

        return views
    }

    override fun onDeleted(context: Context, appWidgetIds: IntArray) {
    }
}
