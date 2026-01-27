package org.mytonwallet.uihome.wallets.cells

import android.animation.ValueAnimator
import android.annotation.SuppressLint
import android.content.Context
import android.os.Handler
import android.os.Looper
import android.text.TextUtils
import android.view.Gravity
import android.view.MotionEvent
import android.view.ViewConfiguration
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import android.view.animation.AccelerateDecelerateInterpolator
import androidx.appcompat.widget.AppCompatImageView
import androidx.constraintlayout.widget.ConstraintLayout.LayoutParams.MATCH_CONSTRAINT
import androidx.core.content.ContextCompat
import androidx.core.view.isGone
import org.mytonwallet.app_air.uicomponents.AnimationConstants
import org.mytonwallet.app_air.uicomponents.commonViews.AccountIconView
import org.mytonwallet.app_air.uicomponents.commonViews.CardThumbnailView
import org.mytonwallet.app_air.uicomponents.drawable.CheckboxDrawable
import org.mytonwallet.app_air.uicomponents.drawable.WRippleDrawable
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.widgets.WBaseView
import org.mytonwallet.app_air.uicomponents.widgets.WCell
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.uicomponents.widgets.WMultichainAddressLabel
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.uicomponents.widgets.WView
import org.mytonwallet.app_air.uicomponents.widgets.sensitiveDataContainer.WSensitiveDataContainer
import org.mytonwallet.app_air.walletbasecontext.theme.ThemeManager
import org.mytonwallet.app_air.walletbasecontext.theme.ViewConstants
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletbasecontext.utils.toString
import org.mytonwallet.app_air.walletcontext.utils.AnimUtils.Companion.lerp
import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.models.MAccount
import org.mytonwallet.app_air.walletcore.stores.BalanceStore
import kotlin.math.abs

