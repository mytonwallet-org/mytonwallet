@file:Suppress("ktlint:standard:backing-property-naming")

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
import android.widget.ImageView
import androidx.core.view.isGone
import java.math.BigInteger
import kotlin.math.abs
import org.mytonwallet.app_air.icons.R
import org.mytonwallet.app_air.uiassets.viewControllers.tokens.TokensVC
import org.mytonwallet.app_air.uicomponents.AnimationConstants
import org.mytonwallet.app_air.uicomponents.commonViews.IconView
import org.mytonwallet.app_air.uicomponents.extensions.animatorSet
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.helpers.CubicBezierInterpolator
import org.mytonwallet.app_air.uicomponents.helpers.TokenNameHelper
import org.mytonwallet.app_air.uicomponents.helpers.TokenTagHelper
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.helpers.adaptiveFontSize
import org.mytonwallet.app_air.uicomponents.widgets.WCell
import org.mytonwallet.app_air.uicomponents.widgets.WEvaporateLabel
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
import org.mytonwallet.app_air.walletbasecontext.utils.getDrawableCompat
import org.mytonwallet.app_air.walletbasecontext.utils.signSpace
import org.mytonwallet.app_air.walletbasecontext.utils.smartDecimalsCount
import org.mytonwallet.app_air.walletbasecontext.utils.toString
import org.mytonwallet.app_air.walletbasecontext.utils.withLocalizedNumbers
import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage
import org.mytonwallet.app_air.walletcore.STAKE_SLUG
import org.mytonwallet.app_air.walletcore.TONCOIN_SLUG
import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.models.MToken
import org.mytonwallet.app_air.walletcore.models.MTokenBalance
import org.mytonwallet.app_air.walletcore.moshi.StakingState
import org.mytonwallet.app_air.walletcore.stores.StakingStore
import org.mytonwallet.app_air.walletcore.stores.TokenStore

