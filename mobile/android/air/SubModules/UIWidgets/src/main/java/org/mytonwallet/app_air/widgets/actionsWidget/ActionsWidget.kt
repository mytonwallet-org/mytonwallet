package org.mytonwallet.app_air.widgets.actionsWidget

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.res.Configuration
import android.graphics.Color
import android.os.Build
import android.os.Bundle
import android.util.SizeF
import android.view.View
import android.widget.RemoteViews
import androidx.core.content.ContextCompat
import org.json.JSONObject
import org.mytonwallet.app_air.walletbasecontext.WBaseStorage
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.localization.WLanguage
import org.mytonwallet.app_air.widgets.R
import org.mytonwallet.app_air.widgets.utils.DeeplinkUtils
import org.mytonwallet.app_air.widgets.utils.FontUtils
import org.mytonwallet.app_air.widgets.utils.TextUtils

// TODO:: Support account id tint colors...
class ActionsWidget : AppWidgetProvider() {
    data class Config(
        val style: Style,
        var appWidgetMinWidth: Int? = null,
        var appWidgetMinHeight: Int? = null,
        var appWidgetMaxWidth: Int? = null,
        var appWidgetMaxHeight: Int? = null
    ) {
        enum class Style(val value: Int) {
            VIVID(1),
            NEUTRAL(2);

            companion object {
                fun fromValue(value: Int?): Style =
                    entries.find { it.value == value } ?: VIVID
            }
        }

        constructor(config: JSONObject?) : this(
            style = Style.fromValue(config?.optInt("style")),
            appWidgetMinWidth = config?.optInt("appWidgetMinWidth").let {
                if ((it ?: 0) > 0) it else null
            },
            appWidgetMinHeight = config?.optInt("appWidgetMinHeight").let {
                if ((it ?: 0) > 0) it else null
            },
            appWidgetMaxWidth = config?.optInt("appWidgetMaxWidth").let {
                if ((it ?: 0) > 0) it else null
            },
            appWidgetMaxHeight = config?.optInt("appWidgetMaxHeight").let {
                if ((it ?: 0) > 0) it else null
            },
        )

        fun toJson(): JSONObject =
            JSONObject()
                .put("style", style.value)
                .put("appWidgetMinWidth", appWidgetMinWidth)
                .put("appWidgetMinHeight", appWidgetMinHeight)
                .put("appWidgetMaxWidth", appWidgetMaxWidth)
                .put("appWidgetMaxHeight", appWidgetMaxHeight)
    }

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
        WBaseStorage.init(context)
        LocaleController.init(context, WBaseStorage.getActiveLanguage())
        for (appWidgetId in appWidgetIds) {
            updateAppWidget(context, appWidgetManager, appWidgetId)
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
        if (minWidth == 0 || minHeight == 0)
            return
        WBaseStorage.init(context)
        val config = WBaseStorage.getWidgetConfigurations(appWidgetId) ?: JSONObject()
        WBaseStorage.setWidgetConfigurations(appWidgetId, config.apply {
            put("appWidgetMinWidth", minWidth)
            put("appWidgetMinHeight", minHeight)
            put("appWidgetMaxWidth", maxWidth)
            put("appWidgetMaxHeight", maxHeight)
        })
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) {
            // On older devices, handle size change manually
            appWidgetManager?.let {
                updateAppWidget(context, appWidgetManager, appWidgetId)
            }
        }
    }

    fun updateAppWidget(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetId: Int
    ) {
        val config = Config(config = WBaseStorage.getWidgetConfigurations(appWidgetId))
        if (config.appWidgetMinWidth == null || config.appWidgetMinHeight == null) {
            val options = appWidgetManager.getAppWidgetOptions(appWidgetId)
            config.appWidgetMinWidth =
                options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH)
            config.appWidgetMinHeight =
                options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT)
            config.appWidgetMaxWidth =
                options.getInt(AppWidgetManager.OPTION_APPWIDGET_MAX_WIDTH)
            config.appWidgetMaxHeight =
                options.getInt(AppWidgetManager.OPTION_APPWIDGET_MAX_HEIGHT)
            WBaseStorage.setWidgetConfigurations(appWidgetId, config.toJson())
        }
        WBaseStorage.setWidgetConfigurations(appWidgetId, config.toJson())
        val remoteViews = generateRemoteViews(context, config, false)
        appWidgetManager.updateAppWidget(appWidgetId, remoteViews)
    }

    val set =
        setOf(R.layout.actions_widget, R.layout.actions_widget_tall, R.layout.actions_widget_wide)

    fun layoutHasTexts(layoutId: Int): Boolean {
        return set.contains(layoutId)
    }

    fun generateRemoteViews(context: Context, config: Config, isPreview: Boolean): RemoteViews {
        if (isPreview) {
            return RemoteViews(context.packageName, R.layout.actions_widget_preview).apply {
                configure(context, this@apply, true, config, true)
            }
        }
        val remoteViews = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val miniView = RemoteViews(context.packageName, R.layout.actions_widget_mini)
            val miniTallView = RemoteViews(context.packageName, R.layout.actions_widget_mini_tall)
            val miniWideView = RemoteViews(context.packageName, R.layout.actions_widget_mini_wide)
            val normalView = RemoteViews(context.packageName, R.layout.actions_widget)
            val tallView = RemoteViews(context.packageName, R.layout.actions_widget_tall)
            val wideView = RemoteViews(context.packageName, R.layout.actions_widget_wide)
            configure(context, miniView, false, config)
            configure(context, miniTallView, false, config)
            configure(context, miniWideView, false, config)
            configure(context, normalView, true, config)
            configure(context, tallView, true, config)
            configure(context, wideView, true, config)

            val viewMapping: Map<SizeF, RemoteViews> = mapOf(
                SizeF(0f, 0f) to miniView,
                SizeF(50f, 50f) to normalView,
                SizeF(50f, 110f) to miniTallView,
                SizeF(100f, 50f) to miniWideView,
                SizeF(50f, 250f) to tallView,
                SizeF(200f, 50f) to wideView,
                SizeF(150f, 150f) to normalView,
            )
            RemoteViews(viewMapping)
        } else {
            val orientation = context.resources.configuration.orientation
            val isLandscape = orientation == Configuration.ORIENTATION_LANDSCAPE
            val width =
                (if (isLandscape) config.appWidgetMaxWidth else config.appWidgetMinWidth) ?: 1000
            val height =
                (if (isLandscape) config.appWidgetMinHeight else config.appWidgetMaxHeight) ?: 1000
            val layoutId = when {
                width < 120 && height < 120 -> R.layout.actions_widget_mini
                width < 120 && height >= 120 -> R.layout.actions_widget_mini_tall
                width >= 120 && height < 120 -> R.layout.actions_widget_mini_wide
                width < 190 && height >= 190 -> R.layout.actions_widget_tall
                width >= 190 && height < 190 -> R.layout.actions_widget_wide
                else -> R.layout.actions_widget
            }
            RemoteViews(context.packageName, layoutId).apply {
                configure(context, this@apply, layoutHasTexts(layoutId), config)
            }
        }
        return remoteViews
    }

    private fun configure(
        context: Context,
        remoteViews: RemoteViews,
        renderTexts: Boolean,
        config: Config,
        isPreview: Boolean = false
    ) {
        val addString = LocaleController.getString("Add")
        val sendString = LocaleController.getString("Send")
        val swapString = LocaleController.getString("Swap")
        val earnString = LocaleController.getString("Earn")

        var iconColor = Color.WHITE
        if (config.style == Config.Style.NEUTRAL) {
            iconColor = ContextCompat.getColor(context, R.color.widget_tint)
            remoteViews.setInt(
                R.id.container,
                "setBackgroundResource",
                R.drawable.bg_widget_background_rounded
            )
            remoteViews.setViewVisibility(R.id.img_background, View.GONE)
            arrayOf(R.id.img_add, R.id.img_send, R.id.img_swap, R.id.img_earn).forEach {
                remoteViews.setInt(it, "setColorFilter", iconColor)
            }
            arrayOf(R.id.action_add, R.id.action_send, R.id.action_swap, R.id.action_earn).forEach {
                remoteViews.setInt(
                    it,
                    "setBackgroundResource",
                    if (renderTexts) R.drawable.bg_background_ripple else R.drawable.bg_background_0_ripple
                )
            }
        }
        if (!isPreview) {
            DeeplinkUtils.setOnClickDeeplink(context, remoteViews, R.id.action_add, "mtw://receive")
            DeeplinkUtils.setOnClickDeeplink(
                context,
                remoteViews,
                R.id.action_send,
                "mtw://transfer"
            )
            DeeplinkUtils.setOnClickDeeplink(context, remoteViews, R.id.action_swap, "mtw://swap")
            DeeplinkUtils.setOnClickDeeplink(context, remoteViews, R.id.action_earn, "mtw://stake")
        }
        remoteViews.setContentDescription(R.id.action_add, addString)
        remoteViews.setContentDescription(R.id.action_send, sendString)
        remoteViews.setContentDescription(R.id.action_swap, swapString)
        remoteViews.setContentDescription(R.id.action_earn, earnString)
        if (renderTexts) {
            val typeface = FontUtils.semiBold(context)
            val textSize =
                if (WBaseStorage.getActiveLanguage() == WLanguage.RUSSIAN.langCode) 12 else 15
            remoteViews.setImageViewBitmap(
                R.id.text_add,
                TextUtils.textToBitmap(
                    context, TextUtils.DrawableText(
                        addString,
                        textSize,
                        iconColor,
                        typeface
                    )
                )
            )
            remoteViews.setImageViewBitmap(
                R.id.text_send,
                TextUtils.textToBitmap(
                    context, TextUtils.DrawableText(
                        sendString,
                        textSize,
                        iconColor,
                        typeface
                    )
                )
            )
            remoteViews.setImageViewBitmap(
                R.id.text_swap,
                TextUtils.textToBitmap(
                    context, TextUtils.DrawableText(
                        swapString,
                        textSize,
                        iconColor,
                        typeface
                    )
                )
            )
            remoteViews.setImageViewBitmap(
                R.id.text_earn,
                TextUtils.textToBitmap(
                    context, TextUtils.DrawableText(
                        earnString,
                        textSize,
                        iconColor,
                        typeface
                    )
                )
            )
        }
    }

    override fun onDeleted(context: Context?, appWidgetIds: IntArray?) {
        super.onDeleted(context, appWidgetIds)
        val context = context ?: return
        WBaseStorage.init(context.applicationContext)
        appWidgetIds?.forEach { appWidgetId ->
            WBaseStorage.setWidgetConfigurations(appWidgetId, null)
        }
    }
}
