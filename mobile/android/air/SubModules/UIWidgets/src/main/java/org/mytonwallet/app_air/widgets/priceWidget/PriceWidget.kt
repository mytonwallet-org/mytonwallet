package org.mytonwallet.app_air.widgets.priceWidget

import android.annotation.SuppressLint
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.res.Configuration
import android.graphics.Bitmap
import android.graphics.Color
import android.os.Bundle
import android.widget.RemoteViews
import androidx.core.graphics.toColorInt
import androidx.core.net.toUri
import org.json.JSONArray
import org.json.JSONObject
import org.mytonwallet.app_air.walletbasecontext.WBaseStorage
import org.mytonwallet.app_air.walletbasecontext.models.MBaseCurrency
import org.mytonwallet.app_air.walletbasecontext.utils.ApplicationContextHolder
import org.mytonwallet.app_air.walletbasecontext.utils.MHistoryTimePeriod
import org.mytonwallet.app_air.walletbasecontext.utils.formatDateAndTime
import org.mytonwallet.app_air.walletbasecontext.utils.formatTime
import org.mytonwallet.app_air.walletbasecontext.utils.signSpace
import org.mytonwallet.app_air.walletbasecontext.utils.toString
import org.mytonwallet.app_air.walletsdk.methods.SDKApiMethod
import org.mytonwallet.app_air.widgets.R
import org.mytonwallet.app_air.widgets.utils.BackgroundUtils
import org.mytonwallet.app_air.widgets.utils.ChartUtils
import org.mytonwallet.app_air.widgets.utils.DeeplinkUtils
import org.mytonwallet.app_air.widgets.utils.FontUtils
import org.mytonwallet.app_air.widgets.utils.ImageUtils
import org.mytonwallet.app_air.widgets.utils.TextUtils
import org.mytonwallet.app_air.widgets.utils.colorWithAlpha
import org.mytonwallet.app_air.widgets.utils.dp
import java.util.Date
import java.util.LinkedList
import java.util.Queue
import kotlin.math.absoluteValue

class PriceWidget : AppWidgetProvider() {
    companion object {
        const val DEFAULT_TOKEN = "TON"
        const val DEFAULT_COLOR = "#0088cc"
    }

