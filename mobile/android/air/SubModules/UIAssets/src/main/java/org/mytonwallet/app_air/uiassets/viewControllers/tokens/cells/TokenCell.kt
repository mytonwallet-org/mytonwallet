package org.mytonwallet.app_air.uiassets.viewControllers.tokens.cells

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Color
import android.graphics.drawable.GradientDrawable
import android.text.Spannable
import android.text.SpannableString
import android.text.TextUtils
import android.text.style.ForegroundColorSpan
import android.view.Gravity
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import androidx.constraintlayout.widget.ConstraintLayout.LayoutParams.MATCH_CONSTRAINT
import androidx.constraintlayout.widget.ConstraintSet
import androidx.core.view.isGone
import org.mytonwallet.app_air.uiassets.viewControllers.tokens.TokensVC
import org.mytonwallet.app_air.uicomponents.commonViews.IconView
import org.mytonwallet.app_air.uicomponents.drawable.HighlightGradientBackgroundDrawable
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.widgets.WCell
import org.mytonwallet.app_air.uicomponents.widgets.WCounterLabel
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.uicomponents.widgets.sensitiveDataContainer.WSensitiveDataContainer
import org.mytonwallet.app_air.uicomponents.widgets.setBackgroundColor
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.models.MBaseCurrency
import org.mytonwallet.app_air.walletbasecontext.theme.ThemeManager
import org.mytonwallet.app_air.walletbasecontext.theme.ViewConstants
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletbasecontext.utils.ApplicationContextHolder
import org.mytonwallet.app_air.walletbasecontext.utils.signSpace
import org.mytonwallet.app_air.walletbasecontext.utils.toString
import org.mytonwallet.app_air.walletcore.STAKE_SLUG
import org.mytonwallet.app_air.walletcore.TONCOIN_SLUG
import org.mytonwallet.app_air.walletcore.TON_USDT_SLUG
import org.mytonwallet.app_air.walletcore.TON_USDT_TESTNET_SLUG
import org.mytonwallet.app_air.walletcore.TRON_USDT_SLUG
import org.mytonwallet.app_air.walletcore.TRON_USDT_TESTNET_SLUG
import org.mytonwallet.app_air.walletcore.USDE_SLUG
import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.models.MToken
import org.mytonwallet.app_air.walletcore.models.MTokenBalance
import org.mytonwallet.app_air.walletcore.stores.StakingStore
import org.mytonwallet.app_air.walletcore.stores.TokenStore
import java.math.BigInteger
import kotlin.math.abs
import kotlin.math.roundToInt

@SuppressLint("ViewConstructor")
class TokenCell(context: Context, val mode: TokensVC.Mode) : WCell(context), WThemedView {

    private val iconView: IconView by lazy {
        val iv = IconView(context, ApplicationContextHolder.adaptiveIconSize.dp)
        iv
    }

    private val topLeftLabel: WLabel by lazy {
        val lbl = WLabel(context)
        lbl.setStyle(ApplicationContextHolder.adaptiveFontSize, WFont.DemiBold)
        lbl.setSingleLine()
        lbl.ellipsize = TextUtils.TruncateAt.END
        lbl.isHorizontalFadingEdgeEnabled = true
        lbl
    }

    private val topLeftTagLabel: WCounterLabel by lazy {
        val lbl = WCounterLabel(context)
        lbl.id = generateViewId()
        lbl.textAlignment = TEXT_ALIGNMENT_CENTER
        lbl.setPadding(4.5f.dp.roundToInt(), 4.dp, 4.5f.dp.roundToInt(), 0)
        lbl.setStyle(11f, WFont.SemiBold)
        lbl
    }

    private val bottomLeftLabel: WLabel by lazy {
        WLabel(context).apply {
            setStyle(13f)
            setSingleLine()
            ellipsize = TextUtils.TruncateAt.MARQUEE
            isHorizontalFadingEdgeEnabled = true
            isSelected = true
        }
    }

    private val topRightLabel: WSensitiveDataContainer<WLabel> by lazy {
        val lbl = WLabel(context)
        lbl.setStyle(ApplicationContextHolder.adaptiveFontSize)
        WSensitiveDataContainer(
            lbl,
            WSensitiveDataContainer.MaskConfig(0, 2, Gravity.END or Gravity.CENTER_VERTICAL)
        )
    }

