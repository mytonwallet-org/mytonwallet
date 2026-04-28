package org.mytonwallet.app_air.uistake.earn.cells

import android.annotation.SuppressLint
import org.mytonwallet.app_air.uicomponents.helpers.adaptiveFontSize
import android.content.Context
import android.text.TextUtils
import android.view.Gravity
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import androidx.dynamicanimation.animation.FloatValueHolder
import androidx.dynamicanimation.animation.SpringAnimation
import androidx.dynamicanimation.animation.SpringForce
import org.mytonwallet.app_air.uicomponents.commonViews.IconView
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.walletbasecontext.utils.ApplicationContextHolder
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.widgets.WCell
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.uicomponents.widgets.sensitiveDataContainer.SensitiveDataMaskView
import org.mytonwallet.app_air.uicomponents.widgets.sensitiveDataContainer.WSensitiveDataContainer
import org.mytonwallet.app_air.uicomponents.widgets.setBackgroundColor
import org.mytonwallet.app_air.uistake.earn.models.EarnItem
import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage
import org.mytonwallet.app_air.walletbasecontext.theme.ViewConstants
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletbasecontext.utils.DateUtils
import org.mytonwallet.app_air.walletbasecontext.utils.signSpace
import kotlin.math.abs
import androidx.core.view.isVisible
import org.mytonwallet.app_air.uicomponents.AnimationConstants
import org.mytonwallet.app_air.uicomponents.widgets.fadeIn
import org.mytonwallet.app_air.uicomponents.widgets.fadeOut
import org.mytonwallet.app_air.walletbasecontext.theme.ThemeManager
import kotlin.math.roundToInt

