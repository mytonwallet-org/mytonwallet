package org.mytonwallet.app_air.uicomponents.widgets.autoComplete

import android.animation.Animator
import android.content.Context
import android.text.TextUtils
import android.view.Gravity
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import android.widget.FrameLayout
import androidx.constraintlayout.widget.ConstraintLayout.LayoutParams.MATCH_CONSTRAINT
import androidx.core.view.isGone
import androidx.core.view.isVisible
import androidx.core.view.updateLayoutParams
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import org.mytonwallet.app_air.uicomponents.AnimationConstants
import org.mytonwallet.app_air.uicomponents.commonViews.AccountIconView
import org.mytonwallet.app_air.uicomponents.commonViews.CardThumbnailView
import org.mytonwallet.app_air.uicomponents.drawable.WRippleDrawable
import org.mytonwallet.app_air.uicomponents.extensions.animatorSet
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.helpers.CubicBezierInterpolator
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.widgets.WCell
import org.mytonwallet.app_air.uicomponents.widgets.WFrameLayout
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.uicomponents.widgets.WMultichainAddressLabel
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.uicomponents.widgets.WView
import org.mytonwallet.app_air.uicomponents.widgets.sensitiveDataContainer.WSensitiveDataContainer
import org.mytonwallet.app_air.uicomponents.widgets.setBackgroundColor
import org.mytonwallet.app_air.walletbasecontext.theme.ThemeManager
import org.mytonwallet.app_air.walletbasecontext.theme.ViewConstants
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletbasecontext.utils.toString
import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.models.MAccount
import org.mytonwallet.app_air.walletcore.models.MSavedAddress
import org.mytonwallet.app_air.walletcore.stores.BalanceStore
import kotlin.math.abs

