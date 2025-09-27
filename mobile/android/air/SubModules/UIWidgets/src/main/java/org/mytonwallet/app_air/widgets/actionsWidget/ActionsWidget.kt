package org.mytonwallet.app_air.widgets.actionsWidget

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.os.Build
import android.util.SizeF
import android.view.View
import android.widget.RemoteViews
import androidx.core.content.ContextCompat
import org.json.JSONObject
import org.mytonwallet.app_air.walletbasecontext.WBaseStorage
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.widgets.R
import org.mytonwallet.app_air.widgets.utils.DeeplinkUtils
import org.mytonwallet.app_air.widgets.utils.FontUtils
import org.mytonwallet.app_air.widgets.utils.TextUtils

class ActionsWidget : AppWidgetProvider() {
    data class Config(val style: Style) {
        enum class Style(val value: Int) {
            VIVID(1),
            NATURAL(2);

            companion object {
                fun fromValue(value: Int?): Style =
                    entries.find { it.value == value } ?: VIVID
            }
        }

        constructor(config: JSONObject?) : this(
            style = Style.fromValue(config?.optInt("style"))
        )

        fun toJson(): JSONObject =
            JSONObject().put("style", style.value)
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

    fun updateAppWidget(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetId: Int
    ) {
        val config = Config(config = WBaseStorage.getWidgetConfigurations(appWidgetId))
        val remoteViews = generateRemoteViews(context, config, false)
        appWidgetManager.updateAppWidget(appWidgetId, remoteViews)
    }

    // TODO:: Support account id tint colors...
    fun generateRemoteViews(context: Context, config: Config, isPreview: Boolean): RemoteViews {
        if (isPreview) {
            return RemoteViews(context.packageName, R.layout.actions_widget_mini).apply {
                configure(context, this@apply, false, config, true)
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
            // TODO:: How to handle different displays?!
            RemoteViews(context.packageName, R.layout.actions_widget).apply {
                configure(context, this@apply, false, config)
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
        val sendString = LocaleController.getString("\$send_action")
        val swapString = LocaleController.getString("Swap")
        val earnString = LocaleController.getString("Earn")

        var iconColor = Color.WHITE
        if (config.style == Config.Style.NATURAL) {
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
            remoteViews.setImageViewBitmap(
                R.id.text_add,
                TextUtils.textToBitmap(
                    context, TextUtils.DrawableText(
                        addString,
                        15,
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
                        15,
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
                        15,
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
                        15,
                        iconColor,
                        typeface
                    )
                )
            )
        }
    }

    override fun onDeleted(context: Context?, appWidgetIds: IntArray?) {
        super.onDeleted(context, appWidgetIds)
        appWidgetIds?.forEach { appWidgetId ->
            WBaseStorage.setWidgetConfigurations(appWidgetId, null)
        }
    }
}
