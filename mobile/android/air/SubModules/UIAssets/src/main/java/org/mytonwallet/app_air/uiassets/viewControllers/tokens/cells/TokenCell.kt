package org.mytonwallet.app_air.uiassets.viewControllers.tokens.cells

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Color
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
import org.mytonwallet.app_air.uicomponents.widgets.WView
import org.mytonwallet.app_air.uicomponents.widgets.sensitiveDataContainer.WSensitiveDataContainer
import org.mytonwallet.app_air.uicomponents.widgets.setBackgroundColor
import org.mytonwallet.app_air.walletcontext.helpers.LocaleController
import org.mytonwallet.app_air.walletcontext.theme.ViewConstants
import org.mytonwallet.app_air.walletcontext.theme.WColor
import org.mytonwallet.app_air.walletcontext.theme.color
import org.mytonwallet.app_air.walletcontext.utils.toString
import org.mytonwallet.app_air.walletcore.STAKE_SLUG
import org.mytonwallet.app_air.walletcore.TONCOIN_SLUG
import org.mytonwallet.app_air.walletcore.TON_USDT_SLUG
import org.mytonwallet.app_air.walletcore.TRON_USDT_SLUG
import org.mytonwallet.app_air.walletcore.USDE_SLUG
import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.models.MToken
import org.mytonwallet.app_air.walletcore.models.MTokenBalance
import org.mytonwallet.app_air.walletcore.stores.AccountStore
import org.mytonwallet.app_air.walletcore.stores.TokenStore
import java.math.BigInteger
import kotlin.math.abs
import kotlin.math.roundToInt

@SuppressLint("ViewConstructor")
class TokenCell(context: Context, val mode: TokensVC.Mode) : WCell(context), WThemedView {

    private val iconView: IconView by lazy {
        val iv = IconView(context)
        iv
    }

