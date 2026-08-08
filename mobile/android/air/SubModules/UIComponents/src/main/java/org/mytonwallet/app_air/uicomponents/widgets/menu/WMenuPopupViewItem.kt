package org.mytonwallet.app_air.uicomponents.widgets.menu

import android.annotation.SuppressLint
import android.content.Context
import android.text.TextUtils
import android.view.Gravity
import android.view.View
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import androidx.appcompat.widget.AppCompatImageView
import kotlin.math.roundToInt
import org.mytonwallet.app_air.icons.R
import org.mytonwallet.app_air.uicomponents.drawable.WRippleDrawable
import org.mytonwallet.app_air.uicomponents.extensions.atMost
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.extensions.unspecified
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.helpers.adaptiveFontSize
import org.mytonwallet.app_air.uicomponents.widgets.WFrameLayout
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletbasecontext.utils.getDrawableCompat

interface WMenuPopupExpandableTrailingView {
    fun setSubmenuExpansionProgress(progress: Float)
}

@SuppressLint("ViewConstructor")
class WMenuPopupViewItem(context: Context, val item: WMenuPopup.Item) :
    WFrameLayout(context),
    WThemedView {

    private val ripple = WRippleDrawable.create(0f)

    init {
        background = ripple
        clipChildren = false
        clipToPadding = false
    }

    private val hasSubtitle = !item.getSubTitle().isNullOrEmpty()

    private val label = WLabel(context).apply {
        setStyle(adaptiveFontSize(), if (hasSubtitle) WFont.Medium else WFont.Regular)
        setSingleLine()
        ellipsize = TextUtils.TruncateAt.END
        text = item.getTitle()
    }

    private val subtitleLabel = if (hasSubtitle) {
        WLabel(context).apply {
            setStyle(12f)
            setSingleLine()
            ellipsize = TextUtils.TruncateAt.END
            text = item.getSubTitle()
            applyFontOffsetFix = true
        }
    } else {
        null
    }

    private val hasIcon = item.getIcon() != null || item.getIconDrawable() != null
    private val iconView = if (hasIcon) AppCompatImageView(context) else null
    private val separatorView = if (item.hasSeparator) View(context) else null
    private val arrowView = if (item.getSubItems() != null) AppCompatImageView(context) else null
    private val trailingView = (item.config as? WMenuPopup.Item.Config.Item)?.let { config ->
        config.trailingViewProvider?.invoke() ?: config.trailingView
    }
    private val arrowReserve = if (arrowView != null) 30.dp + 8.dp else 16.dp

    private val textMargin: Int
        get() {
            return if (
                hasIcon ||
                item.getIsSubItem() ||
                item.config is WMenuPopup.Item.Config.SelectableItem
            ) {
                item.getTextMargin() ?: 58.dp
            } else {
                16.dp
            }
        }

    init {
        addView(
            label,
            LayoutParams(WRAP_CONTENT, WRAP_CONTENT).apply {
                if (hasSubtitle) {
                    gravity = if (LocaleController.isRTL) Gravity.RIGHT else Gravity.LEFT
                    topMargin = 7.dp
                } else {
                    gravity =
                        Gravity.CENTER_VERTICAL or
                        (if (LocaleController.isRTL) Gravity.RIGHT else Gravity.LEFT)
                    bottomMargin = if (item.hasSeparator) 3.5f.dp.roundToInt() else 0
                }
                if (LocaleController.isRTL) {
                    rightMargin = textMargin
                    if (arrowView != null) leftMargin = arrowReserve
                } else {
                    leftMargin = textMargin
                    if (arrowView != null) rightMargin = arrowReserve
                }
            }
        )
        subtitleLabel?.let {
            addView(
                it,
                LayoutParams(WRAP_CONTENT, WRAP_CONTENT).apply {
                    gravity = Gravity.BOTTOM or
                        if (LocaleController.isRTL) Gravity.RIGHT else Gravity.LEFT
                    bottomMargin = if (item.hasSeparator) 13.dp else 6.dp
                    if (LocaleController.isRTL) {
                        rightMargin = textMargin
                    } else {
                        leftMargin = textMargin
                    }
                }
            )
        }
        if (hasIcon) {
            if (LocaleController.isRTL && item.config is WMenuPopup.Item.Config.Back) {
                iconView?.scaleX = -1f
            }
            val iconSize = item.getIconSize() ?: if (hasSubtitle) 36.dp else 30.dp
            addView(
                iconView,
                LayoutParams(iconSize, iconSize).apply {
                    val startMargin = item.getIconMargin() ?: if (hasSubtitle) {
                        10.dp
                    } else {
                        (16.dp - ((item.getIconSize() ?: 30.dp) - 30.dp) / 3f).roundToInt()
                    }
                    if (LocaleController.isRTL) {
                        rightMargin = startMargin
                    } else {
                        leftMargin = startMargin
                    }
                    gravity = Gravity.CENTER_VERTICAL or
                        (if (LocaleController.isRTL) Gravity.RIGHT else Gravity.LEFT)
                    bottomMargin = if (item.hasSeparator) 3.5f.dp.roundToInt() else 0
                }
            )
        }
        if (item.hasSeparator) {
            addView(
                separatorView,
                LayoutParams(LayoutParams.MATCH_PARENT, 7.dp).apply {
                    gravity = Gravity.BOTTOM
                }
            )
        }
        if (!item.getSubItems().isNullOrEmpty()) {
            if (LocaleController.isRTL) arrowView?.scaleX = -1f
            addView(
                arrowView,
                LayoutParams(30.dp, 30.dp).apply {
                    gravity = Gravity.CENTER_VERTICAL or
                        if (LocaleController.isRTL) Gravity.LEFT else Gravity.RIGHT
                    if (LocaleController.isRTL) leftMargin = 8.dp else rightMargin = 8.dp
                    bottomMargin = if (item.hasSeparator) 3.5f.dp.roundToInt() else 0
                }
            )
        }
        trailingView?.let {
            addView(
                it,
                LayoutParams(WRAP_CONTENT, WRAP_CONTENT).apply {
                    gravity = Gravity.CENTER_VERTICAL or
                        if (LocaleController.isRTL) Gravity.LEFT else Gravity.RIGHT
                    if (LocaleController.isRTL) leftMargin = 12.dp else rightMargin = 12.dp
                    bottomMargin = if (item.hasSeparator) 3.5f.dp.roundToInt() else 0
                }
            )
            if (arrowView != null) {
                arrowView.alpha = 0f
            }
        }
        updateTheme()
    }

    private var measuredTextWidth = -1

    override fun onSizeChanged(w: Int, h: Int, oldw: Int, oldh: Int) {
        super.onSizeChanged(w, h, oldw, oldh)
        val endReserve = maxOf(
            arrowReserve,
            (trailingView?.measuredWidth ?: 0) + if (trailingView == null) 0 else 24.dp
        )
        val availableTextWidth = (w - textMargin - endReserve).coerceAtLeast(0)
        if (measuredTextWidth == availableTextWidth) return
        measuredTextWidth = availableTextWidth
        label.maxWidth = availableTextWidth
        subtitleLabel?.maxWidth = availableTextWidth
        label.measure(availableTextWidth.atMost, 0.unspecified)
        subtitleLabel?.measure(availableTextWidth.atMost, 0.unspecified)
    }

    fun setSubmenuExpansionProgress(progress: Float) {
        val safeProgress = progress.coerceIn(0f, 1f)
        (trailingView as? WMenuPopupExpandableTrailingView)?.let {
            it.setSubmenuExpansionProgress(safeProgress)
            return
        }
        arrowView?.rotation = (if (LocaleController.isRTL) -90f else 90f) * safeProgress
        if (trailingView != null) {
            trailingView.alpha = 1f - safeProgress
            arrowView?.alpha = safeProgress
        }
    }

    override fun updateTheme() {
        ripple.rippleColor = WColor.TrinaryBackground.color
        val icon = item.getIcon()
        val customDrawable = item.getIconDrawable()?.let { drawable ->
            drawable.constantState?.newDrawable(resources)?.mutate() ?: drawable
        }
        if (icon != null || customDrawable != null) {
            val drawable = (customDrawable ?: icon?.let { context.getDrawableCompat(it) })?.apply {
                item.getIconTint()?.let {
                    setTint(it)
                }
            }
            iconView?.setImageDrawable(drawable)
        }
        label.setTextColor(item.getTitleColor() ?: WColor.PrimaryText.color)
        subtitleLabel?.setTextColor(WColor.SecondaryText.color)
        if (item.hasSeparator) separatorView?.setBackgroundColor(WColor.PopupSeparator.color)
        if (!item.getSubItems().isNullOrEmpty()) {
            val drawable = context.getDrawableCompat(R.drawable.ic_menu_arrow_right)?.apply {
                setTint(WColor.PrimaryLightText.color)
            }
            arrowView?.setImageDrawable(drawable)
        }
    }
}