@SuppressLint("ViewConstructor")
class TokenCell(context: Context, val mode: TokensVC.Mode) :
    WCell(context),
    WThemedView {

    private val iconView: IconView by lazy {
        val iv = IconView(context, ApplicationContextHolder.adaptiveIconSize.dp)
        iv
    }

    private val pinIcon: ImageView by lazy {
        ImageView(context).apply {
            id = generateViewId()
        }
    }

    private val topLeftLabel: WLabel by lazy {
        val lbl = WLabel(context)
        lbl.setStyle(adaptiveFontSize(), WFont.Medium)
        lbl.setSingleLine()
        lbl.ellipsize = TextUtils.TruncateAt.END
        lbl.isHorizontalFadingEdgeEnabled = true
        lbl
    }

    private val tagHelper = TokenTagHelper(context)

    private val bottomLeftLabel: WLabel by lazy {
        WLabel(context).apply {
            setStyle(13f)
            setSingleLine()
            setTextColor(WColor.SecondaryText)
            ellipsize = TextUtils.TruncateAt.MARQUEE
            isHorizontalFadingEdgeEnabled = true
            isSelected = true
        }
    }

    private val topRightLabel: WSensitiveDataContainer<WEvaporateLabel> by lazy {
        val lbl = WEvaporateLabel(context)
        lbl.setStyle(adaptiveFontSize())
        WSensitiveDataContainer(
            lbl,
            WSensitiveDataContainer.MaskConfig(0, 2, Gravity.END or Gravity.CENTER_VERTICAL)
        )
    }

    private val bottomRightLabel: WSensitiveDataContainer<WEvaporateLabel> by lazy {
        val lbl = WEvaporateLabel(context)
        lbl.setStyle(13f)
        lbl.layoutDirection = LAYOUT_DIRECTION_LTR
        WSensitiveDataContainer(
            lbl,
            WSensitiveDataContainer.MaskConfig(0, 2, Gravity.END or Gravity.CENTER_VERTICAL)
        )
    }

    var onTap: ((tokenBalance: MTokenBalance) -> Unit)? = null

    var onLongPress: ((tokenBalance: MTokenBalance) -> Unit)? = null

    init {
        layoutParams.apply {
            height = 60.dp
        }
        addView(
            iconView,
            LayoutParams(
                (ApplicationContextHolder.adaptiveIconSize + 2).dp,
                (ApplicationContextHolder.adaptiveIconSize + 2).dp
            )
        )
        addView(pinIcon, LayoutParams(14.dp, 20.dp))
        addView(topLeftLabel, LayoutParams(WRAP_CONTENT, WRAP_CONTENT))
        addView(tagHelper.tagLabel, LayoutParams(WRAP_CONTENT, 16.dp))
        addView(topRightLabel)
        addView(bottomLeftLabel)
        addView(bottomRightLabel)
        setConstraints {
            // Icon View
            toTop(iconView, ApplicationContextHolder.adaptiveIconTopMargin)
            toStart(iconView, 12f)
            // Top Row
            toTop(topLeftLabel, 9f)
            toStart(pinIcon, ApplicationContextHolder.adaptiveContentStart)
            toStart(topLeftLabel, ApplicationContextHolder.adaptiveContentStart + 18)
            centerYToCenterY(pinIcon, topLeftLabel)
            startToEnd(tagHelper.tagLabel, topLeftLabel, 3f)
            centerYToCenterY(tagHelper.tagLabel, topLeftLabel)
            endToStart(tagHelper.tagLabel, topRightLabel, 4f)
            toTop(topRightLabel, 9f)
            toEnd(topRightLabel, 16f)
            constrainedWidth(topLeftLabel.id, true)
            setHorizontalBias(topLeftLabel.id, 0f)
            setHorizontalBias(tagHelper.tagLabel.id, 0f)
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
        setOnLongClickListener {
            tokenBalance?.let {
                onLongPress?.invoke(it)
            }
            onLongPress != null
        }
    }

    private var _isDarkThemeApplied: Boolean? = null
    override fun updateTheme() {
        updateTheme(forceUpdate = false)
    }

    private fun updateTheme(forceUpdate: Boolean) {
        val darkModeChanged = ThemeManager.isDark != _isDarkThemeApplied
        if (!forceUpdate && !darkModeChanged) return
        _isDarkThemeApplied = ThemeManager.isDark
        setBackgroundColor(
            if (mode == TokensVC.Mode.HOME) Color.TRANSPARENT else WColor.Background.color,
            if (isFirst) ViewConstants.TOOLBAR_RADIUS.dp else 0f,
            if (isLast) ViewConstants.BLOCK_RADIUS.dp else 0f
        )
        addRippleEffect(
            WColor.SecondaryBackground.color,
            if (isFirst) ViewConstants.TOOLBAR_RADIUS.dp else 0f,
            if (isLast) ViewConstants.BLOCK_RADIUS.dp else 0f
        )
        topLeftLabel.setTextColor(WColor.PrimaryText.color)
        tagHelper.onThemeChanged()
        topRightLabel.contentView.setTextColor(WColor.PrimaryText.color)
        topRightLabel.contentView.updateTheme()
        bottomRightLabel.contentView.setTextColor(WColor.SecondaryText.color)
        bottomRightLabel.contentView.updateTheme()
        tokenBalance?.let {
            updateBottomLeftLabel(it, null)
        }
        val drawable = context.getDrawableCompat(R.drawable.ic_pin_solid_14_20)?.apply {
            setTint(WColor.SecondaryText.color)
        }
        pinIcon.setImageDrawable(drawable)
    }

    private var accountId: String? = null
    private var tokenBalance: MTokenBalance? = null
    private var baseCurrency: MBaseCurrency? = null
    private var stakingState: StakingState? = null
    private var isFirst = false
    private var isLast = false
    private var isPinned = false

    fun configure(
        accountId: String,
        isMultichain: Boolean,
        tokenBalance: MTokenBalance,
        isPinned: Boolean,
        isFirst: Boolean,
        isLast: Boolean
    ) {
        val firstChanged = this.isFirst != isFirst
        val lastChanged = this.isLast != isLast
        val baseCurrency = WalletCore.baseCurrency
        this.isFirst = isFirst
        this.isLast = isLast

        val accountChanged = this.accountId != accountId
        val tokenChanged =
            this.tokenBalance?.virtualStakingToken != tokenBalance.virtualStakingToken
        val pinnedChanged = this.isPinned != isPinned
        val token = TokenStore.getToken(tokenBalance.token)
        val tokenName = token?.let { TokenNameHelper.getTokenName(it, tokenBalance) } ?: ""
        val stakingState = if (token?.isEarnAvailable == true || tokenBalance.isVirtualStakingRow) {
            StakingStore.getStakingState(accountId)?.stakingState(token?.slug)
        } else {
            null
        }
        if (!accountChanged &&
            this.tokenBalance == tokenBalance &&
            this.baseCurrency == baseCurrency &&
            !pinnedChanged &&
            topLeftLabel.text?.toString() == tokenName
        ) {
            updateTheme(forceUpdate = firstChanged || lastChanged)
            if (this.stakingState != stakingState) {
                this.stakingState = stakingState
                tagHelper.configure(
                    this,
                    topLeftLabel,
                    topRightLabel,
                    accountId,
                    token,
                    tokenBalance
                )
            }
            return
        }

        this.accountId = accountId
        this.tokenBalance = tokenBalance
        this.baseCurrency = baseCurrency
        this.stakingState = stakingState
        this.isPinned = isPinned
        updateTheme(forceUpdate = firstChanged || lastChanged)
        if (pinnedChanged && !accountChanged) {
            animatePin(isPinned)
        } else {
            pinIcon.isGone = !isPinned
            val pinMargin = if (isPinned) 18 else 0
            setConstraints {
                toStart(topLeftLabel, ApplicationContextHolder.adaptiveContentStart + pinMargin)
            }
        }

        val amountCols = 4 + abs(tokenBalance.virtualStakingToken.hashCode() % 8)
        topRightLabel.setMaskCols(amountCols)
        val fiatAmountCols = 5 + (amountCols % 6)
        bottomRightLabel.setMaskCols(fiatAmountCols)
        topRightLabel.updateProtectedView(false)
        bottomRightLabel.updateProtectedView(false)

        iconView.config(
            tokenBalance,
            showChain = isMultichain,
            showPercentBadge = (
                tokenBalance.isVirtualStakingRow &&
                    tokenBalance.amountValue > BigInteger.ZERO
                )
        )
        if (topLeftLabel.text != tokenName) topLeftLabel.text = tokenName
        val animateTexts = !accountChanged && !tokenChanged
        topRightLabel.contentView.animateText(
            tokenBalance.amountValue.toString(
                decimals = token?.decimals ?: 9,
                currency = token?.symbol ?: "",
                currencyDecimals = tokenBalance.amountValue.smartDecimalsCount(
                    token?.decimals ?: 9
                ),
                showPositiveSign = false
            ),
            animateTexts
        )
        updateBottomLeftLabel(tokenBalance, token)
        bottomRightLabel.contentView.animateText(
            tokenBalance.toBaseCurrency?.toString(
                decimals = token?.decimals ?: 9,
                currency = baseCurrency.sign,
                currencyDecimals = token?.decimals ?: 9,
                smartDecimals = true,
                showPositiveSign = false
            ),
            animateTexts
        )

        tagHelper.configure(this, topLeftLabel, topRightLabel, accountId, token, tokenBalance)
    }

    private fun animatePin(isPinned: Boolean) {
        val marginUpdate = { margin: Int ->
            setConstraints {
                toStart(
                    topLeftLabel,
                    ApplicationContextHolder.adaptiveContentStart + margin
                )
            }
        }
        val pinUpdate = { alpha: Float, scale: Float ->
            pinIcon.alpha = alpha
            pinIcon.scaleX = scale
            pinIcon.scaleY = scale
        }
        pinIcon.isGone = false
        val onEnd = {
            if (isPinned) {
                marginUpdate(18)
                pinUpdate(1f, 1f)
            } else {
                marginUpdate(0)
                pinUpdate(0f, 0f)
                pinIcon.isGone = true
            }
        }
        if (!WGlobalStorage.getAreAnimationsActive()) {
            onEnd()
            return
        }
        animatorSet {
            duration(AnimationConstants.VERY_VERY_QUICK_ANIMATION)
            interpolator(CubicBezierInterpolator.EASE_OUT)
            together {
                if (isPinned) {
                    intValues(0, 18) {
                        onUpdate { margin -> marginUpdate(margin) }
                    }
                    viewProperty(pinIcon) {
                        alpha(0f, 1f)
                        scaleX(0f, 1f)
                        scaleY(0f, 1f)
                    }
                } else {
                    intValues(18, 0) {
                        onUpdate { margin -> marginUpdate(margin) }
                    }
                    viewProperty(pinIcon) {
                        alpha(1f, 0f)
                        scaleX(1f, 0f)
                        scaleY(1f, 0f)
                    }
                }
            }
            onEnd { onEnd() }
        }.start()
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
        val directionalAmountText =
            if (LocaleController.isRTL) "\u200F\u200E$amountText\u200F" else amountText

        val percentChange = pricedToken.percentChange24h
        val percentChangeText = when {
            percentChange < 0 -> " -$signSpace${abs(percentChange)}%"
            percentChange > 0 && percentChange.isFinite() -> " +$signSpace$percentChange%"
            else -> ""
        }

        if (percentChangeText.isEmpty()) {
            bottomLeftLabel.text = directionalAmountText
            return
        }

        val formattedText =
            directionalAmountText + (if (LocaleController.isRTL) " · \u202D" else "") +
                percentChangeText.withLocalizedNumbers
        val spannableString = SpannableString(formattedText)
        val amountLength = directionalAmountText.length + (if (LocaleController.isRTL) 3 else 0)

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
