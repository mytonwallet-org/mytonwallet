package org.mytonwallet.app_air.uiwidgets.configurations.actionsWidget.views

import android.content.Context
import androidx.constraintlayout.widget.ConstraintSet
import org.mytonwallet.app_air.uicomponents.drawable.SeparatorBackgroundDrawable
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.widgets.WBaseView
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.uicomponents.widgets.WView
import org.mytonwallet.app_air.uicomponents.widgets.setBackgroundColor
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.theme.ThemeManager
import org.mytonwallet.app_air.walletbasecontext.theme.ViewConstants
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.widgets.actionsWidget.ActionsWidget

class ActionsStyleView(
    context: Context,
) : WView(context), WThemedView {

    private val titleLabel: WLabel by lazy {
        val lbl = WLabel(context)
        lbl.text = LocaleController.getString("Theme")
        lbl.setStyle(16f, WFont.Medium)
        lbl
    }

    private val separatorBackgroundDrawable: SeparatorBackgroundDrawable by lazy {
        SeparatorBackgroundDrawable().apply {
            backgroundWColor = WColor.Background
        }
    }

    private val vividView = ActionsStyleItemView(
        context,
        ActionsWidget.Config.Style.VIVID,
        onSelect = {
            selectedStyle = it
            updateSelection()
        }
    )
    private val neutralView = ActionsStyleItemView(
        context,
        ActionsWidget.Config.Style.NEUTRAL,
        onSelect = {
            selectedStyle = it
            updateSelection()
        }
    )

    private val themeView: WView by lazy {
        val v = WView(context)
        v.addView(vividView, LayoutParams(LayoutParams.WRAP_CONTENT, LayoutParams.WRAP_CONTENT))
        v.addView(
            neutralView,
            LayoutParams(LayoutParams.WRAP_CONTENT, LayoutParams.WRAP_CONTENT)
        )
        v.setConstraints {
            toTop(vividView)
            toLeft(vividView)
            leftToRight(neutralView, vividView)
            leftToRight(neutralView, vividView)
            toRight(neutralView)
            toBottom(neutralView)
            createHorizontalChain(
                ConstraintSet.PARENT_ID, ConstraintSet.LEFT,
                ConstraintSet.PARENT_ID, ConstraintSet.RIGHT,
                intArrayOf(vividView.id, neutralView.id),
                null,
                ConstraintSet.CHAIN_SPREAD
            )
        }
        v
    }

    var selectedStyle = ActionsWidget.Config.Style.VIVID

    override fun setupViews() {
        super.setupViews()

        addView(titleLabel)
        addView(themeView, LayoutParams(0, LayoutParams.WRAP_CONTENT))

        setConstraints {
            toTop(titleLabel, 16f)
            toStart(titleLabel, 20f)
            topToBottom(themeView, titleLabel, 24f)
            toCenterX(themeView)
            toBottom(themeView, 20f)
        }

        arrayOf(vividView, neutralView).forEach {
            it.isActive = selectedStyle == it.identifier
        }
        updateTheme()
    }

    private fun updateSelection() {
        arrayOf(vividView, neutralView).forEach {
            it.isActive = selectedStyle == it.identifier
            it.updateTheme()
        }
    }

    override fun updateTheme() {
        setBackgroundColor(
            WColor.Background.color,
            ViewConstants.BLOCK_RADIUS.dp
        )
        titleLabel.setTextColor(WColor.Tint.color)
    }

}
