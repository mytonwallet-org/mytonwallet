package org.mytonwallet.app_air.uiwidgets.configurations.actionsWidget.views

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Color
import android.view.View
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.uicomponents.widgets.WView
import org.mytonwallet.app_air.uicomponents.widgets.setBackgroundColor
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.widgets.actionsWidget.ActionsWidget

@SuppressLint("ViewConstructor")
class ActionsStyleItemView(
    context: Context,
    val identifier: ActionsWidget.Config.Style,
    val onSelect: ((style: ActionsWidget.Config.Style) -> Unit)
) : WView(context), WThemedView {

    var isActive: Boolean = false

    private val previewView: View by lazy {
        ActionsWidget().generateRemoteViews(context, ActionsWidget.Config(style = identifier), true)
            .apply(context, this)
    }

    private val nameLabel: WLabel by lazy {
        val lbl = WLabel(context)
        lbl.text = when (identifier) {
            ActionsWidget.Config.Style.NEUTRAL -> {
                LocaleController.getString("Neutral")
            }

            ActionsWidget.Config.Style.VIVID -> {
                LocaleController.getString("Vivid")
            }
        }
        lbl
    }

    override fun setupViews() {
        super.setupViews()

        addView(previewView, LayoutParams(155.dp, 155.dp))
        addView(nameLabel)
        setConstraints {
            toTop(previewView, 3f)
            toCenterX(previewView, 3f)
            topToBottom(nameLabel, previewView, 8f)
            toCenterX(nameLabel)
            toBottom(nameLabel, 8f)
        }

        setOnClickListener {
            onSelect(identifier)
        }

        updateTheme()
    }

    override fun updateTheme() {
        previewView.setBackgroundColor(WColor.Background.color, 20f.dp, true)
        setBackgroundColor(
            Color.TRANSPARENT,
            20f.dp,
            20f.dp,
            strokeColor = (if (isActive) WColor.Tint else WColor.Separator).color,
            strokeWidth = if (isActive) 3 else 2,
            clipToBounds = true
        )
        addRippleEffect(WColor.BackgroundRipple.color, 20f.dp)
        nameLabel.setTextColor((if (isActive) WColor.Tint else WColor.SecondaryText).color)
        nameLabel.setStyle(16f, if (isActive) WFont.Medium else WFont.Regular)
    }

}
