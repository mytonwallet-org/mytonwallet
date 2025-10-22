package org.mytonwallet.app_air.uicomponents.commonViews.cells

import android.annotation.SuppressLint
import android.content.Context
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import org.mytonwallet.app_air.uicomponents.drawable.SeparatorBackgroundDrawable
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.widgets.WCell
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.uicomponents.widgets.WSwitch
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.uicomponents.widgets.setBackgroundColor
import org.mytonwallet.app_air.walletbasecontext.theme.ThemeManager
import org.mytonwallet.app_air.walletbasecontext.theme.ViewConstants
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color

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
        WLabel(context).apply {
            setStyle(16f)
            text = title
        }
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

        addView(titleLabel, LayoutParams(0, WRAP_CONTENT))
        addView(switchView)
        setConstraints {
            toStart(titleLabel, 20f)
            toCenterY(titleLabel)
            endToStart(titleLabel, switchView, 4f)
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

    fun setChecked(isChecked: Boolean) {
        switchView.isChecked = isChecked
    }
}
