package org.mytonwallet.app_air.uiwidgets.configurations.actionsWidget

import android.appwidget.AppWidgetManager
import android.content.Context
import android.view.Gravity
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import androidx.constraintlayout.widget.ConstraintLayout
import androidx.constraintlayout.widget.ConstraintLayout.LayoutParams.MATCH_CONSTRAINT
import org.mytonwallet.app_air.uicomponents.base.WNavigationBar
import org.mytonwallet.app_air.uicomponents.base.WWindow
import org.mytonwallet.app_air.uicomponents.commonViews.ReversedCornerViewUpsideDown
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.extensions.setPaddingLocalized
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.widgets.WButton
import org.mytonwallet.app_air.uicomponents.widgets.WScrollView
import org.mytonwallet.app_air.uicomponents.widgets.WView
import org.mytonwallet.app_air.uiwidgets.configurations.WidgetConfigurationVC
import org.mytonwallet.app_air.uiwidgets.configurations.actionsWidget.views.ActionsStyleView
import org.mytonwallet.app_air.walletbasecontext.WBaseStorage
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.theme.ViewConstants
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.widgets.actionsWidget.ActionsWidget
import java.lang.ref.WeakReference
import kotlin.math.roundToInt

class ActionsWidgetConfigurationVC(
    context: Context,
    override val appWidgetId: Int,
    override val onResult: (ok: Boolean) -> Unit
) :
    WidgetConfigurationVC(context) {
    override val TAG = "ActionsWidgetConfiguration"

    override val shouldDisplayBottomBar = false

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

    private val scrollingContentView: WView by lazy {
        val v = WView(context)
        v.addView(stylesView, ConstraintLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT))
        v.setConstraints {
            toTop(stylesView, 16f)
            toCenterX(stylesView)
            toBottom(stylesView)
        }
        v
    }

    private val scrollView: WScrollView by lazy {
        WScrollView(WeakReference(this)).apply {
            clipToPadding = false
            addView(scrollingContentView, ConstraintLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT))
            onScrollChange = { updateBlurViews(scrollView = this) }
        }
    }

    private val bottomReversedCornerViewUpsideDown: ReversedCornerViewUpsideDown by lazy {
        ReversedCornerViewUpsideDown(context, scrollView).apply {
            if (ignoreSideGuttering)
                setHorizontalPadding(0f)
        }
    }

    override fun setupViews() {
        super.setupViews()

        title = LocaleController.getString("Customize Widget")
        setupNavBar(true)
        navigationBar?.titleLabel?.setStyle(20f, WFont.Medium)
        navigationBar?.setTitleGravity(Gravity.CENTER)

        view.apply {
            addView(scrollView, ConstraintLayout.LayoutParams(0, 0).apply {
                matchConstraintMaxWidth = WWindow.WIDE_LAYOUT_INNER_WIDTH_DP.dp
            })
            addView(
                bottomReversedCornerViewUpsideDown,
                ConstraintLayout.LayoutParams(MATCH_PARENT, MATCH_CONSTRAINT)
            )
            addView(continueButton, ConstraintLayout.LayoutParams(0, WRAP_CONTENT).apply {
                matchConstraintMaxWidth = WWindow.WIDE_LAYOUT_INNER_WIDTH_DP.dp
            })
            setConstraints {
                toTop(scrollView)
                toCenterX(scrollView)
                toBottom(scrollView)
                toCenterX(continueButton, 20f)
                toBottomPx(
                    continueButton,
                    navigationController?.getSystemBars()?.bottom ?: 0
                )
                topToTop(
                    bottomReversedCornerViewUpsideDown,
                    continueButton,
                    -ViewConstants.GAP - ViewConstants.BLOCK_RADIUS
                )
                toBottom(bottomReversedCornerViewUpsideDown)
            }
        }
    }

    override fun updateTheme() {
        super.updateTheme()
        view.setBackgroundColor(WColor.SecondaryBackground.color)
    }

    override fun insetsUpdated() {
        super.insetsUpdated()

        scrollView.setPaddingLocalized(
            ViewConstants.HORIZONTAL_PADDINGS.dp + systemBarStartInset,
            (navigationController?.getSystemBars()?.top ?: 0) + WNavigationBar.DEFAULT_HEIGHT.dp,
            ViewConstants.HORIZONTAL_PADDINGS.dp + systemBarEndInset,
            16.dp +
                ViewConstants.BLOCK_RADIUS.dp.roundToInt() +
                continueButton.buttonHeight +
                (navigationController?.getSystemBars()?.bottom ?: 0)
        )
        view.setConstraints {
            toStartPx(continueButton, 20.dp + systemBarStartInset)
            toEndPx(continueButton, 20.dp + systemBarEndInset)
            toBottomPx(
                continueButton,
                16.dp + (navigationController?.getSystemBars()?.bottom ?: 0)
            )
        }
    }
}
