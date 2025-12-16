package org.mytonwallet.app_air.uiwidgets.configurations.actionsWidget

import android.appwidget.AppWidgetManager
import android.content.Context
import android.view.Gravity
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import androidx.constraintlayout.widget.ConstraintLayout
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.widgets.WButton
import org.mytonwallet.app_air.uiwidgets.configurations.WidgetConfigurationVC
import org.mytonwallet.app_air.uiwidgets.configurations.actionsWidget.views.ActionsStyleView
import org.mytonwallet.app_air.walletbasecontext.WBaseStorage
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.theme.ViewConstants
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.widgets.actionsWidget.ActionsWidget

class ActionsWidgetConfigurationVC(
    context: Context,
    override val appWidgetId: Int,
    override val onResult: (ok: Boolean) -> Unit
) :
    WidgetConfigurationVC(context) {
    override val TAG = "ActionsWidgetConfiguration"

    override val shouldDisplayTopBar = false

    val stylesView = ActionsStyleView(context)

    val continueButton = WButton(context, WButton.Type.PRIMARY).apply {
        text = LocaleController.getString("Continue")
        setOnClickListener {
            WBaseStorage.setWidgetConfigurations(
                appWidgetId,
                ActionsWidget.Config(style = stylesView.selectedStyle).toJson()
            )
            val appWidgetManager = AppWidgetManager.getInstance(context)
            ActionsWidget().updateAppWidget(context, appWidgetManager, appWidgetId)
            onResult(true)
        }
    }

    override fun setupViews() {
        super.setupViews()

        title = LocaleController.getString("Customize Widget")
        setupNavBar(true)
        navigationBar?.titleLabel?.setStyle(20f, WFont.SemiBold)
        navigationBar?.setTitleGravity(Gravity.CENTER)

        view.apply {
            addView(stylesView, ConstraintLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT))
            addView(continueButton, ConstraintLayout.LayoutParams(0, WRAP_CONTENT))
            setConstraints {
                topToBottom(stylesView, navigationBar!!, 16f)
                toCenterX(stylesView, ViewConstants.HORIZONTAL_PADDINGS.toFloat())
                toCenterX(continueButton, 20f)
                toBottomPx(
                    continueButton,
                    navigationController?.getSystemBars()?.bottom ?: 0
                )
            }
        }
    }

    override fun updateTheme() {
        super.updateTheme()
        view.setBackgroundColor(WColor.SecondaryBackground.color)
    }

    override fun insetsUpdated() {
        super.insetsUpdated()

        navigationBar?.setPadding(0, (navigationController?.getSystemBars()?.top) ?: 0, 0, 0)
        view.setConstraints {
            toBottomPx(
                continueButton,
                16.dp + (navigationController?.getSystemBars()?.bottom ?: 0)
            )
        }
    }
}