@SuppressLint("ViewConstructor")
class WalletCardRowCell(
    context: Context,
    var reordering: Boolean,
    private val onTouchStart: (view: WView) -> Unit,
    private val onClick: (accountId: MAccount) -> Unit,
    private val onLongClick: (cell: WalletCardRowCell, view: WView, account: MAccount) -> Unit,
    private val onCheckChanged: (account: MAccount, isChecked: Boolean) -> Unit,
) :
    WCell(context, LayoutParams(MATCH_PARENT, 60.dp)), WThemedView, IWalletCardCell {

    companion object {
        private const val REORDERING_OFFSET = 42f
    }

    private var account: MAccount? = null
    private var isFirst = false
    private var isLast = false

    private val reorderingOffset: Float
        get() {
            return if (reordering) REORDERING_OFFSET.dp else 0f
        }

    private val ripple = WRippleDrawable.create(0f)

    private val checkboxDrawable = CheckboxDrawable {
        invalidate()
    }

    private val checkboxImageView = AppCompatImageView(context).apply {
        id = generateViewId()
        setImageDrawable(checkboxDrawable)
        translationX = reorderingOffset - REORDERING_OFFSET.dp
        alpha = 0f
    }

    private val iconView: AccountIconView by lazy {
        AccountIconView(context, AccountIconView.Usage.SelectableItem(16f.dp))
    }

    private val titleLabel: WLabel by lazy {
        WLabel(context).apply {
            setStyle(16f, WFont.DemiBold)
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
            setStyle(13f)
            isSelected = true
        }
    }

    private val valueLabel: WSensitiveDataContainer<WLabel> by lazy {
        val lbl = WLabel(context)
        lbl.setStyle(16f)
        lbl.gravity = Gravity.LEFT
        lbl.layoutDirection = LAYOUT_DIRECTION_LTR
        WSensitiveDataContainer(
            lbl,
            WSensitiveDataContainer.MaskConfig(0, 2, Gravity.END or Gravity.CENTER_VERTICAL)
        )
    }

    private val handleButton: AppCompatImageView by lazy {
        AppCompatImageView(context).apply {
            id = generateViewId()
            setImageDrawable(
                ContextCompat.getDrawable(
                    context,
                    org.mytonwallet.uihome.R.drawable.ic_handle
                )
            )
            alpha = 0f
            translationX = -reorderingOffset + REORDERING_OFFSET.dp
        }
    }

    private val contentView = object : WView(context) {

        private var downX = 0f
        private var downY = 0f
        private val touchSlop = ViewConfiguration.get(context).scaledTouchSlop
        private val longPressTimeout = ViewConfiguration.getLongPressTimeout().toLong()
        private val handler = Handler(Looper.getMainLooper())
        private var hasPerformedLongClick = false

        @SuppressLint("ClickableViewAccessibility")
        override fun onTouchEvent(event: MotionEvent): Boolean {
            when (event.actionMasked) {
                MotionEvent.ACTION_DOWN -> {
                    downX = event.x
                    downY = event.y
                    isPressed = true
                    hasPerformedLongClick = false

                    handler.postDelayed({
                        if (isPressed) {
                            hasPerformedLongClick = performLongClick()
                            if (hasPerformedLongClick) {
                                isPressed = false
                            }
                        }
                    }, longPressTimeout)

                    onTouchStart(this)
                    requestDisallowInterceptTouchEvent(true)
                }

                MotionEvent.ACTION_MOVE -> {
                    val dx = abs(event.x - downX)
                    val dy = abs(event.y - downY)
                    if (dx >= touchSlop || dy >= touchSlop) {
                        isPressed = false
                    }
                }

                MotionEvent.ACTION_UP -> {
                    if (isPressed && !hasPerformedLongClick) {
                        performClick()
                    }
                    isPressed = false
                }

                MotionEvent.ACTION_CANCEL -> {
                    requestDisallowInterceptTouchEvent(false)
                    isPressed = false
                }
            }
            return false
        }

    }.apply {
        background = ripple
        clipChildren = false
        clipToPadding = false
        addView(checkboxImageView, LayoutParams(22.dp, 22.dp))
        addView(iconView, LayoutParams(43.dp, 43.dp))
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
        addView(valueLabel, LayoutParams(WRAP_CONTENT, WRAP_CONTENT))
        addView(handleButton, LayoutParams(30.dp, 30.dp))

        setConstraints {
            // Checkbox
            toStart(checkboxImageView, 16f)
            toCenterY(checkboxImageView)

            // Icon
            toStart(iconView, 10.5f)
            toCenterY(iconView)

            // Title
            toTop(titleLabel, 9f)
            toStart(titleLabel, 64f)
            setHorizontalBias(titleLabel.id, 0f)
            constrainedWidth(titleLabel.id, true)

            // Card-Thumbnail
            centerYToCenterY(cardThumbnail, titleLabel)
            startToEnd(cardThumbnail, titleLabel, 6f)
            setHorizontalBias(cardThumbnail.id, 0f)

            // Value
            toCenterY(valueLabel)
            toEnd(valueLabel, 16f)
            setHorizontalBias(valueLabel.id, 1f)
            endToStartPx(cardThumbnail, valueLabel, 4.dp)

            // Handle
            toCenterY(handleButton)
            toEnd(handleButton, 16f)

            // Subtitle
            topToBottom(addressLabel, titleLabel, 1f)
            startToStart(addressLabel, titleLabel)
            endToStart(addressLabel, valueLabel, 4f)
            setHorizontalBias(addressLabel.id, 0f)
            constrainedWidth(addressLabel.id, true)
        }

        setOnClickListener {
            if (reordering)
                setChecked(!isChecked)
            else
                account?.let { onClick(it) }
        }

        setOnLongClickListener {
            if (reordering)
                return@setOnLongClickListener true
            account?.let { onLongClick(this@WalletCardRowCell, this, it) }
            true
        }
    }

    override var isShowingPopup = false

    init {
        super.setupViews()

        addView(contentView, LayoutParams(MATCH_PARENT, MATCH_PARENT))
        updateTheme()
    }

    fun configure(
        account: MAccount,
        isFirst: Boolean,
        isLast: Boolean,
        isChecked: Boolean,
        reordering: Boolean
    ) {
        this.account = account
        this.isFirst = isFirst
        this.isLast = isLast
        this.isChecked = isChecked

        iconView.config(account)
        cardThumbnail.configure(account)
        if (titleLabel.text != account.name) {
            titleLabel.text = account.name
        }
        notifyBalanceChange()

        contentView.setConstraints {
            endToStart(
                titleLabel,
                valueLabel,
                16f + (if (cardThumbnail.isGone) 0f else 22f)
            )
        }

        updateTheme()

        valueLabel.isSensitiveData = true
        valueLabel.setMaskCols(8 + abs(account.name.hashCode()) % 8)

        checkboxDrawable.setChecked(isChecked, false)
        toggleReordering(reordering, false)
    }

    override fun updateTheme() {
        checkboxDrawable.checkedColor = WColor.Tint.color
        checkboxDrawable.uncheckedColor = WColor.SecondaryText.color
        ripple.rippleColor = WColor.BackgroundRipple.color
        titleLabel.setTextColor(WColor.PrimaryText.color)
        addressLabel.setTextColor(WColor.SecondaryText.color)
        valueLabel.contentView.setTextColor(WColor.SecondaryText.color)
        val style = when (account?.accountType) {
            MAccount.AccountType.VIEW -> WMultichainAddressLabel.cardRowWalletViewStyle
            MAccount.AccountType.HARDWARE -> WMultichainAddressLabel.cardRowWalletHardwareStyle
            else -> WMultichainAddressLabel.cardRowWalletStyle
        }
        addressLabel.displayAddresses(account, style)
    }

    override fun notifyBalanceChange() {
        val accountId = account?.accountId ?: return
        val baseCurrency = WalletCore.baseCurrency
        val balance = BalanceStore.totalBalanceInBaseCurrency(accountId)
        valueLabel.contentView.text = balance?.toString(
            baseCurrency.decimalsCount,
            baseCurrency.sign,
            baseCurrency.decimalsCount,
            true
        )
    }

    private var isChecked: Boolean = false
    fun setChecked(isChecked: Boolean) {
        this.isChecked = isChecked
        checkboxDrawable.setChecked(isChecked, true)
        account?.let { it ->
            onCheckChanged(it, isChecked)
        }
    }

    fun toggleReordering(reordering: Boolean, animated: Boolean) {
        this.reordering = reordering

        // Final target values
        val checkboxTx = if (reordering) 0f else -REORDERING_OFFSET.dp
        val checkboxAlpha = if (reordering) 1f else 0f

        val genericTx = reorderingOffset

        val valueAlpha = if (reordering) 0f else 1f
        val handleTx = if (reordering) 0f else REORDERING_OFFSET.dp
        val handleAlpha = if (reordering) 1f else 0f

        handleButton.isGone = false
        valueLabel.isGone = false

        val checkboxStartTx = checkboxImageView.translationX
        val checkboxStartAlpha = checkboxImageView.alpha

        val iconTxStart = iconView.translationX
        val titleTxStart = titleLabel.translationX
        val subtitleTxStart = addressLabel.translationX
        val cardThumbTxStart = cardThumbnail.translationX

        val valueStartTx = valueLabel.translationX
        val valueStartAlpha = valueLabel.alpha

        val handleStartTx = handleButton.translationX
        val handleStartAlpha = handleButton.alpha

        fun render(fraction: Float) {
            // Checkbox
            checkboxImageView.translationX =
                lerp(checkboxStartTx, checkboxTx, fraction)
            checkboxImageView.alpha =
                lerp(checkboxStartAlpha, checkboxAlpha, fraction)

            // Icons / labels
            iconView.translationX = lerp(iconTxStart, genericTx, fraction)
            titleLabel.translationX = lerp(titleTxStart, genericTx, fraction)
            addressLabel.translationX = lerp(subtitleTxStart, genericTx, fraction)
            cardThumbnail.translationX = lerp(cardThumbTxStart, genericTx, fraction)

            // Value label
            valueLabel.translationX =
                lerp(valueStartTx, genericTx, fraction)
            valueLabel.alpha =
                lerp(valueStartAlpha, valueAlpha, fraction)

            // Handle button
            handleButton.translationX =
                lerp(handleStartTx, handleTx, fraction)
            handleButton.alpha =
                lerp(handleStartAlpha, handleAlpha, fraction)

            if (fraction == 1f) {
                if (reordering)
                    valueLabel.isGone = true
                else
                    handleButton.isGone = true
            }
        }
        if (!animated) {
            render(1f)
            return
        }

        ValueAnimator.ofFloat(0f, 1f).apply {
            this.duration = AnimationConstants.VERY_QUICK_ANIMATION
            this.interpolator = AccelerateDecelerateInterpolator()

            addUpdateListener { anim ->
                render(anim.animatedFraction)
            }
            start()
        }
    }

}
