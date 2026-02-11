package org.mytonwallet.app_air.uisettings.viewControllers.settings.cells

import android.content.Context
import android.text.TextUtils
import android.view.Gravity
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import android.widget.FrameLayout
import androidx.constraintlayout.widget.ConstraintLayout.LayoutParams.MATCH_CONSTRAINT
import androidx.core.view.isGone
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import org.mytonwallet.app_air.uicomponents.commonViews.AccountIconView
import org.mytonwallet.app_air.uicomponents.commonViews.CardThumbnailView
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.widgets.WBaseView
import org.mytonwallet.app_air.uicomponents.widgets.WCell
import org.mytonwallet.app_air.uicomponents.widgets.WFrameLayout
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.uicomponents.widgets.WMultichainAddressLabel
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.uicomponents.widgets.WView
import org.mytonwallet.app_air.uicomponents.widgets.sensitiveDataContainer.WSensitiveDataContainer
import org.mytonwallet.app_air.uicomponents.widgets.setBackgroundColor
import org.mytonwallet.app_air.uisettings.viewControllers.settings.models.SettingsItem
import org.mytonwallet.app_air.walletbasecontext.theme.ThemeManager
import org.mytonwallet.app_air.walletbasecontext.theme.ViewConstants
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletbasecontext.utils.toString
import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.models.MAccount
import org.mytonwallet.app_air.walletcore.stores.BalanceStore
import kotlin.math.abs

class SettingsAccountCell(context: Context) : WCell(context), ISettingsItemCell, WThemedView {
    private var account: MAccount? = null
    private var isFirst = false
    private var isLast = false

    companion object {
        fun heightForItem(isLast: Boolean): Int {
            return (60 + if (isLast) ViewConstants.GAP else 0).dp
        }
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

    private val trailingContainerView: WFrameLayout by lazy {
        WFrameLayout(context).apply {
            addView(valueLabel, FrameLayout.LayoutParams(WRAP_CONTENT, WRAP_CONTENT).apply {
                gravity = Gravity.END or Gravity.CENTER_VERTICAL
            })
        }
    }

    private val contentView = WView(context).apply {
        clipChildren = false
        clipToPadding = false
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
        addView(trailingContainerView)

        setConstraints {
            // Icon
            toStart(iconView, 10.5f)
            toCenterY(iconView)

            // Title
            toTop(titleLabel, 11f)
            toStart(titleLabel, 64f)
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
            topToBottom(addressLabel, titleLabel, 1f)
            startToStart(addressLabel, titleLabel)
            endToStart(addressLabel, trailingContainerView, 4f)
            setHorizontalBias(addressLabel.id, 0f)
            constrainedWidth(addressLabel.id, true)
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
        subtitle: String?,
        isFirst: Boolean,
        isLast: Boolean,
        onTap: () -> Unit
    ) {
        val account = item.account!!
        val accountChanged = this.account != account
        if (!accountChanged &&
            titleLabel.text == account.name &&
            this.isFirst == isFirst &&
            this.isLast == isLast
        ) {
            updateTheme()
            notifyBalanceChange()
            return
        }

        this.account = account
        this.isFirst = isFirst
        this.isLast = isLast
        setOnClickListener {
            onTap()
        }

        iconView.config(account)
        cardThumbnail.configure(account)
        titleLabel.text = account.name

        contentView.setConstraints {
            endToStart(
                titleLabel,
                trailingContainerView,
                16f + (if (cardThumbnail.isGone) 0f else 22f)
            )
        }

        heightForItem(isLast).let {
            if (layoutParams.height != it)
                layoutParams.height = it
        }

        setOnClickListener {
            onTap()
        }

        updateAddressLabel()
        updateTheme()
        if (accountChanged) {
            valueLabel.contentView.text = ""
        }
        notifyBalanceChange()

        valueLabel.isSensitiveData = true
        valueLabel.setMaskCols(8 + abs(account.name.hashCode()) % 8)
    }

    private var _isDarkThemeApplied: Boolean? = null
    override fun updateTheme() {
        contentView.setBackgroundColor(
            WColor.Background.color,
            if (isFirst) ViewConstants.BLOCK_RADIUS.dp else 0f.dp,
            if (isLast) ViewConstants.BLOCK_RADIUS.dp else 0f.dp
        )
        contentView.addRippleEffect(
            WColor.SecondaryBackground.color,
            if (isFirst) ViewConstants.BLOCK_RADIUS.dp else 0f.dp,
            if (isLast) ViewConstants.BLOCK_RADIUS.dp else 0f.dp
        )

        val darkModeChanged = ThemeManager.isDark != _isDarkThemeApplied
        if (!darkModeChanged)
            return
        _isDarkThemeApplied = ThemeManager.isDark

        titleLabel.setTextColor(WColor.PrimaryText.color)
        addressLabel.setTextColor(WColor.SecondaryText.color)
        valueLabel.contentView.setTextColor(WColor.SecondaryText.color)
    }

    private fun updateAddressLabel() {
        val style = when (account?.accountType) {
            MAccount.AccountType.VIEW -> WMultichainAddressLabel.cardRowWalletViewStyle
            MAccount.AccountType.HARDWARE -> WMultichainAddressLabel.cardRowWalletHardwareStyle
            else -> WMultichainAddressLabel.cardRowWalletStyle
        }
        addressLabel.displayAddresses(account, style)
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