    private val bottomRightLabel: WSensitiveDataContainer<WLabel> by lazy {
        val lbl = WLabel(context)
        lbl.setStyle(13f)
        lbl.layoutDirection = LAYOUT_DIRECTION_LTR
        WSensitiveDataContainer(
            lbl,
            WSensitiveDataContainer.MaskConfig(0, 2, Gravity.END or Gravity.CENTER_VERTICAL)
        )
    }

    var onTap: ((tokenBalance: MTokenBalance) -> Unit)? = null

    init {
        layoutParams.apply {
            height = 60.dp
        }
        addView(iconView, LayoutParams((ApplicationContextHolder.adaptiveIconSize + 2).dp, (ApplicationContextHolder.adaptiveIconSize + 2).dp))
        addView(topLeftLabel, LayoutParams(WRAP_CONTENT, WRAP_CONTENT))
        addView(topLeftTagLabel, LayoutParams(WRAP_CONTENT, 16.dp))
        addView(topRightLabel)
        addView(bottomLeftLabel)
        addView(bottomRightLabel)
        setConstraints {
            // Icon View
            toTop(iconView, ApplicationContextHolder.adaptiveIconTopMargin)
            toStart(iconView, 12f)
            // Top Row
            toTop(topLeftLabel, 9f)
            toStart(topLeftLabel, ApplicationContextHolder.adaptiveContentStart)
            startToEnd(topLeftTagLabel, topLeftLabel, 3f)
            centerYToCenterY(topLeftTagLabel, topLeftLabel)
            endToStart(topLeftTagLabel, topRightLabel, 4f)
            toTop(topRightLabel, 9f)
            toEnd(topRightLabel, 16f)
            constrainedWidth(topLeftLabel.id, true)
            setHorizontalBias(topLeftLabel.id, 0f)
            setHorizontalBias(topLeftTagLabel.id, 0f)
            // Bottom Row
            toBottom(bottomLeftLabel, 10f)
            toStart(bottomLeftLabel, ApplicationContextHolder.adaptiveContentStart)
            endToStart(bottomLeftLabel, bottomRightLabel, 4f)
            setHorizontalBias(bottomLeftLabel.id, 0f)
            toBottom(bottomRightLabel, 10f)
            toEnd(bottomRightLabel, 16f)
        }
        setOnClickListener {
            tokenBalance?.let {
                onTap?.invoke(it)
            }
        }
    }

    private var _isDarkThemeApplied: Boolean? = null
    override fun updateTheme() {
        updateTheme(forceUpdate = false)
    }

    private fun updateTheme(forceUpdate: Boolean) {
        val darkModeChanged = ThemeManager.isDark != _isDarkThemeApplied
        if (!forceUpdate && !darkModeChanged)
            return
        _isDarkThemeApplied = ThemeManager.isDark
        cachedStakingTagDrawable = null
        cachedNotStakingTagDrawable = null
        setBackgroundColor(
            if (mode == TokensVC.Mode.HOME) Color.TRANSPARENT else WColor.Background.color,
            0f,
            if (isLast) ViewConstants.BIG_RADIUS.dp else 0f
        )
        addRippleEffect(
            WColor.SecondaryBackground.color,
            0f,
            if (isLast) ViewConstants.BIG_RADIUS.dp else 0f
        )
        topLeftLabel.setTextColor(WColor.PrimaryText.color)
        topLeftTagLabel.updateTheme()
        if (isShowingStaticTag)
            topLeftTagLabel.setBackgroundColor(WColor.BadgeBackground.color, 8f.dp)
        topRightLabel.contentView.setTextColor(WColor.PrimaryText.color)
        bottomRightLabel.contentView.setTextColor(WColor.SecondaryText.color)
        tokenBalance?.let {
            updateBottomLeftLabel(it, null)
        }
    }

    private var accountId: String? = null
    private var tokenBalance: MTokenBalance? = null
    private var baseCurrency: MBaseCurrency? = null
    private var isLast = false
    private var isShowingStaticTag = false

