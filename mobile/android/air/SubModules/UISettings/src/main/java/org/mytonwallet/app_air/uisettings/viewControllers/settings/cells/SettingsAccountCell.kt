package org.mytonwallet.app_air.uisettings.viewControllers.settings.cells

import android.content.Context
import android.text.SpannableStringBuilder
import android.text.Spanned
import android.text.TextUtils
import android.view.Gravity
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import android.widget.FrameLayout
import androidx.core.content.ContextCompat
import androidx.core.view.isGone
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import org.mytonwallet.app_air.uicomponents.commonViews.AccountIconView
import org.mytonwallet.app_air.uicomponents.commonViews.CardThumbnailView
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.extensions.updateDotsTypeface
import org.mytonwallet.app_air.uicomponents.helpers.spans.WSpacingSpan
import org.mytonwallet.app_air.uicomponents.widgets.WBaseView
import org.mytonwallet.app_air.uicomponents.widgets.WCell
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.uicomponents.widgets.WView
import org.mytonwallet.app_air.uicomponents.widgets.sensitiveDataContainer.WSensitiveDataContainer
import org.mytonwallet.app_air.uicomponents.widgets.setBackgroundColor
import org.mytonwallet.app_air.uisettings.viewControllers.settings.models.SettingsItem
import org.mytonwallet.app_air.walletbasecontext.theme.ThemeManager
import org.mytonwallet.app_air.walletbasecontext.theme.ViewConstants
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletbasecontext.utils.formatStartEndAddress
import org.mytonwallet.app_air.walletbasecontext.utils.toString
import org.mytonwallet.app_air.walletcontext.utils.VerticalImageSpan
import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.models.MAccount
import org.mytonwallet.app_air.walletcore.models.MBlockchain
import org.mytonwallet.app_air.walletcore.stores.BalanceStore
import kotlin.math.abs
import kotlin.math.roundToInt

class SettingsAccountCell(context: Context) : WCell(context), ISettingsItemCell, WThemedView {
    private var account: MAccount? = null
    private var isFirst = false
    private var isLast = false

    private val iconView: AccountIconView by lazy {
        AccountIconView(context, AccountIconView.Usage.SELECTABLE_ITEM)
    }

    private val titleLabel: WLabel by lazy {
        WLabel(context).apply {
            setStyle(16f)
            setSingleLine()
            ellipsize = TextUtils.TruncateAt.MARQUEE
            isSelected = true
            isHorizontalFadingEdgeEnabled = true
        }
    }

    private val cardThumbnail: CardThumbnailView by lazy {
        CardThumbnailView(context)
    }

