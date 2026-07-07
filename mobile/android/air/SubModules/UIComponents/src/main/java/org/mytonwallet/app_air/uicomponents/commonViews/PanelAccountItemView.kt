package org.mytonwallet.app_air.uicomponents.commonViews

import android.annotation.SuppressLint
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
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.widgets.WCell
import org.mytonwallet.app_air.uicomponents.widgets.WFrameLayout
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.uicomponents.widgets.WMultichainAddressLabel
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.uicomponents.widgets.WView
import org.mytonwallet.app_air.uicomponents.widgets.sensitiveDataContainer.WSensitiveDataContainer
import org.mytonwallet.app_air.uicomponents.drawable.WRippleDrawable
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletbasecontext.utils.toString
import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.models.MAccount
import org.mytonwallet.app_air.walletcore.stores.BalanceStore
import kotlin.math.abs

@SuppressLint("ViewConstructor")
class PanelAccountItemView(context: Context) :
    WCell(context, LayoutParams(MATCH_PARENT, WRAP_CONTENT)), WThemedView {

    companion object {
        const val HEIGHT_DP = 60
        private const val ICON_SIZE_DP = 50
    }

    private var account: MAccount? = null

    private val iconView = AccountIconView(context, AccountIconView.Usage.SelectableItem(16f.dp))

    private val titleLabel = WLabel(context).apply {
        setStyle(16f, WFont.Medium)
        setSingleLine()
        ellipsize = TextUtils.TruncateAt.END
        useCustomEmoji = true
    }

    private val addressLabel = WMultichainAddressLabel(context).apply {
        setStyle(13f)
        applyFontOffsetFix = true
    }

    private val cardThumbnail = CardThumbnailView(context)

    private val valueLabel: WSensitiveDataContainer<WLabel> by lazy {
        val lbl = WLabel(context).apply {
            setStyle(16f)
            gravity = Gravity.LEFT
            layoutDirection = LAYOUT_DIRECTION_LTR
        }
        WSensitiveDataContainer(
            lbl,
            WSensitiveDataContainer.MaskConfig(0, 2, Gravity.END or Gravity.CENTER_VERTICAL)
        )
    }

    private val trailingContainerView = WFrameLayout(context).apply {
        addView(valueLabel, FrameLayout.LayoutParams(WRAP_CONTENT, WRAP_CONTENT).apply {
            gravity = Gravity.END or Gravity.CENTER_VERTICAL
        })
    }

    private val rippleDrawable = WRippleDrawable.create(16f.dp).apply {
        rippleColor = WColor.BackgroundRipple.color
    }

    private val contentView = WView(context).apply {
        background = rippleDrawable
        clipChildren = false
        clipToPadding = false
        addView(iconView, LayoutParams(ICON_SIZE_DP.dp, ICON_SIZE_DP.dp))
        addView(titleLabel, LayoutParams(WRAP_CONTENT, WRAP_CONTENT))
        addView(cardThumbnail, LayoutParams(22.dp, 14.dp))
        addView(addressLabel, LayoutParams(MATCH_CONSTRAINT, WRAP_CONTENT))
        addView(trailingContainerView)

        setConstraints {
            toStart(iconView, 8.5f)
            toCenterY(iconView)

            toTop(titleLabel, 9f)
            startToEnd(titleLabel, iconView, 10.5f)
            setHorizontalBias(titleLabel.id, 0f)
            constrainedWidth(titleLabel.id, true)

            centerYToCenterY(cardThumbnail, titleLabel)
            startToEnd(cardThumbnail, titleLabel, 6f)
            endToStartPx(cardThumbnail, trailingContainerView, 8.dp)
            setHorizontalBias(cardThumbnail.id, 0f)

            toCenterY(trailingContainerView)
            toEnd(trailingContainerView, 14f)
            setHorizontalBias(trailingContainerView.id, 1f)

            topToBottom(addressLabel, titleLabel, 1f)
            startToStart(addressLabel, titleLabel)
            endToStart(addressLabel, trailingContainerView, 4f)
            setHorizontalBias(addressLabel.id, 0f)
            constrainedWidth(addressLabel.id, true)
        }
    }

    init {
        addView(contentView, LayoutParams(MATCH_PARENT, HEIGHT_DP.dp))
        clipToPadding = false
        setConstraints {
            toTop(contentView)
            toStart(contentView)
            toEnd(contentView)
        }
    }

    fun configure(
        account: MAccount,
        isFirst: Boolean,
        onSelect: () -> Unit,
        onLongPress: (() -> Unit)? = null
    ) {
        setPadding(0, if (isFirst) 12.dp else 0, 0, 0)

        val accountChanged = this.account != account
        this.account = account

        titleLabel.text = account.name

        if (accountChanged) {
            valueLabel.contentView.text = ""
            updateAddressLabel()
            valueLabel.isSensitiveData = true
            valueLabel.setMaskCols(8 + abs(account.name.hashCode()) % 8)
        }

        // AccountIconView draws the Tint selected-border itself when accountId == activeAccountId.
        // Always re-config (not only on accountChanged) so the border updates when the active
        // account changes while this row's account stays the same.
        iconView.config(account)
        cardThumbnail.configure(account)

        contentView.setConstraints {
            endToStart(
                titleLabel,
                trailingContainerView,
                8f + (if (cardThumbnail.isGone) 0f else 22f)
            )
        }

        setOnClickListener { onSelect() }
        if (onLongPress != null) {
            setOnLongClickListener {
                onLongPress()
                true
            }
        } else {
            setOnLongClickListener(null)
            isLongClickable = false
        }
        updateTheme()
        notifyBalanceChange()
    }

    fun refreshSelection() {
        account?.let { iconView.config(it) }
    }

    private fun updateAddressLabel() {
        val style = when (account?.accountType) {
            MAccount.AccountType.VIEW -> WMultichainAddressLabel.cardRowWalletViewStyle
            MAccount.AccountType.HARDWARE -> WMultichainAddressLabel.cardRowWalletHardwareStyle
            else -> WMultichainAddressLabel.cardRowWalletStyle
        }
        addressLabel.displayAddresses(account, style)
    }

    override fun updateTheme() {
        rippleDrawable.rippleColor = WColor.BackgroundRipple.color
        titleLabel.setTextColor(WColor.PrimaryText.color)
        addressLabel.setTextColor(WColor.SecondaryText.color)
        valueLabel.contentView.setTextColor(WColor.SecondaryText.color)
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