    fun configure(
        accountId: String,
        isMultichain: Boolean,
        tokenBalance: MTokenBalance,
        isLast: Boolean
    ) {
        val lastChanged = this.isLast != isLast
        val baseCurrency = WalletCore.baseCurrency
        this.isLast = isLast

        if (this.accountId == accountId &&
            this.tokenBalance == tokenBalance &&
            this.baseCurrency == baseCurrency) {
            updateTheme(forceUpdate = lastChanged)
            return
        }

        this.accountId = accountId
        this.tokenBalance = tokenBalance
        this.baseCurrency = baseCurrency
        updateTheme(forceUpdate = lastChanged)

        val amountCols = 4 + abs(tokenBalance.token.hashCode() % 8)
        topRightLabel.setMaskCols(amountCols)
        val fiatAmountCols = 5 + (amountCols % 6)
        bottomRightLabel.setMaskCols(fiatAmountCols)
        topRightLabel.updateProtectedView(false)
        bottomRightLabel.updateProtectedView(false)

        val token = TokenStore.getToken(tokenBalance.token)
        iconView.config(
            tokenBalance,
            showChain = isMultichain,
            showPercentBadge = (tokenBalance.isVirtualStakingRow && tokenBalance.amountValue > BigInteger.ZERO)
        )
        val tokenName = if (tokenBalance.isVirtualStakingRow) {
            LocaleController.getStringWithKeyValues(
                "%token% Staking", listOf(
                    Pair(
                        "%token%", when (tokenBalance.token) {
                            USDE_SLUG -> "Ethena"
                            else -> token?.name ?: ""
                        }
                    )
                )
            )
        } else token?.name
        if (topLeftLabel.text != tokenName)
            topLeftLabel.text = tokenName
        topRightLabel.contentView.setAmount(
            tokenBalance.amountValue,
            token?.decimals ?: 9,
            token?.symbol ?: "",
            token?.decimals ?: 9,
            smartDecimals = true,
            forceCurrencyToRight = true
        )
        updateBottomLeftLabel(tokenBalance, token)
        bottomRightLabel.contentView.setAmount(
            tokenBalance.toBaseCurrency,
            token?.decimals ?: 9,
            baseCurrency.sign,
            baseCurrency.decimalsCount,
            true
        )

        configureTagLabelAndSpacing(accountId, token)
    }

    private fun configureTagLabelAndSpacing(accountId: String, token: MToken?) {
        val shouldShowTagLabel = when (token?.slug) {
            TRON_USDT_SLUG, TRON_USDT_TESTNET_SLUG -> {
                configureStaticTag("TRC-20")
                true
            }

            TON_USDT_SLUG, TON_USDT_TESTNET_SLUG -> {
                configureStaticTag("TON")
                true
            }

            else -> configureStakingTag(accountId, token)
        }

        updateLabelSpacing(shouldShowTagLabel)
    }

    private fun configureStaticTag(text: String) {
        isShowingStaticTag = true
        topLeftTagLabel.setAmount(text)
        topLeftTagLabel.setGradientColor(
            arrayOf(WColor.SecondaryText, WColor.SecondaryText)
        )
        topLeftTagLabel.setBackgroundColor(WColor.BadgeBackground.color, 8f.dp)
    }

    private var cachedStakingTagDrawable: GradientDrawable? = null
    private var cachedNotStakingTagDrawable: GradientDrawable? = null
    fun getTagDrawable(hasStaking: Boolean, cornerRadius: Float = 8f): GradientDrawable {
        return if (hasStaking) {
            cachedStakingTagDrawable ?: createAndCacheTagDrawable(true, cornerRadius)
        } else {
            cachedNotStakingTagDrawable ?: createAndCacheTagDrawable(false, cornerRadius)
        }
    }

    private fun createAndCacheTagDrawable(hasStaking: Boolean, radius: Float): GradientDrawable {
        val drawable = HighlightGradientBackgroundDrawable(hasStaking, radius)
        if (hasStaking) {
            cachedStakingTagDrawable = drawable
        } else {
            cachedNotStakingTagDrawable = drawable
        }
        return drawable
    }