    private val subtitleLabel: WLabel by lazy {
        WLabel(context).apply {
            setStyle(13f)
            setSingleLine()
            ellipsize = TextUtils.TruncateAt.MARQUEE
            isSelected = true
            isHorizontalFadingEdgeEnabled = true
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

    private val trailingContainerView: FrameLayout by lazy {
        FrameLayout(context).apply {
            id = generateViewId()
            addView(valueLabel, FrameLayout.LayoutParams(WRAP_CONTENT, WRAP_CONTENT).apply {
                gravity = Gravity.END or Gravity.CENTER_VERTICAL
            })
        }
    }

    private val separatorView = WBaseView(context)

    private val contentView = WView(context).apply {
        clipChildren = false
        clipToPadding = false
        addView(iconView, LayoutParams(51.dp, 51.dp))
        addView(
            titleLabel,
            LayoutParams(WRAP_CONTENT, WRAP_CONTENT)
        )
        addView(
            cardThumbnail,
            LayoutParams(22.dp, 14.dp)
        )
        addView(
            subtitleLabel,
            LayoutParams(WRAP_CONTENT, WRAP_CONTENT)
        )
        addView(trailingContainerView)
        addView(separatorView, LayoutParams(0, 1))

        setConstraints {
            // Icon
            toStart(iconView, 10.5f)
            toCenterY(iconView)

            // Title
            toTop(titleLabel, 11f)
            toStart(titleLabel, 72f)
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
            topToBottom(subtitleLabel, titleLabel, 1f)
            startToStart(subtitleLabel, titleLabel)
            endToStart(subtitleLabel, trailingContainerView, 4f)
            setHorizontalBias(subtitleLabel.id, 0f)
            constrainedWidth(subtitleLabel.id, true)

            // Separator
            toStart(separatorView, 72f)
            toEnd(separatorView, 16f)
            toBottom(separatorView)
        }
    }

    init {
        super.setupViews()

        addView(contentView, LayoutParams(MATCH_PARENT, 64.dp))
        setConstraints {
            toTop(contentView)
            toCenterX(contentView)
        }
    }

    override fun configure(
        item: SettingsItem,
        value: String?,
        isFirst: Boolean,
        isLast: Boolean,
        showSeparator: Boolean,
        onTap: () -> Unit
    ) {
        val account = item.accounts!!.first()
        this.account = account
        this.isFirst = isFirst
        this.isLast = isLast
        setOnClickListener {
            onTap()
        }

        iconView.config(account)
        cardThumbnail.configure(account)
        if (titleLabel.text != account.name) {
            titleLabel.text = account.name
            subtitleLabel.text =
                SpannableStringBuilder(
                    account.firstAddress?.formatStartEndAddress() ?: ""
                ).apply {
                    updateDotsTypeface()
                }
        }
        notifyBalanceChange()

        contentView.setConstraints {
            endToStart(
                titleLabel,
                trailingContainerView,
                16f + (if (cardThumbnail.isGone) 0f else 22f)
            )
        }
        if (ThemeManager.uiMode.hasRoundedCorners) {
            separatorView.visibility = if (isLast || showSeparator) INVISIBLE else VISIBLE
        } else {
            separatorView.visibility = if (isLast && ThemeManager.isDark) INVISIBLE else VISIBLE
            contentView.setConstraints {
                toStart(separatorView, if (isLast) 0f else 68f)
                toEnd(separatorView, if (isLast) 0f else 16f)
            }
        }

        ((64 + if (isLast) ViewConstants.GAP else 0).dp).let {
            if (layoutParams.height != it)
                layoutParams.height = it
        }

        setOnClickListener {
            onTap()
        }

        updateTheme()

        valueLabel.isSensitiveData = true
        valueLabel.setMaskCols(8 + abs(account.name.hashCode()) % 8)
    }

    override fun updateTheme() {
        contentView.setBackgroundColor(
            WColor.Background.color,
            if (isFirst) ViewConstants.BIG_RADIUS.dp else 0f.dp,
            if (isLast) ViewConstants.BIG_RADIUS.dp else 0f.dp
        )
        contentView.addRippleEffect(
            WColor.SecondaryBackground.color,
            if (isFirst) ViewConstants.BIG_RADIUS.dp else 0f.dp,
            if (isLast) ViewConstants.BIG_RADIUS.dp else 0f.dp
        )
        titleLabel.setTextColor(WColor.PrimaryText.color)
        subtitleLabel.setTextColor(WColor.SecondaryText.color)
        valueLabel.contentView.setTextColor(WColor.SecondaryText.color)
        separatorView.setBackgroundColor(WColor.Separator.color)
        updateAddressLabel()
    }

    private fun updateAddressLabel() {
        val addressSpannableString = SpannableStringBuilder()
        val isMultichain = account?.isMultichain == true
        if (account?.isViewOnly == true || account?.isHardware == true) {
            val drawable = ContextCompat.getDrawable(
                context,
                if (account?.isHardware == true)
                    org.mytonwallet.app_air.uicomponents.R.drawable.ic_wallet_ledger
                else
                    org.mytonwallet.app_air.uicomponents.R.drawable.ic_wallet_eye
            )!!
            drawable.mutate()
            drawable.setTint(subtitleLabel.currentTextColor)
            val width = 12.dp
            val height = 12.dp
            drawable.setBounds(0, 0, width, height)
            val imageSpan = VerticalImageSpan(drawable)
            addressSpannableString.append(" ", imageSpan, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
            addressSpannableString.append(
                " ",
                WSpacingSpan(4.dp),
                Spanned.SPAN_EXCLUSIVE_EXCLUSIVE
            )
        }
        account?.byChain?.entries?.forEachIndexed { i, addressChain ->
            if (i > 0) {
                addressSpannableString.append(", ")
            }
            val blockchain = MBlockchain.valueOf(addressChain.key)
            blockchain.symbolIcon?.let {
                val drawable = ContextCompat.getDrawable(context, it)!!
                drawable.mutate()
                drawable.setTint(subtitleLabel.currentTextColor)
                val iconWidth = 8.66f.dp.roundToInt()
                val iconHeight = 8.66f.dp.roundToInt()
                drawable.setBounds(0, 0, iconWidth, iconHeight)
                val imageSpan = VerticalImageSpan(drawable)
                addressSpannableString.append(" ", imageSpan, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
                addressSpannableString.append(
                    " ",
                    WSpacingSpan(1.66f.dp.roundToInt()),
                    Spanned.SPAN_EXCLUSIVE_EXCLUSIVE
                )
            }
            val ss =
                SpannableStringBuilder(
                    addressChain.value.address.formatStartEndAddress(
                        prefix = if (isMultichain) 0 else 4,
                        suffix = 4
                    )
                ).apply {
                    updateDotsTypeface()
                }
            addressSpannableString.append(ss)
        }
        subtitleLabel.text = addressSpannableString
    }

    fun notifyBalanceChange() {
        val accountId = account?.accountId ?: return
        val baseCurrency = WalletCore.baseCurrency
        CoroutineScope(Dispatchers.Main).launch {
            val balanceDouble = withContext(Dispatchers.Default) {
                BalanceStore.totalBalanceInBaseCurrency(accountId)
            } ?: run {
                valueLabel.contentView.text = ""
                return@launch
            }
            valueLabel.contentView.text = balanceDouble.toString(
                baseCurrency.decimalsCount,
                baseCurrency.sign,
                baseCurrency.decimalsCount,
                true,
            )
        }
    }

}
