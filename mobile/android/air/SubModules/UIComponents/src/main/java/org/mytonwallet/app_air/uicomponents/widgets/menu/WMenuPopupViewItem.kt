package org.mytonwallet.app_air.uicomponents.widgets.menu

import android.animation.ValueAnimator
import android.annotation.SuppressLint
import android.content.Context
import android.os.Build
import android.text.TextUtils
import android.view.Gravity
import android.view.View
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import android.view.accessibility.AccessibilityNodeInfo
import androidx.appcompat.widget.AppCompatImageView
import com.airbnb.lottie.LottieCompositionFactory
import com.airbnb.lottie.LottieDrawable
import com.airbnb.lottie.LottieProperty
import com.airbnb.lottie.SimpleColorFilter
import com.airbnb.lottie.model.KeyPath
import com.airbnb.lottie.value.LottieValueCallback
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
import org.mytonwallet.app_air.walletbasecontext.theme.colorForTheme
import org.mytonwallet.app_air.walletbasecontext.utils.getDrawableCompat
import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage

interface WMenuPopupExpandableTrailingView {
    fun setSubmenuExpansionProgress(progress: Float)
}

/** [themeIsDark] colors the item in the dark (true) or light (false) theme, or null in the app's */
@SuppressLint("ViewConstructor")
class WMenuPopupViewItem(
    context: Context,
    val item: WMenuPopup.Item,
    private val themeIsDark: Boolean? = null
) : WFrameLayout(context),
    WThemedView {

    companion object {
        // Classic plays its tab icons at double speed
        private const val ICON_ANIMATION_SPEED = 2f
    }

    private val ripple = WRippleDrawable.create(0f)

    init {
        background = ripple
        clipChildren = false
        clipToPadding = false
        if ((item.config as? WMenuPopup.Item.Config.SelectableItem)?.isSelected == true) {
            // The selection mark is only drawn, so screen readers and UI tests would not know the selected item
            accessibilityDelegate = object : View.AccessibilityDelegate() {
                override fun onInitializeAccessibilityNodeInfo(
                    host: View,
                    info: AccessibilityNodeInfo
                ) {
                    super.onInitializeAccessibilityNodeInfo(host, info)
                    info.isSelected = true
                }
            }
        }
    }

    private val hasSubtitle = !item.getSubTitle().isNullOrEmpty()
    private val isWalletStyle = item.getRowStyle() == WMenuPopup.RowStyle.WALLET

    private val label = WLabel(context).apply {
        setStyle(
            adaptiveFontSize(),
            if (hasSubtitle ||
                isWalletStyle
            ) {
                WFont.Medium
            } else {
                WFont.Regular
            }
        )
        if (isWalletStyle) setLineHeight(24f)
        setSingleLine()
        ellipsize = TextUtils.TruncateAt.END
        text = item.getTitle()
    }

    private val subtitleLabel = if (hasSubtitle) {
        WLabel(context).apply {
            setStyle(if (isWalletStyle) 13f else 12f)
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

    // Turning system animations off also turns these off, so E2E runs and reduced motion see the
    // static icon
    private val areIconAnimationsEnabled: Boolean
        get() = WGlobalStorage.getAreAnimationsActive() &&
            (Build.VERSION.SDK_INT < Build.VERSION_CODES.O || ValueAnimator.areAnimatorsEnabled())

    private val iconAnimation: LottieDrawable? = item.getIconAnimation()
        ?.takeIf { hasIcon && areIconAnimationsEnabled }
        ?.let { LottieCompositionFactory.fromRawResSync(context, it).value }
        ?.let { composition ->
            LottieDrawable().apply {
                setComposition(composition)
                speed = ICON_ANIMATION_SPEED
                progress = 1f
            }
        }
    private val separatorView = if (item.hasSeparator) View(context) else null
    private val arrowView = if (item.getSubItems() != null) AppCompatImageView(context) else null
    private val trailingView = (item.config as? WMenuPopup.Item.Config.Item)?.let { config ->
        config.trailingViewProvider?.invoke() ?: config.trailingView
    }
    private val arrowReserve = if (isWalletStyle) {
        (if (arrowView != null) 42 else 8).dp
    } else {
        if (arrowView != null) 30.dp + 8.dp else 16.dp
    }

    private val textMargin: Int
        get() {
            return if (
                isWalletStyle || hasIcon ||
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
                    topMargin = (if (isWalletStyle) 8 else 7).dp
                    if (isWalletStyle && item.hasSeparator) bottomMargin = 3.5f.dp.roundToInt()
                } else {
                    gravity =
                        Gravity.CENTER_VERTICAL or
                        (if (LocaleController.isRTL) Gravity.RIGHT else Gravity.LEFT)
                    bottomMargin = if (item.hasSeparator) 3.5f.dp.roundToInt() else 0
                }
                if (LocaleController.isRTL) {
                    rightMargin = textMargin
                    if (arrowView != null || isWalletStyle) leftMargin = arrowReserve
                } else {
                    leftMargin = textMargin
                    if (arrowView != null || isWalletStyle) rightMargin = arrowReserve
                }
            }
        )
        subtitleLabel?.let {
            addView(
                it,
                LayoutParams(WRAP_CONTENT, WRAP_CONTENT).apply {
                    gravity = if (LocaleController.isRTL) Gravity.RIGHT else Gravity.LEFT
                    if (isWalletStyle) {
                        topMargin = 31.dp
                        bottomMargin = if (item.hasSeparator) 5.5f.dp.roundToInt() else 2.dp
                    } else {
                        gravity = gravity or Gravity.BOTTOM
                        bottomMargin = if (item.hasSeparator) 13.dp else 6.dp
                    }
                    if (LocaleController.isRTL) {
                        rightMargin = textMargin
                        if (isWalletStyle) leftMargin = arrowReserve
                    } else {
                        leftMargin = textMargin
                        if (isWalletStyle) rightMargin = arrowReserve
                    }
                }
            )
        }
        if (hasIcon) {
            if (LocaleController.isRTL && item.config is WMenuPopup.Item.Config.Back) {
                iconView?.scaleX = -1f
            }
            val artworkSize = item.getIconSize() ?: if (hasSubtitle) 36.dp else 30.dp
            val iconSize = if (isWalletStyle) 39.dp else artworkSize
            if (isWalletStyle) {
                val extraSize = (iconSize - artworkSize).coerceAtLeast(0)
                val leadingInset = extraSize / 2
                val trailingInset = extraSize - leadingInset
                iconView?.setPadding(leadingInset, leadingInset, trailingInset, trailingInset)
            }
            addView(
                iconView,
                LayoutParams(iconSize, iconSize).apply {
                    val startMargin = if (isWalletStyle) {
                        10.5f.dp.roundToInt()
                    } else {
                        item.getIconMargin() ?: if (hasSubtitle) {
                            10.dp
                        } else {
                            (16.dp - ((item.getIconSize() ?: 30.dp) - 30.dp) / 3f).roundToInt()
                        }
                    }
                    if (LocaleController.isRTL) {
                        rightMargin = startMargin
                    } else {
                        leftMargin = startMargin
                    }
                    gravity = Gravity.CENTER_VERTICAL or
                        (if (LocaleController.isRTL) Gravity.RIGHT else Gravity.LEFT)
                    bottomMargin = if (item.hasSeparator) {
                        (if (isWalletStyle) 1.5f else 3.5f).dp.roundToInt()
                    } else {
                        0
                    }
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

    override fun setPressed(pressed: Boolean) {
        val becomesPressed = pressed && !isPressed
        super.setPressed(pressed)
        if (becomesPressed && areIconAnimationsEnabled) iconAnimation?.playAnimation()
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
        ripple.rippleColor = if (isWalletStyle) {
            WColor.BackgroundRipple.colorForTheme(themeIsDark)
        } else {
            WColor.TrinaryBackground.colorForTheme(themeIsDark)
        }
        val icon = item.getIcon()
        val customDrawable = item.getIconDrawable()?.let { drawable ->
            drawable.constantState?.newDrawable(resources)?.mutate() ?: drawable
        }
        if (iconAnimation != null) {
            item.getIconTint(themeIsDark)?.let { tint ->
                iconAnimation.addValueCallback(
                    KeyPath("**"),
                    LottieProperty.COLOR_FILTER,
                    LottieValueCallback(SimpleColorFilter(tint))
                )
            }
            iconView?.setImageDrawable(iconAnimation)
        } else if (icon != null || customDrawable != null) {
            val drawable = (customDrawable ?: icon?.let { context.getDrawableCompat(it) })?.apply {
                item.getIconTint(themeIsDark)?.let {
                    setTint(it)
                }
            }
            iconView?.setImageDrawable(drawable)
        }
        label.setTextColor(item.getTitleColor() ?: WColor.PrimaryText.colorForTheme(themeIsDark))
        subtitleLabel?.setTextColor(WColor.SecondaryText.colorForTheme(themeIsDark))
        if (item.hasSeparator) {
            separatorView?.setBackgroundColor(WColor.PopupSeparator.colorForTheme(themeIsDark))
        }
        if (!item.getSubItems().isNullOrEmpty()) {
            val drawable = context.getDrawableCompat(R.drawable.ic_menu_arrow_right)?.apply {
                setTint(WColor.PrimaryLightText.colorForTheme(themeIsDark))
            }
            arrowView?.setImageDrawable(drawable)
        }
    }
}
