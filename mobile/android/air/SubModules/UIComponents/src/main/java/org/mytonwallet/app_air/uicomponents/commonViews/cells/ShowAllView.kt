package org.mytonwallet.app_air.uicomponents.commonViews.cells

import android.content.Context
import android.graphics.drawable.Drawable
import android.text.TextUtils
import android.view.View
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import androidx.appcompat.widget.AppCompatImageView
import androidx.constraintlayout.widget.ConstraintSet
import androidx.core.content.ContextCompat
import androidx.core.view.isVisible
import org.mytonwallet.app_air.uicomponents.drawable.WRippleDrawable
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.widgets.WCounterLabel
import org.mytonwallet.app_air.uicomponents.widgets.WImageButton
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.uicomponents.widgets.WView
import org.mytonwallet.app_air.uicomponents.widgets.setBackgroundColor
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import kotlin.math.roundToInt

class ShowAllView(
    context: Context,
) : WView(context), WThemedView {

    private val ripple = WRippleDrawable.create(0f)

    var onTap: (() -> Unit)? = null
    var onMenuTap: ((anchorView: WImageButton) -> Unit)? = null
        set(value) {
            field = value
            menuButton.visibility = if (value != null) VISIBLE else GONE
            updateTrailingViewsLayout()
        }

    private var iconDrawable: Drawable? = null
    private var menuDrawable: Drawable? = null

    private val iconView = AppCompatImageView(context).apply {
        id = generateViewId()
    }
    private val menuButton = WImageButton(context).apply {
        id = generateViewId()
        background = WRippleDrawable.create(20f.dp)
        setOnClickListener {
            onMenuTap?.invoke(this)
        }
        visibility = GONE
    }
    private val counterLabel = WCounterLabel(context).apply {
        id = generateViewId()
        textAlignment = TEXT_ALIGNMENT_CENTER
        setPadding(4.5f.dp.roundToInt(), 4.dp, 4.5f.dp.roundToInt(), 0)
        setStyle(11f, WFont.SemiBold)
        setGradientColor(arrayOf(WColor.SecondaryText, WColor.SecondaryText))
        setBackgroundColor(WColor.BadgeBackground.color, 8f.dp)
        isVisible = false
    }

    private val titleLabel: WLabel by lazy {
        WLabel(context).apply {
            id = generateViewId()
            setStyle(16f)
            setTextColor(WColor.PrimaryText)
            setSingleLine()
            ellipsize = TextUtils.TruncateAt.MARQUEE
            marqueeRepeatLimit = -1
            isHorizontalFadingEdgeEnabled = true
            isSelected = true
        }
    }

    init {
        background = ripple
        addView(iconView, LayoutParams(28.dp, 28.dp))
        addView(menuButton, LayoutParams(24.dp, 24.dp))
        addView(counterLabel, LayoutParams(WRAP_CONTENT, 16.dp))
        addView(titleLabel, LayoutParams(WRAP_CONTENT, WRAP_CONTENT))

        setOnClickListener {
            onTap?.invoke()
        }

        updateTrailingViewsLayout()
        updateTheme()
    }

    fun configure(icon: Int, text: String) {
        iconDrawable = ContextCompat.getDrawable(context, icon)?.apply {
            setTint(WColor.SecondaryText.color)
        }
        menuDrawable = ContextCompat.getDrawable(context, org.mytonwallet.app_air.icons.R.drawable.ic_more)?.apply {
            setTint(WColor.SecondaryText.color)
        }
        iconView.setImageDrawable(iconDrawable)
        menuButton.setImageDrawable(menuDrawable)
        titleLabel.text = text
    }

    fun setCounter(value: Int?) {
        val count = value ?: 0
        val shouldShow = count > 0
        if (shouldShow) {
            counterLabel.setAmount(count.toString())
        }
        counterLabel.isVisible = shouldShow
        updateTrailingViewsLayout()
    }

    private fun updateTrailingViewsLayout() {
        val isMenuVisible = menuButton.isVisible
        setConstraints {
            toStart(iconView, 20f)
            toCenterY(iconView)

            toEnd(menuButton, 20f)
            toCenterY(menuButton)

            startToEnd(titleLabel, iconView, 20f)
            toCenterY(titleLabel)
            setHorizontalBias(titleLabel.id, 0f)
            constrainedWidth(titleLabel.id, true)

            toCenterY(counterLabel)
            clear(counterLabel.id, ConstraintSet.START)
            clear(counterLabel.id, ConstraintSet.END)

            if (counterLabel.isVisible) {
                endToStart(titleLabel, counterLabel, 4f)
                startToEnd(counterLabel, titleLabel, 4f)
                if (isMenuVisible) {
                    endToStart(counterLabel, menuButton, 8f)
                } else {
                    toEnd(counterLabel, 20f)
                }
                setHorizontalBias(counterLabel.id, 0f)
                setHorizontalBias(titleLabel.id, 0f)
                setHorizontalChainStyle(titleLabel.id, ConstraintSet.CHAIN_PACKED)
            } else {
                if (isMenuVisible) {
                    endToStart(titleLabel, menuButton, 12f)
                } else {
                    toEnd(titleLabel, 20f)
                }
                setHorizontalChainStyle(titleLabel.id, ConstraintSet.CHAIN_SPREAD)
            }
        }
    }

    override fun updateTheme() {
        ripple.rippleColor = WColor.BackgroundRipple.color
        iconDrawable?.setTint(WColor.SecondaryText.color)
        menuDrawable?.setTint(WColor.SecondaryText.color)
        counterLabel.setGradientColor(arrayOf(WColor.SecondaryText, WColor.SecondaryText))
        counterLabel.setBackgroundColor(WColor.BadgeBackground.color, 8f.dp)
        menuButton.updateColors(WColor.SecondaryText, WColor.BackgroundRipple)
    }

}