class EarnItemCell(context: Context) : WCell(context, LayoutParams(LayoutParams.MATCH_PARENT, 0)),
    WThemedView {

    private var item: EarnItem? = null
    private var isLast = false
    var onTap: ((item: EarnItem?) -> Unit)? = null

    private var pendingInsertRunnable: Runnable? = null

    companion object {
        const val ITEM_HEIGHT = 60f
    }

    private val iconView: IconView by lazy {
        val iv = IconView(context, ApplicationContextHolder.adaptiveIconSize.dp)
        iv
    }

    private val groupIcon: IconView by lazy {
        val iv = IconView(context, ApplicationContextHolder.adaptiveIconSize.dp)
        iv.visibility = GONE
        iv
    }

    private val groupIconShadow1: IconView by lazy {
        val iv = IconView(context, viewSize = (ApplicationContextHolder.adaptiveIconSize - 4).dp)
        iv.alpha = 0.6f
        iv.visibility = GONE
        iv
    }

    private val groupIconShadow2: IconView by lazy {
        val iv = IconView(context, viewSize = (ApplicationContextHolder.adaptiveIconSize - 8).dp)
        iv.alpha = 0.3f
        iv.visibility = GONE
        iv
    }

    private val titleLabel: WLabel by lazy {
        WLabel(context).apply {
            setStyle(adaptiveFontSize(), WFont.DemiBold)
            setSingleLine()
            ellipsize = TextUtils.TruncateAt.MARQUEE
            isHorizontalFadingEdgeEnabled = true
            isSelected = true
        }
    }

    private val itemDateLabel: WLabel by lazy {
        WLabel(context).apply {
            setStyle(13f, WFont.Regular)
            setSingleLine()
            ellipsize = TextUtils.TruncateAt.MARQUEE
            isHorizontalFadingEdgeEnabled = true
            isSelected = true
        }
    }

    private val amountLabel: WSensitiveDataContainer<WLabel> by lazy {
        val label = WLabel(context)
        label.setStyle(adaptiveFontSize(), WFont.Regular)
        WSensitiveDataContainer(
            label,
            WSensitiveDataContainer.MaskConfig(0, 2, Gravity.RIGHT or Gravity.CENTER_VERTICAL)
        )
    }

    private val fiatValueLabel: WSensitiveDataContainer<WLabel> by lazy {
        val label = WLabel(context)
        label.setStyle(13f, WFont.Regular)
        WSensitiveDataContainer(
            label,
            WSensitiveDataContainer.MaskConfig(0, 2, Gravity.RIGHT or Gravity.CENTER_VERTICAL)
        )
    }

    private var heightSpringAnimation: SpringAnimation? = null

    private fun cancelContentAnimations() {
        titleLabel.animate().cancel()
        itemDateLabel.animate().cancel()
        amountLabel.animate().cancel()
        fiatValueLabel.animate().cancel()
        iconView.animate().cancel()
        groupIcon.animate().cancel()
        groupIconShadow1.animate().cancel()
        groupIconShadow2.animate().cancel()
    }

    private fun setContentAlpha(alpha: Float) {
        iconView.alpha = alpha
        groupIcon.alpha = alpha
        groupIconShadow1.alpha = alpha * 0.6f
        groupIconShadow2.alpha = alpha * 0.3f
        titleLabel.alpha = alpha
        itemDateLabel.alpha = alpha
        amountLabel.alpha = alpha
        fiatValueLabel.alpha = alpha
    }

    private fun startInsertAnimation() {
        val targetHeight = ITEM_HEIGHT.dp
        heightSpringAnimation = SpringAnimation(FloatValueHolder()).apply {
            setStartValue(0f)
            spring = SpringForce(targetHeight).apply {
                stiffness = 500f
                dampingRatio = SpringForce.DAMPING_RATIO_NO_BOUNCY
            }
            addUpdateListener { _, value, _ ->
                layoutParams.height = value.toInt()
                requestLayout()
                val fraction =
                    ((value - 0.8f * targetHeight) / (0.2f * targetHeight)).coerceIn(0f, 1f)
                setContentAlpha(fraction)
            }
            addEndListener { _, _, _, _ ->
                layoutParams.height = ITEM_HEIGHT.dp.roundToInt()
                setContentAlpha(1f)
                heightSpringAnimation = null
            }
            start()
        }
    }

    // Setup items is postponed to allow the view appear with 0 height (during unmerge animations) instantly with no overheads
    fun firstAppearanceSetup() {
        val iconSize = (ApplicationContextHolder.adaptiveIconSize + 2).dp
        val shadow1Size = (ApplicationContextHolder.adaptiveIconSize - 4).dp
        val shadow2Size = (ApplicationContextHolder.adaptiveIconSize - 8).dp
        addView(iconView, LayoutParams(iconSize, iconSize))
        addView(groupIconShadow2, LayoutParams(shadow2Size, shadow2Size))
        addView(groupIconShadow1, LayoutParams(shadow1Size, shadow1Size))
        addView(groupIcon, LayoutParams(iconSize, iconSize))
        addView(titleLabel)
        addView(itemDateLabel)
        addView(amountLabel)
        addView(fiatValueLabel)

        addRippleEffect(WColor.SecondaryBackground.color)

        setConstraints {
            toTop(iconView, ApplicationContextHolder.adaptiveIconTopMargin)
            toStart(iconView, 12f)

            edgeToEdge(groupIcon, iconView)
            centerXToCenterX(groupIconShadow1, groupIcon)
            topToTop(groupIconShadow1, groupIcon, 7f)
            centerXToCenterX(groupIconShadow2, groupIcon)
            topToTop(groupIconShadow2, groupIconShadow1, 7f)

            setHorizontalBias(titleLabel.id, 0f)
            constrainedWidth(titleLabel.id, true)
            toStart(titleLabel, ApplicationContextHolder.adaptiveContentStart)
            toTop(titleLabel, 9f)
            endToStart(titleLabel, amountLabel, 4f)

            startToStart(itemDateLabel, titleLabel)
            endToStart(itemDateLabel, fiatValueLabel, 4f)
            constrainedWidth(itemDateLabel.id, true)
            setHorizontalBias(itemDateLabel.id, 0f)
            toBottom(itemDateLabel, 10f)

            toTop(amountLabel, 9f)
            toEnd(amountLabel, 16f)

            endToEnd(fiatValueLabel, amountLabel)
            toBottom(fiatValueLabel, 10f)
        }

        setOnClickListener {
            onTap?.invoke(item)
        }
    }

    private var _isDarkThemeApplied: Boolean? = null
    private var isLastChanged = true
    override fun updateTheme() {
        val darkModeChanged = ThemeManager.isDark != _isDarkThemeApplied
        if (!darkModeChanged && !isLastChanged)
            return
        _isDarkThemeApplied = ThemeManager.isDark

        setBackgroundColor(
            WColor.Background.color,
            0f,
            if (isLast) ViewConstants.BLOCK_RADIUS.dp else 0f.dp
        )
        if (item is EarnItem.ProfitGroup)
            addRippleEffect(
                WColor.SecondaryBackground.color,
                0f,
                if (isLast) ViewConstants.BLOCK_RADIUS.dp else 0f
            )

        titleLabel.setTextColor(WColor.PrimaryText.color)
        itemDateLabel.setTextColor(WColor.SecondaryText.color)

        amountLabel.contentView.setTextColor(WColor.PrimaryText.color)
        fiatValueLabel.contentView.setTextColor(WColor.SecondaryText.color)
    }

    @SuppressLint("SetTextI18n")
    private fun configureReplacedAfterUnmerge(item: EarnItem, tokenSymbol: String) {
        val duration = AnimationConstants.VERY_QUICK_ANIMATION
        if (groupIconShadow1.isVisible) {
            groupIcon.fadeOut(duration)
            groupIconShadow1.fadeOut(duration) {
                groupIconShadow1.alpha = 0.6f
                if (this.item !== item) return@fadeOut
                groupIconShadow1.visibility = GONE
            }
            groupIconShadow2.fadeOut(duration) {
                groupIconShadow2.alpha = 0.3f
                if (this.item !== item) return@fadeOut
                groupIconShadow2.visibility = GONE
            }
        }

        titleLabel.fadeOut(duration)
        itemDateLabel.fadeOut(duration)
        amountLabel.fadeOut(duration)
        fiatValueLabel.fadeOut(duration) {
            if (this.item !== item) return@fadeOut
            titleLabel.setTextIfChanged(item.getTitle())
            if (item is EarnItem.Profit || item is EarnItem.ProfitGroup || item is EarnItem.Unstaked) {
                amountLabel.contentView.text = "+$signSpace${item.formattedAmount} $tokenSymbol"
                amountLabel.contentView.setTextColor(WColor.Green.color)
                amountLabel.maskView.skin = SensitiveDataMaskView.Skin.GREEN
            } else {
                amountLabel.contentView.text = "${item.formattedAmount} $tokenSymbol"
                amountLabel.contentView.setTextColor(WColor.PrimaryText.color)
                amountLabel.maskView.skin = null
            }
            fiatValueLabel.contentView.text = item.amountInBaseCurrency
            itemDateLabel.text = DateUtils.formatDateAndTimeDotSeparated(item.timestamp)
            groupIconShadow1.visibility = GONE
            groupIconShadow2.visibility = GONE
            iconView.alpha = 0f
            iconView.visibility = VISIBLE

            val amountCols = 4 + abs(item.timestamp.hashCode() % 8)
            amountLabel.setMaskCols(amountCols)
            fiatValueLabel.setMaskCols(5 + (amountCols % 6))
            amountLabel.isSensitiveData = true
            fiatValueLabel.isSensitiveData = true

            groupIcon.fadeIn()
            titleLabel.fadeIn(duration)
            itemDateLabel.fadeIn(duration)
            amountLabel.fadeIn(duration)
            fiatValueLabel.fadeIn(duration)
            iconView.fadeIn(duration)
        }
    }

    @SuppressLint("SetTextI18n")
    fun configure(
        item: EarnItem,
        tokenSymbol: String,
        isLast: Boolean,
        isAdded: Boolean = false,
        isReplaced: Boolean = false,
        animationDelay: Long = 0L,
    ) {
        if (this.item == null)
            firstAppearanceSetup()

        isLastChanged = this.isLast != isLast
        this.isLast = isLast
        val itemChanged = this.item?.isSame(item) != true || this.item?.isChanged(item) == true
        this.item = item

        val replaceAnimation = isReplaced && WGlobalStorage.getAreAnimationsActive()
        if (!replaceAnimation)
            updateTheme()

        if (!itemChanged && !isLastChanged)
            return

        animate().cancel()
        cancelContentAnimations()
        heightSpringAnimation?.cancel()
        heightSpringAnimation = null
        pendingInsertRunnable?.let { removeCallbacks(it) }
        pendingInsertRunnable = null

        if (replaceAnimation) {
            configureReplacedAfterUnmerge(item, tokenSymbol)
            return
        }

        titleLabel.setTextIfChanged(item.getTitle())
        if (item is EarnItem.Profit || item is EarnItem.ProfitGroup || item is EarnItem.Unstaked) {
            amountLabel.contentView.text = "+$signSpace${item.formattedAmount} $tokenSymbol"
            amountLabel.contentView.setTextColor(WColor.Green.color)
            amountLabel.maskView.skin = SensitiveDataMaskView.Skin.GREEN
        } else {
            amountLabel.contentView.text = "${item.formattedAmount} $tokenSymbol"
            amountLabel.contentView.setTextColor(WColor.PrimaryText.color)
            amountLabel.maskView.skin = null
        }
        fiatValueLabel.contentView.text = item.amountInBaseCurrency
        arrayListOf(iconView, groupIcon, groupIconShadow1, groupIconShadow2).forEach {
            it.config(
                item.getIcon(),
                item.getGradientColors()?.first,
                item.getGradientColors()?.second,
            )
        }
        if (item is EarnItem.ProfitGroup) {
            groupIcon.visibility = VISIBLE
            groupIconShadow1.visibility = VISIBLE
            groupIconShadow2.visibility = VISIBLE
            iconView.visibility = INVISIBLE

            val firstDate = DateUtils.formatDayMonth(item.profitItems.first().timestamp)
            val lastDate = DateUtils.formatDayMonth(item.profitItems.last().timestamp)
            itemDateLabel.text = "$firstDate…$lastDate"
        } else {
            groupIcon.visibility = GONE
            groupIconShadow1.visibility = GONE
            groupIconShadow2.visibility = GONE
            iconView.visibility = VISIBLE

            itemDateLabel.text = DateUtils.formatDateAndTimeDotSeparated(item.timestamp)
        }

        val amountCols = 4 + abs(item.timestamp.hashCode() % 8)
        amountLabel.setMaskCols(amountCols)
        val fiatAmountCols = 5 + (amountCols % 6)
        fiatValueLabel.setMaskCols(fiatAmountCols)
        amountLabel.isSensitiveData = true
        fiatValueLabel.isSensitiveData = true

        if (isAdded && WGlobalStorage.getAreAnimationsActive()) {
            alpha = 1f
            layoutParams.height = 0
            setContentAlpha(0f)
            requestLayout()
            pendingInsertRunnable = Runnable { startInsertAnimation() }
            postDelayed(pendingInsertRunnable, animationDelay)
        } else {
            alpha = 1f
            layoutParams.height = ITEM_HEIGHT.dp.roundToInt()
            setContentAlpha(1f)
        }
    }

}
