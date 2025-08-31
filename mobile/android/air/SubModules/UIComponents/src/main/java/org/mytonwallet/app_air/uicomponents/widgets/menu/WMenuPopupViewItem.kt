package org.mytonwallet.app_air.uicomponents.widgets.menu

import android.annotation.SuppressLint
import android.content.Context
import android.text.TextUtils
import android.view.Gravity
import android.view.View
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import android.widget.FrameLayout
import androidx.appcompat.widget.AppCompatImageView
import androidx.core.content.ContextCompat
import org.mytonwallet.app_air.icons.R
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.uicomponents.widgets.addRippleEffect
import org.mytonwallet.app_air.walletcontext.helpers.LocaleController
import org.mytonwallet.app_air.walletcontext.theme.WColor
import org.mytonwallet.app_air.walletcontext.theme.color
import kotlin.math.roundToInt

@SuppressLint("ViewConstructor")
class WMenuPopupViewItem(context: Context, val item: WMenuPopup.Item) : FrameLayout(context),
    WThemedView {

    private val hasSubtitle = !item.getSubTitle().isNullOrEmpty()

    private val label = WLabel(context).apply {
        setStyle(16f, if (hasSubtitle) WFont.Medium else WFont.Regular)
        setSingleLine()
        ellipsize = TextUtils.TruncateAt.END
        text = item.getTitle()
    }

    private val subtitleLabel = WLabel(context).apply {
        setStyle(12f)
        text = item.getSubTitle()
        applyFontOffsetFix = true
    }

    private val iconView = if (item.getIcon() != null) AppCompatImageView(context) else null
    private val separatorView = if (item.hasSeparator) View(context) else null
    private val arrowView = if (item.getSubItems() != null) AppCompatImageView(context) else null

    private val textMargin: Int
        get() {
            return if (
                item.getIcon() != null ||
                item.getIsSubItem() ||
                item.config is WMenuPopup.Item.Config.SelectableItem
            )
                57.dp
            else
                16.dp
        }

    init {
        id = generateViewId()
        addView(label, LayoutParams(WRAP_CONTENT, WRAP_CONTENT).apply {
            if (hasSubtitle) {
                gravity = if (LocaleController.isRTL) Gravity.RIGHT else Gravity.LEFT
                topMargin = 9.dp
            } else {
                gravity =
                    Gravity.CENTER_VERTICAL or
                        (if (LocaleController.isRTL) Gravity.RIGHT else Gravity.LEFT)
                bottomMargin = if (item.hasSeparator) 3.5f.dp.roundToInt() else 0
            }
            if (LocaleController.isRTL)
                rightMargin = textMargin
            else
                leftMargin = textMargin
        })
        addView(subtitleLabel, LayoutParams(WRAP_CONTENT, WRAP_CONTENT).apply {
            gravity = Gravity.BOTTOM or
                if (LocaleController.isRTL) Gravity.RIGHT else Gravity.LEFT
            bottomMargin = if (item.hasSeparator) 18.dp else 11.dp
            if (LocaleController.isRTL)
                rightMargin = textMargin
            else
                leftMargin = textMargin
        })
        item.getIcon()?.let {
            val iconSize = item.getIconSize() ?: if (hasSubtitle) 36.dp else 24.dp
            addView(iconView, LayoutParams(iconSize, iconSize).apply {
                val startMargin = if (hasSubtitle)
                    10.dp
                else
                    (18.dp - ((item.getIconSize() ?: 24.dp) - 24.dp) / 3f).roundToInt()
                if (LocaleController.isRTL)
                    rightMargin = startMargin
                else
                    leftMargin = startMargin
                gravity = Gravity.CENTER_VERTICAL or
                    (if (LocaleController.isRTL) Gravity.RIGHT else Gravity.LEFT)
                bottomMargin = if (item.hasSeparator) 3.5f.dp.roundToInt() else 0
            })
        }
        if (item.hasSeparator) {
            addView(separatorView, LayoutParams(500.dp, 7.dp).apply {
                gravity = Gravity.BOTTOM
            })
        }
        if (!item.getSubItems().isNullOrEmpty()) {
            addView(arrowView, LayoutParams(24.dp, 24.dp).apply {
                gravity = Gravity.CENTER_VERTICAL or
                    if (LocaleController.isRTL) Gravity.LEFT else Gravity.RIGHT
                if (LocaleController.isRTL)
                    leftMargin = 8.dp
                else
                    rightMargin = 8.dp
                bottomMargin = if (item.hasSeparator) 3.5f.dp.roundToInt() else 0
            })
        }
        if (item.config is WMenuPopup.Item.Config.Item) {
            item.config.trailingView?.let {
                addView(it, LayoutParams(WRAP_CONTENT, WRAP_CONTENT).apply {
                    gravity = Gravity.CENTER_VERTICAL or
                        if (LocaleController.isRTL) Gravity.LEFT else Gravity.RIGHT
                    if (LocaleController.isRTL)
                        leftMargin = 12.dp
                    else
                        rightMargin = 12.dp
                    bottomMargin = if (item.hasSeparator) 3.5f.dp.roundToInt() else 0
                })
            }
        }
        updateTheme()
    }

    override fun onSizeChanged(w: Int, h: Int, oldw: Int, oldh: Int) {
        super.onSizeChanged(w, h, oldw, oldh)
        label.maxWidth = w - textMargin - 8.dp
        label.measure(
            MeasureSpec.makeMeasureSpec(w - textMargin - 8.dp, MeasureSpec.AT_MOST),
            MeasureSpec.makeMeasureSpec(0, MeasureSpec.UNSPECIFIED)
        )
    }

    override fun updateTheme() {
        addRippleEffect(WColor.TrinaryBackground.color, 0f)
        val icon = item.getIcon()
        if (icon != null) {
            val drawable = ContextCompat.getDrawable(context, icon)?.apply {
                item.getIconTint()?.let {
                    setTint(it)
                }
            }
            iconView!!.setImageDrawable(drawable)
        }
        label.setTextColor(item.getTitleColor() ?: WColor.PrimaryText.color)
        subtitleLabel.setTextColor(WColor.SecondaryText.color)
        if (item.hasSeparator)
            separatorView!!.setBackgroundColor(WColor.SecondaryBackground.color)
        if (!item.getSubItems().isNullOrEmpty()) {
            val drawable =
                ContextCompat.getDrawable(context, R.drawable.ic_menu_arrow_right)?.apply {
                    setTint(WColor.SecondaryText.color)
                }
            arrowView!!.setImageDrawable(drawable)
        }
    }

}
