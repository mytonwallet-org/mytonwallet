package org.mytonwallet.app_air.uiwidgets.configurations.views

import android.annotation.SuppressLint
import android.content.Context
import android.view.View
import android.view.ViewGroup
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import android.widget.RemoteViews
import com.google.android.material.progressindicator.CircularProgressIndicator
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.uicomponents.widgets.WView
import org.mytonwallet.app_air.uicomponents.widgets.fadeIn
import org.mytonwallet.app_air.uicomponents.widgets.fadeOut
import org.mytonwallet.app_air.uicomponents.widgets.setBackgroundColor
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.theme.ViewConstants
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color

@SuppressLint("ViewConstructor")
class WidgetPreviewView(context: Context) : WView(context), WThemedView {

    companion object {
        const val WIDTH = 250
        const val HEIGHT = 180
    }

    private var progressIndicator: CircularProgressIndicator? = null
    private var isLoadingPreview: Boolean = true
        set(value) {
            field = value
            updateLoadingState()
        }

    private val titleLabel: WLabel by lazy {
        WLabel(context).apply {
            text = LocaleController.getString("Preview")
            setStyle(16f, WFont.Medium)
            setTextColor(WColor.Tint)
        }
    }

    private var widgetView: View? = null

    override fun setupViews() {
        super.setupViews()

        addView(titleLabel)
        widgetView?.let {
            addView(widgetView, LayoutParams(WIDTH.dp, HEIGHT.dp))
        }

        setConstraints {
            toTop(titleLabel, 16f)
            toStart(titleLabel, 20f)
            toBottom(titleLabel, HEIGHT + 44f)
            widgetView?.let { widgetView ->
                topToBottom(widgetView, titleLabel, 24f)
                toCenterX(widgetView)
            }
        }

        updateTheme()
    }

    override fun updateTheme() {
        setBackgroundColor(
            WColor.Background.color,
            ViewConstants.TOOLBAR_RADIUS.dp,
            ViewConstants.BLOCK_RADIUS.dp
        )
        progressIndicator?.setIndicatorColor(WColor.SecondaryText.color)
    }

    fun setWidget(newWidgetView: RemoteViews?) {
        isLoadingPreview = newWidgetView == null
        newWidgetView?.let {
            removeView(widgetView)
            val widgetView = newWidgetView.apply(context, this).apply {
                id = generateViewId()
            }
            addView(widgetView, LayoutParams(WIDTH.dp, HEIGHT.dp))
            setConstraints {
                widgetView?.let { widgetView ->
                    topToBottom(widgetView, titleLabel, 24f)
                    toCenterX(widgetView)
                }
            }
            if (this.widgetView == null) {
                this.widgetView = widgetView
                widgetView.alpha = 0f
                widgetView?.fadeIn(onCompletion = {
                    if (this.widgetView != null) {
                        progressIndicator?.visibility = GONE
                    }
                })
            } else {
                this.widgetView = widgetView
            }
        } ?: run {
            widgetView?.let { it ->
                it.fadeOut(onCompletion = {
                    removeView(it)
                })
                this.widgetView = null
            }
        }
    }

    private fun updateLoadingState() {
        if (progressIndicator == null) {
            progressIndicator = CircularProgressIndicator(context).apply {
                id = generateViewId()
                isIndeterminate = true
                setIndicatorColor(WColor.SecondaryText.color)
                indicatorSize = 28.dp
            }
            addView(
                progressIndicator,
                ViewGroup.LayoutParams(WRAP_CONTENT, WRAP_CONTENT)
            )
            setConstraints {
                toCenterX(progressIndicator!!)
                toBottom(progressIndicator!!, 20 + HEIGHT / 2 - 14f)
            }
        }
        if (isLoadingPreview) {
            progressIndicator?.visibility = VISIBLE
        } else {
            progressIndicator?.visibility = GONE
        }
    }
}
