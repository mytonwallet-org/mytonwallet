package org.mytonwallet.app_air.uicomponents.commonViews

import android.annotation.SuppressLint
import android.content.Context
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.uicomponents.widgets.WView
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color

@SuppressLint("ViewConstructor")
class WEmptyView(
    context: Context,
    val title: String,
    val text: String
) : WView(context), WThemedView {

    private val titleLabel: WLabel by lazy {
        val v = WLabel(context)
        v.setStyle(16f, WFont.Medium)
        v.textAlignment = TEXT_ALIGNMENT_CENTER
        v
    }

    private val textLabel: WLabel by lazy {
        val v = WLabel(context)
        v.setStyle(14f)
        v.textAlignment = TEXT_ALIGNMENT_CENTER
        v
    }

    override fun setupViews() {
        super.setupViews()

        addView(titleLabel)
        addView(textLabel)

        setConstraints {
            toTop(titleLabel, 40f)
            toCenterX(titleLabel)
            topToBottom(textLabel, titleLabel, 8F)
            toCenterX(textLabel)
            toBottom(textLabel)
        }

        titleLabel.text = title
        textLabel.text = text

        updateTheme()
    }

    override fun updateTheme() {
        titleLabel.setTextColor(WColor.PrimaryText.color)
        textLabel.setTextColor(WColor.SecondaryText.color)
    }
}
