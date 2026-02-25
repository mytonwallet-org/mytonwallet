package org.mytonwallet.app_air.uicomponents.helpers

import android.content.Context
import android.graphics.drawable.GradientDrawable
import android.view.View
import androidx.constraintlayout.widget.ConstraintLayout.LayoutParams.MATCH_CONSTRAINT
import androidx.constraintlayout.widget.ConstraintSet
import androidx.core.view.isGone
import org.mytonwallet.app_air.uicomponents.drawable.HighlightGradientBackgroundDrawable
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.widgets.WCounterLabel
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.uicomponents.widgets.WView
import org.mytonwallet.app_air.uicomponents.widgets.setBackgroundColor
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletcore.SOLANA_USDC_SLUG
import org.mytonwallet.app_air.walletcore.SOLANA_USDT_SLUG
import org.mytonwallet.app_air.walletcore.TON_USDT_SLUG
import org.mytonwallet.app_air.walletcore.TON_USDT_TESTNET_SLUG
import org.mytonwallet.app_air.walletcore.TRON_USDT_SLUG
import org.mytonwallet.app_air.walletcore.TRON_USDT_TESTNET_SLUG
import org.mytonwallet.app_air.walletcore.models.MToken
import org.mytonwallet.app_air.walletcore.models.MTokenBalance
import org.mytonwallet.app_air.walletcore.stores.StakingStore
import java.math.BigInteger
import kotlin.math.roundToInt

class TokenTagHelper(context: Context) {

    val tagLabel: WCounterLabel = WCounterLabel(context).apply {
        id = View.generateViewId()
        textAlignment = View.TEXT_ALIGNMENT_CENTER
        setPadding(4.5f.dp.roundToInt(), 4.dp, 4.5f.dp.roundToInt(), 0)
        setStyle(11f, WFont.SemiBold)
    }

    private var isShowingStaticTag = false
    private var wasShowingTagLabel: Boolean? = null
    private var cachedStakingTagDrawable: GradientDrawable? = null
    private var cachedNotStakingTagDrawable: GradientDrawable? = null

    fun configure(
        cell: WView,
        topLeftLabel: WLabel,
        topRightView: View,
        accountId: String?,
        token: MToken?,
        tokenBalance: MTokenBalance?
    ) {
        val shouldShow = when (token?.slug) {
            TRON_USDT_SLUG, TRON_USDT_TESTNET_SLUG -> { configureStaticTag("TRC-20"); true }
            TON_USDT_SLUG, TON_USDT_TESTNET_SLUG -> { configureStaticTag("TON"); true }
            SOLANA_USDT_SLUG, SOLANA_USDC_SLUG -> { configureStaticTag("Solana"); true }
            else -> configureStakingTag(accountId, token, tokenBalance)
        }
        updateLabelSpacing(cell, topLeftLabel, topRightView, shouldShow)
    }

    fun onThemeChanged() {
        tagLabel.updateTheme()
        cachedStakingTagDrawable = null
        cachedNotStakingTagDrawable = null
        if (isShowingStaticTag) {
            tagLabel.setBackgroundColor(WColor.BadgeBackground.color, 8f.dp)
        }
    }

    private fun getTagDrawable(hasStaking: Boolean, cornerRadius: Float = 8f): GradientDrawable {
        return if (hasStaking) {
            cachedStakingTagDrawable ?: HighlightGradientBackgroundDrawable(true, cornerRadius)
                .also { cachedStakingTagDrawable = it }
        } else {
            cachedNotStakingTagDrawable ?: HighlightGradientBackgroundDrawable(false, cornerRadius)
                .also { cachedNotStakingTagDrawable = it }
        }
    }

    private fun configureStaticTag(text: String) {
        isShowingStaticTag = true
        tagLabel.setAmount(text)
        tagLabel.setGradientColor(arrayOf(WColor.SecondaryText, WColor.SecondaryText))
        tagLabel.setBackgroundColor(WColor.BadgeBackground.color, 8f.dp)
    }

    private fun configureStakingTag(
        accountId: String?,
        token: MToken?,
        tokenBalance: MTokenBalance?
    ): Boolean {
        isShowingStaticTag = false
        if (tokenBalance?.isVirtualStakingRow != true && token?.isEarnAvailable != true) return false
        val stakingState = accountId?.let {
            StakingStore.getStakingState(it)?.stakingState(token?.slug ?: "")
        } ?: return false
        val apy = stakingState.annualYield ?: return false
        val hasStakingAmount = stakingState.balance > BigInteger.ZERO
        val shouldShow = tokenBalance?.isVirtualStakingRow == true || !hasStakingAmount
        if (shouldShow) {
            tagLabel.setGradientColor(
                if (hasStakingAmount) arrayOf(WColor.White, WColor.White)
                else arrayOf(WColor.EarnGradientLeft, WColor.EarnGradientRight)
            )
            tagLabel.setAmount(if (hasStakingAmount) "$apy%" else "${stakingState.yieldType} $apy%")
            tagLabel.background = getTagDrawable(hasStakingAmount, 8f.dp)
        }
        return shouldShow
    }

    private fun updateLabelSpacing(
        cell: WView,
        topLeftLabel: WLabel,
        topRightView: View,
        showTagLabel: Boolean
    ) {
        tagLabel.isGone = !showTagLabel
        if (wasShowingTagLabel == showTagLabel) return
        wasShowingTagLabel = showTagLabel
        topLeftLabel.layoutParams = topLeftLabel.layoutParams.apply {
            width = MATCH_CONSTRAINT
        }
        if (showTagLabel) {
            cell.setConstraints {
                clear(topLeftLabel.id, ConstraintSet.END)
                endToStart(topLeftLabel, tagLabel)
                endToStart(tagLabel, topRightView, 4f)
                constrainedWidth(topLeftLabel.id, true)
                setHorizontalBias(topLeftLabel.id, 0f)
                setHorizontalChainStyle(topLeftLabel.id, ConstraintSet.CHAIN_PACKED)
            }
        } else {
            tagLabel.visibility = View.GONE
            cell.setConstraints {
                clear(topLeftLabel.id, ConstraintSet.END)
                endToStart(topLeftLabel, topRightView, 4f)
                constrainedWidth(topLeftLabel.id, true)
                setHorizontalBias(topLeftLabel.id, 0f)
            }
        }
    }
}
