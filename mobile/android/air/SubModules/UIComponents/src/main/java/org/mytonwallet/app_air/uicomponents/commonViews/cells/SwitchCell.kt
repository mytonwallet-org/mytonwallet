package org.mytonwallet.app_air.uicomponents.commonViews.cells

import android.annotation.SuppressLint
import android.content.Context
import org.mytonwallet.app_air.uicomponents.drawable.SeparatorBackgroundDrawable
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.widgets.WCell
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.uicomponents.widgets.WSwitch
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.uicomponents.widgets.setBackgroundColor
import org.mytonwallet.app_air.walletcontext.theme.ThemeManager
import org.mytonwallet.app_air.walletcontext.theme.ViewConstants
import org.mytonwallet.app_air.walletcontext.theme.WColor
import org.mytonwallet.app_air.walletcontext.theme.color

@SuppressLint("ViewConstructor")
class SwitchCell(
    context: Context,
    title: String,
    isChecked: Boolean,
    val isFirst: Boolean = false,
    val isLast: Boolean = false,
    onChange: (checked: Boolean) -> Unit
) : WCell(context), WThemedView {

    private val titleLabel: WLabel by lazy {
        val lbl = WLabel(context)
        lbl.setStyle(16f)
        lbl.text = title
        lbl
    }

    private val switchView: WSwitch by lazy {
        val switchView = WSwitch(context)
        switchView.isChecked = isChecked
        switchView.setOnCheckedChangeListener { _, isChecked ->
            onChange(isChecked)
        }
        switchView
    }

    private val separatorBackgroundDrawable: SeparatorBackgroundDrawable by lazy {
        SeparatorBackgroundDrawable().apply {
            backgroundWColor = WColor.Background
            offsetStart = 20f.dp
        }
    }

    override fun setupViews() {
        super.setupViews()

        addView(titleLabel)
        addView(switchView)
        setConstraints {
            toStart(titleLabel, 20f)
            toCenterY(titleLabel)
            toEnd(switchView, 20f)
            toCenterY(switchView)
        }
        setOnClickListener {
            switchView.isChecked = !switchView.isChecked
        }

        updateTheme()
    }

    override fun updateTheme() {
        if (ThemeManager.uiMode.hasRoundedCorners) {
            setBackgroundColor(
                WColor.Background.color,
                if (isFirst) ViewConstants.BIG_RADIUS.dp else 0f,
                if (isLast) ViewConstants.BIG_RADIUS.dp else 0f
            )
        } else {
            separatorBackgroundDrawable.offsetStart = if (isLast) 0f else 16f.dp
            separatorBackgroundDrawable.offsetEnd = separatorBackgroundDrawable.offsetStart
            background = separatorBackgroundDrawable
        }
        addRippleEffect(WColor.SecondaryBackground.color)
        titleLabel.setTextColor(WColor.PrimaryText.color)
    }
}