    data class Config(
        val token: JSONObject?,
        val period: MHistoryTimePeriod?,
        var appWidgetMinWidth: Int? = null,
        var appWidgetMinHeight: Int? = null,
        var appWidgetMaxWidth: Int? = null,
        var appWidgetMaxHeight: Int? = null,
        // Cache chart to redraw on size changes
        var cachedChart: List<Array<Double>> = listOf(),
        var cachedChartDt: Long = 0,
        var cachedChartCurrency: String? = null,
        var isShown: Boolean = false
    ) {
        constructor(config: JSONObject?) : this(
            token = config?.optJSONObject("token"),
            period = MHistoryTimePeriod.fromValue(config?.optString("period"))
                ?: MHistoryTimePeriod.DAY,
            appWidgetMinWidth = config?.optInt("appWidgetMinWidth")?.let {
                if (it > 0) it else null
            },
            appWidgetMinHeight = config?.optInt("appWidgetMinHeight")?.let {
                if (it > 0) it else null
            },
            appWidgetMaxWidth = config?.optInt("appWidgetMaxWidth").let {
                if ((it ?: 0) > 0) it else null
            },
            appWidgetMaxHeight = config?.optInt("appWidgetMaxHeight").let {
                if ((it ?: 0) > 0) it else null
            },
            cachedChart = {
                val chartList = mutableListOf<Array<Double>>()
                val jsonArray = config?.optJSONArray("cachedChart")
                if (jsonArray != null) {
                    for (i in 0 until jsonArray.length()) {
                        val innerArray = jsonArray.optJSONArray(i)
                        if (innerArray != null) {
                            val doubles = DoubleArray(innerArray.length()) { j ->
                                innerArray.optDouble(j)
                            }
                            chartList.add(doubles.toTypedArray())
                        }
                    }
                }
                chartList
            }(),
            cachedChartDt = config?.optLong("cachedChartDt") ?: 0,
            cachedChartCurrency = config?.optString("cachedChartCurrency"),
            isShown = config?.optBoolean("isShown") ?: false,
        )

        fun toJson(): JSONObject =
            JSONObject()
                .put("token", token)
                .put("period", period?.value)
                .put("appWidgetMinWidth", appWidgetMinWidth)
                .put("appWidgetMinHeight", appWidgetMinHeight)
                .put("appWidgetMaxWidth", appWidgetMaxWidth)
                .put("appWidgetMaxHeight", appWidgetMaxHeight).apply {
                    val chartArray = cachedChart.map { array ->
                        array.fold(JSONArray()) { jsonArr, value ->
                            jsonArr.put(value)
                        }
                    }
                    put("cachedChart", JSONArray(chartArray))
                    put("cachedChartDt", cachedChartDt)
                    put("cachedChartCurrency", cachedChartCurrency)
                    put("isShown", isShown)
                }

        val tokenChain: String?
            get() {
                return token?.optString("chain")
            }
        val tokenAddress: String?
            get() {
                return token?.optString("tokenAddress")
            }
        val tokenSymbol: String?
            get() {
                return token?.optString("symbol") ?: DEFAULT_TOKEN
            }
        val tokenSlug: String?
            get() {
                return token?.optString("slug")
            }
        val assetId: String?
            get() {
                if (tokenChain == "ton") {
                    tokenAddress?.let {
                        if (!it.isEmpty())
                            return it
                    }
                }
                return token?.optString("symbol") ?: DEFAULT_TOKEN
            }
    }

    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)
        if (intent.action == Intent.ACTION_CONFIGURATION_CHANGED) {
            val appWidgetManager = AppWidgetManager.getInstance(context)
            val ids = appWidgetManager.getAppWidgetIds(ComponentName(context, javaClass))
            onUpdate(context, appWidgetManager, ids)
        }
        if (intent.action == DeeplinkUtils.ACTION_UPDATE) {
            val appWidgetManager = AppWidgetManager.getInstance(context)
            onUpdate(
                context,
                appWidgetManager,
                intent.getIntArrayExtra(AppWidgetManager.EXTRA_APPWIDGET_IDS)!!
            )
        }
        intent.getStringExtra(DeeplinkUtils.MTW_DEEPLINK)?.let { mtwDeeplink ->
            val activityIntent = Intent(Intent.ACTION_VIEW, mtwDeeplink.toUri()).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK
            }
            context.startActivity(activityIntent)
        }
    }

    override fun onAppWidgetOptionsChanged(
        context: Context?,
        appWidgetManager: AppWidgetManager?,
        appWidgetId: Int,
        newOptions: Bundle?
    ) {
        super.onAppWidgetOptionsChanged(context, appWidgetManager, appWidgetId, newOptions)
        val context = context ?: return
        val minWidth = newOptions?.getInt("appWidgetMinWidth") ?: return
        val minHeight = newOptions.getInt("appWidgetMinHeight")
        val maxWidth = newOptions.getInt("appWidgetMaxWidth")
        val maxHeight = newOptions.getInt("appWidgetMaxHeight")
        if (minWidth == 0 || minHeight == 0 || maxWidth == 0 || maxHeight == 0)
            return
        ApplicationContextHolder.update(context.applicationContext)
        WBaseStorage.init(context)
        val config = Config(WBaseStorage.getWidgetConfigurations(appWidgetId) ?: JSONObject())
        WBaseStorage.setWidgetConfigurations(appWidgetId, config.apply {
            appWidgetMinWidth = minWidth
            appWidgetMinHeight = minHeight
            appWidgetMaxWidth = maxWidth
            appWidgetMaxHeight = maxHeight
        }.toJson())
        appWidgetManager?.let {
            updateAppWidget(
                context,
                appWidgetManager,
                appWidgetId,
                config,
            )
        }
    }

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
    ) {
        updateAppWidgets(context, appWidgetManager, appWidgetIds, null)
    }

    fun updateAppWidgets(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        onCompletion: (() -> Unit)?
    ) {
        val cachedPriceChartData = mutableMapOf<String, Array<Array<Double>>>()
        ApplicationContextHolder.update(context.applicationContext)
        WBaseStorage.init(context)
        val baseCurrency = WBaseStorage.getBaseCurrency() ?: MBaseCurrency.USD
        val widgetQueue: Queue<Int> = LinkedList(appWidgetIds.toList())

        // TODO:: Consider loading parallel since it's not common to have several widgets with same token and period.
        //      Make sure to don't miss onCompletion?.invoke() if changed anything!
        fun processNextWidget() {
            val appWidgetId = widgetQueue.poll() ?: run {
                onCompletion?.invoke()
                return
            }

            var config = Config(WBaseStorage.getWidgetConfigurations(appWidgetId) ?: JSONObject())
            if (config.appWidgetMinWidth == null || config.appWidgetMinHeight == null) {
                val options = appWidgetManager.getAppWidgetOptions(appWidgetId)
                val minWidth = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH)
                if (minWidth > 0) {
                    config.appWidgetMinWidth = minWidth
                    config.appWidgetMinHeight =
                        options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT)
                    config.appWidgetMaxWidth =
                        options.getInt(AppWidgetManager.OPTION_APPWIDGET_MAX_WIDTH)
                    config.appWidgetMaxHeight =
                        options.getInt(AppWidgetManager.OPTION_APPWIDGET_MAX_HEIGHT)
                    WBaseStorage.setWidgetConfigurations(appWidgetId, config.toJson())
                }
            }
            val period = config.period
            val cacheKey = "${config.assetId}_$period"

            cachedPriceChartData[cacheKey]?.let { priceChartData ->
                config =
                    Config(WBaseStorage.getWidgetConfigurations(appWidgetId)).apply {
                        cachedChart = priceChartData.toList()
                    }
                WBaseStorage.setWidgetConfigurations(appWidgetId, config.toJson())
                updateAppWidget(
                    context,
                    appWidgetManager,
                    appWidgetId,
                    config,
                )
                processNextWidget()
            } ?: run {
                val period = config.period?.value ?: run {
                    processNextWidget()
                    return
                }
                // Update with latest chart data available if base currencies match
                if (config.cachedChartCurrency == baseCurrency.currencyCode)
                    updateAppWidget(
                        context,
                        appWidgetManager,
                        appWidgetId,
                        config,
                    )
                // Ignore requesting again if it's updated less than a minute ago
                if (config.cachedChart.isNotEmpty() &&
                    config.cachedChartDt > System.currentTimeMillis() - 60_000 &&
                    config.cachedChartCurrency == baseCurrency.currencyCode
                ) {
                    processNextWidget()
                    return
                }
                val assetId = config.assetId ?: DEFAULT_TOKEN
                SDKApiMethod.Token.PriceChart(
                    assetId,
                    period,
                    baseCurrency.currencyCode
                )
                    .call(object : SDKApiMethod.ApiCallback<Array<Array<Double>>> {
                        override fun onSuccess(result: Array<Array<Double>>) {
                            cachedPriceChartData[cacheKey] = result
                            config =
                                Config(WBaseStorage.getWidgetConfigurations(appWidgetId)).apply {
                                    cachedChart = result.toList()
                                    cachedChartDt = System.currentTimeMillis()
                                    cachedChartCurrency = baseCurrency.currencyCode
                                }
                            if (config.assetId != assetId || config.period?.value != period) {
                                processNextWidget()
                                return
                            }
                            WBaseStorage.setWidgetConfigurations(appWidgetId, config.toJson())
                            updateAppWidget(
                                context,
                                appWidgetManager,
                                appWidgetId,
                                config,
                            )
                            processNextWidget()
                        }

                        override fun onError(error: Throwable) {
                            processNextWidget()
                        }
                    })
            }
        }

        processNextWidget()
    }

    private fun updateAppWidget(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetId: Int,
        config: Config,
    ) {
        val orientation = context.resources.configuration.orientation
        val isLandscape = orientation == Configuration.ORIENTATION_LANDSCAPE
        if (!config.isShown) {
            if (config.token != null) {
                config.isShown = true
                WBaseStorage.setWidgetConfigurations(appWidgetId, config.toJson())
            }
            appWidgetManager.updateAppWidget(
                appWidgetId,
                generateRemoteViews(
                    context,
                    config,
                    if (isLandscape) config.appWidgetMaxWidth else config.appWidgetMinWidth,
                    if (isLandscape) config.appWidgetMinHeight else config.appWidgetMaxHeight,
                    null,
                    appWidgetId
                )
            )
        }
        ImageUtils.loadBitmapFromUrl(
            context,
            config.token?.optString("image", ""),
            onBitmapReady = { image ->
                appWidgetManager.updateAppWidget(
                    appWidgetId,
                    generateRemoteViews(
                        context,
                        config,
                        if (isLandscape) config.appWidgetMaxWidth else config.appWidgetMinWidth,
                        if (isLandscape) config.appWidgetMinHeight else config.appWidgetMaxHeight,
                        image,
                        appWidgetId
                    )
                )
            })
    }

    @SuppressLint("DefaultLocale")
    fun generateRemoteViews(
        context: Context,
        config: Config,
        width: Int?,
        height: Int?,
        image: Bitmap?,
        appWidgetId: Int?
    ): RemoteViews {
        val views = RemoteViews(context.packageName, R.layout.price_widget)
        DeeplinkUtils.setOnClickDeeplinkWithWidgetUpdate(
            context,
            views,
            R.id.container,
            "mtw://token/${config.tokenSlug}",
            PriceWidget::class.java,
            appWidgetId
        )

        // PREPARE VALUES //////////////////////////////////////////////////////////////////////////
        val priceChartData = config.cachedChart.toTypedArray()
        val baseColor = config.token?.optString("color", DEFAULT_COLOR)?.let {
            if (it != "null")
                it.toColorInt()
            else
                DEFAULT_COLOR.toColorInt()
        } ?: DEFAULT_COLOR.toColorInt()
        val firstEntry = priceChartData.firstOrNull {
            it[1] != 0.0
        }
        var priceChangeValue: Double? = null
        val priceChangePercent = if (priceChartData.size > 1) {
            val firstPrice = firstEntry?.get(1)
            firstPrice?.let {
                priceChangeValue = priceChartData.last()[1] - firstPrice
                priceChangeValue * 100 / firstPrice
            }
        } else null

        image?.let {
            views.setImageViewBitmap(R.id.image_symbol, it)
        }

        val isCompact = (width ?: 100) <= 200

        // BITMAPS /////////////////////////////////////////////////////////////////////////////////
        val forcedCompact = isCompact || priceChangePercent == null
        val change = priceChangePercent ?: 0.0
        val sign = when {
            change > 0 -> "+$signSpace"
            change < 0 -> "-$signSpace"
            else -> ""
        }
        val priceChangeAndDateBitmap = if (priceChangePercent != null) TextUtils.textToBitmap(
            context,
            TextUtils.DrawableText(
                "$sign${
                    String.format(
                        "%.2f",
                        kotlin.math.abs(priceChangePercent)
                    )
                }% · ${Date(priceChartData.last()[0].toLong() * 1000).formatTime()}",
                size = 15,
                color = Color.WHITE.colorWithAlpha(191),
                FontUtils.regular(context)
            )
        ) else null
        val symbolBitmap = TextUtils.textToBitmap(
            context,
            TextUtils.DrawableText(
                config.tokenSymbol ?: "",
                size = 20,
                color = Color.WHITE,
                FontUtils.semiBold(context)
            )
        )
        val baseCurrency =
            if (config.cachedChartCurrency != config.tokenSymbol)
                config.cachedChartCurrency?.let { MBaseCurrency.parse(it) }
            else
                MBaseCurrency.USD
        val firstPriceSmallBitmap = if (forcedCompact) null else TextUtils.textToBitmap(
            context,
            TextUtils.DrawableText(
                firstEntry?.get(1)
                    ?.toString(9, baseCurrency?.sign ?: "", 9, true) ?: "",
                size = 18,
                color = Color.WHITE,
                FontUtils.nunitoExtraBold(context)
            )
        )
        val currentPriceSmallBitmap = if (forcedCompact) null else TextUtils.textToBitmap(
            context,
            TextUtils.DrawableText(
                priceChartData
                    .lastOrNull()
                    ?.get(1)
                    ?.toString(9, baseCurrency?.sign ?: "", 9, true) ?: "",
                size = 18,
                color = Color.WHITE,
                FontUtils.nunitoExtraBold(context)
            )
        )
        val priceDate1SmallBitmap = if (forcedCompact) null else TextUtils.textToBitmap(
            context,
            TextUtils.DrawableText(
                Date(firstEntry!![0].toLong() * 1000).formatDateAndTime(
                    config.period ?: MHistoryTimePeriod.DAY
                ),
                size = 14,
                color = Color.WHITE.colorWithAlpha(191),
                FontUtils.regular(context)
            )
        )
        val priceDate2SmallBitmap = if (forcedCompact) null else TextUtils.textToBitmap(
            context,
            TextUtils.DrawableText(
                Date(priceChartData.last()[0].toLong() * 1000).formatDateAndTime(
                    config.period ?: MHistoryTimePeriod.DAY
                ),
                size = 14,
                color = Color.WHITE.colorWithAlpha(191),
                FontUtils.regular(context)
            )
        )
        val smallHeaderRowSize =
            (symbolBitmap?.width ?: 0) + (priceChangeAndDateBitmap?.width ?: 0) + 74.dp
        val smallTopRowSize =
            (firstPriceSmallBitmap?.width ?: 0) + (currentPriceSmallBitmap?.width ?: 0) + 36.dp
        val smallBottomRowSize =
            (priceDate1SmallBitmap?.width ?: 0) + (priceDate2SmallBitmap?.width ?: 0) + 36.dp

        // DRAW SHARED BITMAPS /////////////////////////////////////////////////////////////////////
        views.setImageViewBitmap(
            R.id.img_background,
            BackgroundUtils.createCardBackground(baseColor, width ?: 200, height ?: 200)
        )
        views.setImageViewBitmap(R.id.text_symbol, symbolBitmap)

        // COMPACT MODE ////////////////////////////////////////////////////////////////////////////
        if (forcedCompact ||
            smallHeaderRowSize > (width?.dp ?: 0) ||
            smallTopRowSize > (width?.dp ?: 0) ||
            smallBottomRowSize > (width?.dp ?: 0)
        ) {
            drawChart(context, views, priceChartData, baseColor, width, height, true)
            views.setImageViewBitmap(R.id.text_change, null)
            // Price on left
            views.setImageViewBitmap(
                R.id.text_left, TextUtils.textToBitmap(
                    context,
                    TextUtils.DrawableText(
                        priceChartData
                            .lastOrNull()
                            ?.get(1)
                            ?.toString(9, baseCurrency?.sign ?: "", 9, true) ?: "",
                        size = 32,
                        color = Color.WHITE,
                        FontUtils.nunitoExtraBold(context)
                    )
                )
            )

            // Price change below price
            priceChangePercent?.let {
                views.setImageViewBitmap(R.id.text_bottom_left, priceChangeAndDateBitmap)
            }
            views.setImageViewBitmap(R.id.text_right, null)
            views.setImageViewBitmap(R.id.text_bottom_right, null)
        } else {
            drawChart(context, views, priceChartData, baseColor, width, height, false)
            views.setImageViewBitmap(
                R.id.text_change, TextUtils.textToBitmap(
                    context,
                    TextUtils.DrawableText(
                        "$sign${
                            String.format(
                                "%.2f",
                                kotlin.math.abs(priceChangePercent ?: 0.0)
                            )
                        }% · ${
                            priceChangeValue?.absoluteValue?.toString(
                                decimals = 9,
                                currency = baseCurrency?.sign ?: "",
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
            views.setImageViewBitmap(
                R.id.text_left, firstPriceSmallBitmap
            )
            views.setImageViewBitmap(
                R.id.text_bottom_left, priceDate1SmallBitmap
            )
            views.setImageViewBitmap(R.id.text_right, currentPriceSmallBitmap)
            views.setImageViewBitmap(R.id.text_bottom_right, priceDate2SmallBitmap)
        }

        return views
    }

    fun drawChart(
        context: Context,
        views: RemoteViews,
        priceChartData: Array<Array<Double>>,
        baseColor: Int,
        width: Int?,
        height: Int?,
        isCompact: Boolean
    ) {
        if (width != null && height != null)
            views.setImageViewBitmap(
                R.id.chart,
                ChartUtils.chartToBitmap(
                    context,
                    priceChartData,
                    baseColor = baseColor,
                    chartWidth = width.dp,
                    chartHeight = height.dp - 130.dp,
                    paddingBottom = if (isCompact) 80.dp else 68.dp
                )
            )
    }

    override fun onDeleted(context: Context, appWidgetIds: IntArray?) {
        WBaseStorage.init(context.applicationContext)
        appWidgetIds?.forEach { appWidgetId ->
            WBaseStorage.setWidgetConfigurations(appWidgetId, null)
        }
    }
}