class WAutoCompleteAddressCell(context: Context) : WCell(
    context, LayoutParams(MATCH_PARENT, 60.dp)
), IAutoCompleteAddressItemCell, WThemedView {

    private val animationDuration = AnimationConstants.QUICK_ANIMATION
    private var animator: Animator? = null

    private var account: MAccount? = null
    private var address: MSavedAddress? = null
    private var keyword: String = ""
    private var isFirst: Boolean = false
    private var isLast: Boolean = false
    private var animationState: AutoCompleteAddressItem.AnimationState =
        AutoCompleteAddressItem.AnimationState.IDLE

    private val contentHeight = 60.dp

    private val iconView: AccountIconView by lazy {
        AccountIconView(context, AccountIconView.Usage.ViewItem(16f.dp))
    }

    private val titleLabel: WLabel by lazy {
        WLabel(context).apply {
            setStyle(16f, WFont.Medium)
            setTextColor(WColor.PrimaryText)
            setHighlightColor(WColor.Tint)
            setSingleLine()
            ellipsize = TextUtils.TruncateAt.MARQUEE
            isSelected = true
            isHorizontalFadingEdgeEnabled = true
        }
    }

    private val cardThumbnail: CardThumbnailView by lazy {
        CardThumbnailView(context)
    }

    private val addressLabel: WMultichainAddressLabel by lazy {
        WMultichainAddressLabel(context).apply {
            setStyle(13f, WFont.Regular)
            setTextColor(WColor.SecondaryText)
            isSelected = true
        }
    }

    private val valueLabel: WSensitiveDataContainer<WLabel> by lazy {
        val lbl = WLabel(context)
        lbl.setStyle(16f, WFont.Regular)
        lbl.gravity = Gravity.LEFT
        lbl.layoutDirection = LAYOUT_DIRECTION_LTR
        WSensitiveDataContainer(
            lbl,
            WSensitiveDataContainer.MaskConfig(0, 2, Gravity.END or Gravity.CENTER_VERTICAL)
        )
    }

    private val trailingContainerView: WFrameLayout by lazy {
        WFrameLayout(context).apply {
            addView(valueLabel, FrameLayout.LayoutParams(WRAP_CONTENT, WRAP_CONTENT).apply {
                gravity = Gravity.END or Gravity.CENTER_VERTICAL
            })
        }
    }

    val contentView = WView(context).apply {
        addView(iconView, LayoutParams(44.dp, 44.dp))
        addView(
            titleLabel,
            LayoutParams(WRAP_CONTENT, WRAP_CONTENT)
        )
        addView(
            cardThumbnail,
            LayoutParams(22.dp, 14.dp)
        )
        addView(
            addressLabel,
            LayoutParams(MATCH_CONSTRAINT, WRAP_CONTENT)
        )
        addView(trailingContainerView)

        setConstraints {
            // Icon
            toStart(iconView, 12f)
            toCenterY(iconView)

            // Title
            toTop(titleLabel, 8f)
            toStart(titleLabel, 68f)
            setHorizontalBias(titleLabel.id, 0f)
            constrainedWidth(titleLabel.id, true)

            // Card-Thumbnail
            centerYToCenterY(cardThumbnail, titleLabel)
            startToEnd(cardThumbnail, titleLabel, 6f)
            setHorizontalBias(cardThumbnail.id, 0f)

            // Value
            toCenterY(trailingContainerView)
            toEnd(trailingContainerView, 16f)
            setHorizontalBias(trailingContainerView.id, 1f)
            endToStartPx(cardThumbnail, trailingContainerView, 4.dp)

            // Subtitle
            topToBottom(addressLabel, titleLabel)
            startToStart(addressLabel, titleLabel)
            endToStart(addressLabel, trailingContainerView, 4f)
            setHorizontalBias(addressLabel.id, 0f)
            constrainedWidth(addressLabel.id, true)
        }
    }

    private val backgroundContainer: FrameLayout = WFrameLayout(context).apply {
        addView(contentView, LayoutParams(MATCH_PARENT, contentHeight))
    }

    init {
        super.setupViews()

        addView(backgroundContainer, LayoutParams(MATCH_PARENT, contentHeight))
        setConstraints {
            toTop(backgroundContainer)
            toCenterX(backgroundContainer)
        }
    }

    override fun configure(
        item: AutoCompleteAddressItem,
        onTap: () -> Unit,
        changeAnimationFinishListener: (() -> Unit),
        onLongClick: (() -> Unit)?,
    ) {
        val account = item.account
        if (account == null) {
            this.account = null
        }
        val address = item.savedAddress
        if (address == null) {
            this.address = null
        }
        if (!configureAccount(
                account = account,
                balance = item.value ?: "",
                keyword = item.keyword,
                isFirst = item.isFirst,
                isLast = item.isLast,
                animationState = item.animationState
            ) && !configureAddress(
                address = address,
                keyword = item.keyword,
                isFirst = item.isFirst,
                isLast = item.isLast,
                animationState = item.animationState
            )
        ) {
            return
        }

        val stateChanged = this.animationState != item.animationState

        this.isFirst = item.isFirst
        this.isLast = item.isLast
        this.keyword = item.keyword
        this.animationState = item.animationState

        contentView.setConstraints {
            endToStart(
                titleLabel,
                trailingContainerView,
                16f + (if (cardThumbnail.isGone) 0f else 22f)
            )
        }
        val itemGap = if (item.isLast) ViewConstants.GAP.dp else 0
        val totalItemHeight = contentHeight + itemGap
        if (layoutParams.height != totalItemHeight) {
            updateLayoutParams { height = totalItemHeight }
            setPadding(0, 0, 0, itemGap)
        }

        backgroundContainer.setOnClickListener {
            onTap()
        }
        if (onLongClick != null) {
            backgroundContainer.setOnLongClickListener {
                onLongClick()
                true
            }
        } else {
            backgroundContainer.setOnLongClickListener(null)
        }

        updateTheme()
        updateRadius()
        updateAddressLabel()

        if (account != null) {
            valueLabel.isVisible = true
            valueLabel.isSensitiveData = true
            valueLabel.setMaskCols(8 + abs(account.name.hashCode()) % 8)
        } else {
            valueLabel.isVisible = false
        }

        if (!stateChanged) {
            return
        }
        when (animationState) {
            AutoCompleteAddressItem.AnimationState.IDLE -> {
                animator?.cancel()
                animator = null
                resetCollapseProgress()
            }

            AutoCompleteAddressItem.AnimationState.DISAPPEARING -> animateCollapse(
                if (isFirst) 0 else itemGap,
                changeAnimationFinishListener
            )

            AutoCompleteAddressItem.AnimationState.CORNER_ROUNDING -> animateRounding(
                changeAnimationFinishListener
            )
        }
    }

    private fun resetCollapseProgress() {
        backgroundContainer.translationY = 0f
        contentView.alpha = 1f
        contentView.scaleX = 1f
        contentView.scaleY = 1f
    }

    override fun hasActiveAnimation(): Boolean {
        return animator?.isRunning == true
    }

    private fun animateCollapse(targetHeight: Int, finishListener: () -> Unit) {
        animator = animatorSet {
            duration(animationDuration)
            interpolator(CubicBezierInterpolator.EASE_OUT)
            together {
                intValues(height, targetHeight) {
                    onUpdate { h -> updateLayoutParams { height = h } }
                }
                viewProperty(backgroundContainer) {
                    translationY(-contentHeight.toFloat())
                }
                viewProperty(contentView) {
                    duration(animationDuration / 4)
                    alpha(0f)
                    scaleX(0.95f)
                    scaleY(0.8f)
                }
            }
            onEnd { finishListener() }
        }.also { it.start() }
    }

    private fun animateRounding(finishListener: () -> Unit) {
        animator = animatorSet {
            startDelay((animationDuration * ((contentHeight - ViewConstants.BLOCK_RADIUS.dp) / contentHeight)).toLong())
            duration((animationDuration * 0.8).toLong())
            interpolator(CubicBezierInterpolator.EASE_OUT)
            together {
                floatValues(0f, ViewConstants.BLOCK_RADIUS.dp) {
                    onUpdate { r -> updateBottomRadius(r) }
                }
            }
            onEnd { finishListener() }
        }.also { it.start() }
    }

    private fun configureAccount(
        account: MAccount?,
        balance: String,
        keyword: String,
        isFirst: Boolean,
        isLast: Boolean,
        animationState: AutoCompleteAddressItem.AnimationState,
    ): Boolean {
        if (account == null) {
            this.account = null
            return false
        }
        if (this.account == account &&
            titleLabel.text == account.name &&
            valueLabel.contentView.text == balance &&
            this.keyword == keyword &&
            this.isFirst == isFirst &&
            this.isLast == isLast &&
            this.animationState == animationState
        ) {
            updateTheme()
            notifyBalanceChange()
            return false
        }

        this.account = account
        this.address = null

        iconView.config(account)
        cardThumbnail.configure(account)
        titleLabel.text = account.name
        if (keyword.isNotEmpty()) {
            titleLabel.highlight(keyword)
        } else {
            titleLabel.resetHighlight()
        }
        valueLabel.contentView.text = balance

        return true
    }

    private fun configureAddress(
        address: MSavedAddress?,
        keyword: String,
        isFirst: Boolean,
        isLast: Boolean,
        animationState: AutoCompleteAddressItem.AnimationState
    ): Boolean {
        if (address == null) {
            this.address = null
            return false
        }
        if (this.address == address &&
            titleLabel.text == address.name &&
            this.keyword == keyword &&
            this.isFirst == isFirst &&
            this.isLast == isLast &&
            this.animationState == animationState
        ) {
            updateTheme()
            notifyBalanceChange()
            return false
        }
        this.account = null
        this.address = address

        iconView.config(address)
        cardThumbnail.configure(null)
        titleLabel.text = address.name

        if (keyword.isNotEmpty()) {
            titleLabel.highlight(keyword)
        } else {
            titleLabel.resetHighlight()
        }

        return true
    }

    private var _isDarkThemeApplied: Boolean? = null
    override fun updateTheme() {
        val darkModeChanged = ThemeManager.isDark != _isDarkThemeApplied
        if (!darkModeChanged)
            return
        _isDarkThemeApplied = ThemeManager.isDark

        updateRadius()
        updateAddressLabel()
        titleLabel.updateTheme()
        addressLabel.updateTheme()
        valueLabel.contentView.setTextColor(WColor.SecondaryText.color)
    }

    private fun updateRadius() {
        updateBottomRadius(if (isLast) ViewConstants.BLOCK_RADIUS.dp else 0f.dp)
    }

    private fun updateBottomRadius(radius: Float) {
        backgroundContainer.setBackgroundColor(WColor.Background.color, 0f.dp, radius)
        backgroundContainer.background = WRippleDrawable.create(0f, 0f, radius, radius).apply {
            backgroundColor = WColor.Background.color
            rippleColor = WColor.SecondaryBackground.color
        }
    }

    private fun updateAddressLabel() {
        val style = when (account?.accountType) {
            MAccount.AccountType.VIEW -> WMultichainAddressLabel.cardRowWalletViewStyle
            MAccount.AccountType.HARDWARE -> WMultichainAddressLabel.cardRowWalletHardwareStyle
            else -> WMultichainAddressLabel.cardRowWalletStyle
        }
        val account = this.account
        val address = this.address
        when {
            account != null -> addressLabel.displayAddresses(account, style, keyword)
            address != null -> addressLabel.displayAddresses(address, style, keyword)
        }

    }

    fun notifyBalanceChange() {
        val accountId = account?.accountId ?: return
        val baseCurrency = WalletCore.baseCurrency
        CoroutineScope(Dispatchers.Main).launch {
            val balanceDouble = withContext(Dispatchers.Default) {
                BalanceStore.totalBalanceInBaseCurrency(accountId)
            } ?: run {
                if (valueLabel.contentView.text != "")
                    valueLabel.contentView.text = ""
                return@launch
            }
            val newValue = balanceDouble.toString(
                baseCurrency.decimalsCount,
                baseCurrency.sign,
                baseCurrency.decimalsCount,
                true,
            )
            if (valueLabel.contentView.text != newValue)
                valueLabel.contentView.text = newValue
        }
    }
}
