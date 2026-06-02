package org.mytonwallet.app_air.uicomponents.commonViews.cells

import android.annotation.SuppressLint
import org.mytonwallet.app_air.uicomponents.helpers.adaptiveFontSize
import android.content.Context
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import androidx.appcompat.widget.AppCompatImageView
import org.mytonwallet.app_air.uicomponents.drawable.SeparatorBackgroundDrawable
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.widgets.WCell
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.uicomponents.widgets.WSwitch
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.uicomponents.widgets.setBackgroundColor
import org.mytonwallet.app_air.walletbasecontext.theme.ViewConstants
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletbasecontext.utils.getDrawableCompat

@SuppressLint("ViewConstructor")
class SwitchCell(
    context: Context,
    title: String,
    isChecked: Boolean,
    var isFirst: Boolean = false,
    var isLast: Boolean = false,
    private val leadingIconRes: Int? = null,
    onChange: (checked: Boolean) -> Unit
) : WCell(context), WThemedView {

    fun setIsLast(value: Boolean) {
        isLast = value
        updateTheme()
    }

    private val titleLabel: WLabel by lazy {
        WLabel(context).apply {
            setStyle(adaptiveFontSize())
            text = title
        }
    }

    private val leadingIconView: AppCompatImageView? by lazy {
        leadingIconRes?.let {
            AppCompatImageView(context).apply {
                id = generateViewId()
                setImageDrawable(context.getDrawableCompat(it))
            }
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

    var isChecked: Boolean
        get() = switchView.isChecked
        set(value) {
            switchView.isChecked = value
        }

    override fun setEnabled(enabled: Boolean) {
        super.setEnabled(enabled)
        switchView.isEnabled = enabled
        alpha = if (enabled) 1f else 0.5f
    }

    override fun setupViews() {
        super.setupViews()

        addView(titleLabel, LayoutParams(0, WRAP_CONTENT))
        addView(switchView)
        leadingIconView?.let { addView(it, LayoutParams(28.dp, 28.dp)) }
        setConstraints {
            val icon = leadingIconView
            if (icon != null) {
                toStart(icon, 18f)
                toCenterY(icon)
                startToEnd(titleLabel, icon, 14f)
            } else {
                toStart(titleLabel, 20f)
            }
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
        setBackgroundColor(
            WColor.Background.color,
            if (isFirst) ViewConstants.BLOCK_RADIUS.dp else 0f,
            if (isLast) ViewConstants.BLOCK_RADIUS.dp else 0f
        )
        addRippleEffect(WColor.SecondaryBackground.color)
        titleLabel.setTextColor(WColor.PrimaryText.color)
    }
}