    private fun configureStakingTag(accountId: String, token: MToken?): Boolean {
        isShowingStaticTag = false
        if (tokenBalance?.isVirtualStakingRow != true && token?.isEarnAvailable != true) {
            return false
        }

        val stakingState = StakingStore.getStakingState(accountId)?.stakingState(token?.slug ?: "")
        val apy = stakingState?.annualYield ?: return false

        val hasStakingAmount = stakingState.balance > BigInteger.ZERO
        val shouldShow = tokenBalance?.isVirtualStakingRow == true || !hasStakingAmount

        if (shouldShow) {
            val gradientColors = if (hasStakingAmount) {
                arrayOf(WColor.White, WColor.White)
            } else {
                arrayOf(WColor.EarnGradientLeft, WColor.EarnGradientRight)
            }

            topLeftTagLabel.setGradientColor(gradientColors)
            topLeftTagLabel.setAmount(if (hasStakingAmount) "$apy%" else "${stakingState.yieldType} $apy%")
            topLeftTagLabel.background =
                getTagDrawable(hasStakingAmount, 8f.dp)
        }

        return shouldShow
    }

    private var wasShowingTagLabel: Boolean? = null
    private fun updateLabelSpacing(showTagLabel: Boolean) {
        topLeftTagLabel.isGone = !showTagLabel

        if (wasShowingTagLabel == showTagLabel)
            return

        wasShowingTagLabel = showTagLabel

        topLeftLabel.layoutParams = topLeftLabel.layoutParams.apply {
            width = MATCH_CONSTRAINT
        }

        if (showTagLabel) {
            setConstraints {
                clear(topLeftLabel.id, ConstraintSet.END)

                endToStart(topLeftLabel, topLeftTagLabel)

                endToStart(topLeftTagLabel, topRightLabel, 4f)
                constrainedWidth(topLeftLabel.id, true)
                setHorizontalBias(topLeftLabel.id, 0f)

                setHorizontalChainStyle(topLeftLabel.id, ConstraintSet.CHAIN_PACKED)
            }
        } else {
            topLeftTagLabel.visibility = GONE

            setConstraints {
                clear(topLeftLabel.id, ConstraintSet.END)

                endToStart(topLeftLabel, topRightLabel, 4f)
                constrainedWidth(topLeftLabel.id, true)
                setHorizontalBias(topLeftLabel.id, 0f)
            }
        }
    }

    private fun updateBottomLeftLabel(tokenBalance: MTokenBalance, token: MToken?) {
        this.tokenBalance = tokenBalance

        val resolvedToken = token ?: TokenStore.getToken(tokenBalance.token)
        val pricedToken = if (resolvedToken?.slug == STAKE_SLUG) {
            TokenStore.getToken(TONCOIN_SLUG)
        } else {
            resolvedToken
        }

        val price = pricedToken?.price
        if (price == null) {
            bottomLeftLabel.text = null
            return
        }

        val decimals = resolvedToken?.decimals ?: 9
        val amountText =
            price.toString(decimals, WalletCore.baseCurrency.sign, decimals, true) ?: ""

        val percentChange = pricedToken.percentChange24h
        val percentChangeText = when {
            percentChange < 0 -> " -$signSpace${abs(percentChange)}%"
            percentChange > 0 && percentChange.isFinite() -> " +$signSpace$percentChange%"
            else -> ""
        }

        if (percentChangeText.isEmpty()) {
            bottomLeftLabel.text = amountText
            return
        }

        val formattedText = amountText + percentChangeText
        val spannableString = SpannableString(formattedText)
        val amountLength = amountText.length

        spannableString.setSpan(
            ForegroundColorSpan(WColor.SecondaryText.color),
            0,
            amountLength,
            Spannable.SPAN_EXCLUSIVE_EXCLUSIVE
        )

        val color = if (percentChange < 0) WColor.Red.color else WColor.Green.color

        spannableString.setSpan(
            ForegroundColorSpan(color),
            amountLength,
            formattedText.length,
            Spannable.SPAN_EXCLUSIVE_EXCLUSIVE
        )

        bottomLeftLabel.text = spannableString
    }

}
