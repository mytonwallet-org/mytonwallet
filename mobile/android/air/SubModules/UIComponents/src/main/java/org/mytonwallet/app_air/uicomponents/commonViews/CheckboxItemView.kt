package org.mytonwallet.app_air.uicomponents.commonViews

import android.annotation.SuppressLint
import android.content.Context
import android.util.TypedValue
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import androidx.appcompat.widget.AppCompatImageView
import org.mytonwallet.app_air.uicomponents.AnimationConstants
import org.mytonwallet.app_air.uicomponents.drawable.CheckboxDrawable
import org.mytonwallet.app_air.uicomponents.drawable.WRippleDrawable
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.uicomponents.widgets.WView
import org.mytonwallet.app_air.walletbasecontext.theme.ViewConstants
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color

@SuppressLint("ViewConstructor")
class CheckboxItemView(context: Context, val isEnabledInitially: Boolean) : WView(context),
    WThemedView {

    private val ripple = WRippleDrawable.create(ViewConstants.BLOCK_RADIUS.dp)

    companion object {
        const val DISABLED_ALPHA_VALUE = 0.4f
    }

    private val checkboxDrawable = CheckboxDrawable {
        invalidate()
    }

    private val imageView = AppCompatImageView(context).apply {
        id = generateViewId()
        setImageDrawable(checkboxDrawable)
    }

    private val label = WLabel(context).apply {
        setStyle(16f)
        setLineHeight(TypedValue.COMPLEX_UNIT_SP, 24f)
        setTextColor(WColor.PrimaryText)
    }

    init {
        id = generateViewId()
        alpha = if (isEnabledInitially) 1f else DISABLED_ALPHA_VALUE
        isEnabled = isEnabledInitially
        background = ripple
    }

    override fun setupViews() {
        super.setupViews()

        addView(imageView, LayoutParams(22.dp, 22.dp))
        addView(label, LayoutParams(0, WRAP_CONTENT))
        setConstraints {
            toStart(imageView, 16f)
            toCenterY(imageView)
            toCenterY(label, 12f)
            startToEnd(label, imageView, 16f)
            toEnd(label, 16f)
        }

        updateTheme()
    }

    override fun updateTheme() {
        ripple.backgroundColor = WColor.Background.color
        ripple.rippleColor = WColor.BackgroundRipple.color

        checkboxDrawable.checkedColor = WColor.Tint.color
        checkboxDrawable.uncheckedColor = WColor.SecondaryText.color
    }

    fun setText(text: CharSequence) {
        label.text = text
    }

    var isChecked: Boolean = false
        set(value) {
            field = value
            checkboxDrawable.setChecked(value, true)
        }

    var isBoxEnabled: Boolean = isEnabledInitially
        set(value) {
            field = value
            isEnabled = value
            animate()
                .alpha(if (value) 1f else DISABLED_ALPHA_VALUE)
                .setDuration(AnimationConstants.VERY_QUICK_ANIMATION)
                .start()
            if (!value)
                isChecked = false
        }
}