    private val topLeftLabel: WLabel by lazy {
        val lbl = WLabel(context)
        lbl.setStyle(16f, WFont.Medium)
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
        lbl.setStyle(16f)
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

    private val separator: WView by lazy {
        val v = WView(context)
        v
    }

    var onTap: ((tokenBalance: MTokenBalance) -> Unit)? = null

    init {
        layoutParams.apply {
            height = 64.dp
        }
        addView(iconView, LayoutParams(53.dp, 48.dp))
        addView(topLeftLabel, LayoutParams(WRAP_CONTENT, WRAP_CONTENT))
        addView(topLeftTagLabel, LayoutParams(WRAP_CONTENT, 16.dp))
        addView(topRightLabel)
        addView(bottomLeftLabel)
        addView(bottomRightLabel)
        addView(separator, LayoutParams(0, 1))
        setConstraints {
            // Icon View
            toTop(iconView, 8f)
            toBottom(iconView, 8f)
            toStart(iconView, 12f)
            // Top Row
            toTop(topLeftLabel, 11f)
            startToEnd(topLeftLabel, iconView, 7f)
            startToEnd(topLeftTagLabel, topLeftLabel, 6f)
            centerYToCenterY(topLeftTagLabel, topLeftLabel)
            endToStart(topLeftTagLabel, topRightLabel, 4f)
            toTop(topRightLabel, 11f)
            toEnd(topRightLabel, 16f)
            constrainedWidth(topLeftLabel.id, true)
            setHorizontalBias(topLeftLabel.id, 0f)
            setHorizontalBias(topLeftTagLabel.id, 0f)
            // Bottom Row
            toBottom(bottomLeftLabel, 12f)
            startToEnd(bottomLeftLabel, iconView, 7f)
            endToStart(bottomLeftLabel, bottomRightLabel, 4f)
            setHorizontalBias(bottomLeftLabel.id, 0f)
            toBottom(bottomRightLabel, 12f)
            toEnd(bottomRightLabel, 16f)
            toBottom(separator)
            toStart(separator, 72f)
            toEnd(separator, 16f)
        }
        setOnClickListener {
            tokenBalance?.let {
                onTap?.invoke(it)
            }
        }

        updateTheme()
    }

    override fun updateTheme() {
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
        topRightLabel.contentView.setTextColor(WColor.PrimaryText.color)
        bottomRightLabel.contentView.setTextColor(WColor.SecondaryText.color)
        separator.setBackgroundColor(WColor.Separator.color)
        tokenBalance?.let {
            updateBottomLeftLabel(it, null)
        }
    }

    private var tokenBalance: MTokenBalance? = null
    private var isLast = false

    fun configure(tokenBalance: MTokenBalance, isLast: Boolean) {
        this.tokenBalance = tokenBalance
        this.isLast = isLast
        updateTheme()

        val amountCols = 4 + abs(tokenBalance.token.hashCode() % 8)
        topRightLabel.setMaskCols(amountCols)
        val fiatAmountCols = 5 + (amountCols % 6)
        bottomRightLabel.setMaskCols(fiatAmountCols)
        topRightLabel.updateProtectedView(false)
        bottomRightLabel.updateProtectedView(false)

        val token = TokenStore.getToken(tokenBalance.token)
        iconView.config(
            tokenBalance,
            alwaysShowChain = WalletCore.isMultichain,
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
            WalletCore.baseCurrency.sign,
            WalletCore.baseCurrency.decimalsCount,
            true
        )

        configureTagLabelAndSpacing(token)

        separator.visibility = if (isLast) INVISIBLE else VISIBLE
    }

    private fun configureTagLabelAndSpacing(token: MToken?) {
        var shouldShowTagLabel = false

        when {
            token?.slug == TRON_USDT_SLUG -> {
                topLeftTagLabel.setAmount("TRC-20")
                topLeftTagLabel.setGradientColor(
                    intArrayOf(
                        WColor.SecondaryText.color,
                        WColor.SecondaryText.color
                    )
                )
                topLeftTagLabel.setBackgroundColor(WColor.BadgeBackground.color, 8f.dp)
                shouldShowTagLabel = true
            }

            token?.slug == TON_USDT_SLUG -> {
                topLeftTagLabel.setAmount("TON")
                topLeftTagLabel.setGradientColor(
                    intArrayOf(
                        WColor.SecondaryText.color,
                        WColor.SecondaryText.color
                    )
                )
                topLeftTagLabel.setBackgroundColor(WColor.BadgeBackground.color, 8f.dp)
                shouldShowTagLabel = true
            }

            tokenBalance?.isVirtualStakingRow == true || token?.isEarnAvailable == true -> {
                val stakingState = AccountStore.stakingData?.stakingState(token?.slug ?: "")
                val apy = stakingState?.annualYield
                val hasStakingAmount = (stakingState?.balance ?: BigInteger.ZERO) > BigInteger.ZERO
                if (apy != null) {
                    shouldShowTagLabel =
                        tokenBalance?.isVirtualStakingRow == true || !hasStakingAmount
                    if (shouldShowTagLabel) {
                        if (hasStakingAmount) {
                            topLeftTagLabel.setGradientColor(
                                intArrayOf(
                                    Color.WHITE,
                                    Color.WHITE
                                )
                            )
                        } else {
                            topLeftTagLabel.setGradientColor(
                                intArrayOf(
                                    WColor.EarnGradientLeft.color,
                                    WColor.EarnGradientRight.color
                                )
                            )
                        }
                        topLeftTagLabel.setAmount("${stakingState.yieldType} ${apy}%")
                        topLeftTagLabel.background =
                            HighlightGradientBackgroundDrawable(
                                hasStakingAmount,
                                8f.dp
                            )
                    }
                }
            }
        }

        updateLabelSpacing(shouldShowTagLabel)
    }

    private var wasShowingTagLabel: Boolean? = null
    private fun updateLabelSpacing(showTagLabel: Boolean) {
        topLeftTagLabel.isGone = !showTagLabel

        if (wasShowingTagLabel == showTagLabel)
            return

        wasShowingTagLabel = showTagLabel
        if (showTagLabel) {
            topLeftLabel.layoutParams = topLeftLabel.layoutParams.apply {
                width = MATCH_CONSTRAINT
            }

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

            topLeftLabel.layoutParams = topLeftLabel.layoutParams.apply {
                width = MATCH_CONSTRAINT
            }

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

        val token = token ?: TokenStore.getToken(tokenBalance.token)

        val pricedToken = if (token?.slug == STAKE_SLUG) {
            TokenStore.getToken(TONCOIN_SLUG)
        } else {
            token
        }

        if (pricedToken?.price != null) {
            val amountText = pricedToken.price!!.toString(
                token?.decimals ?: 9,
                WalletCore.baseCurrency.sign,
                token?.decimals ?: 9,
                true
            ) ?: ""

            val percentChangeText =
                when {
                    pricedToken.percentChange24h < 0 -> {
                        " ${pricedToken.percentChange24h}%"
                    }

                    pricedToken.percentChange24h.isFinite() -> {
                        " +${pricedToken.percentChange24h}%"
                    }

                    else -> ""
                }

            val formattedText = amountText + percentChangeText

            val spannableString = SpannableString(formattedText)
            val color =
                if (pricedToken.percentChange24h < 0) WColor.Red.color else (if (pricedToken.percentChange24h > 0) WColor.Green.color else WColor.SecondaryText.color)
            val startIndex = amountText.length
            val endIndex = formattedText.length

            spannableString.setSpan(
                ForegroundColorSpan(WColor.SecondaryText.color),
                0,
                amountText.length,
                Spannable.SPAN_EXCLUSIVE_EXCLUSIVE
            )
            spannableString.setSpan(
                ForegroundColorSpan(color),
                startIndex,
                endIndex,
                Spannable.SPAN_EXCLUSIVE_EXCLUSIVE
            )
            bottomLeftLabel.text = spannableString
        } else {
            bottomLeftLabel.text = null
        }
    }

}
