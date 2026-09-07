@file:Suppress("ktlint:standard:backing-property-naming")

package org.mytonwallet.app_air.uisettings.viewControllers.settings.cells

import android.content.Context
import android.text.Layout
import android.text.TextUtils
import android.view.Gravity
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import android.widget.FrameLayout
import androidx.core.view.isGone
import kotlin.math.abs
import kotlin.math.roundToInt
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import org.mytonwallet.app_air.uicomponents.commonViews.AccountIconView
import org.mytonwallet.app_air.uicomponents.commonViews.CardThumbnailView
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.helpers.SpannableHelpers
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.helpers.adaptiveFontSize
import org.mytonwallet.app_air.uicomponents.widgets.WCell
import org.mytonwallet.app_air.uicomponents.widgets.WFrameLayout
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
import org.mytonwallet.app_air.walletbasecontext.utils.toString
import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.models.MAccount
import org.mytonwallet.app_air.walletcore.stores.BalanceStore

class SettingsAccountCell(context: Context) :
    WCell(context),
    ISettingsItemCell,
    WThemedView {
    private var account: MAccount? = null
    private var accountAvatarUrl: String? = null
    private var isFirst = false
    private var isLast = false

    companion object {
        private const val BADGE_WIDTH = 12
        private const val BADGE_SPACING = 4

        fun heightForItem(isLast: Boolean): Int = (50 + if (isLast) ViewConstants.GAP else 0).dp
    }

    private val iconView: AccountIconView by lazy {
        AccountIconView(context, AccountIconView.Usage.SelectableItem(14f.dp))
    }

    private val titleLabel: WLabel by lazy {
        WLabel(context).apply {
            setStyle(adaptiveFontSize(), WFont.Medium)
            setSingleLine()
            ellipsize = TextUtils.TruncateAt.MARQUEE
            isSelected = true
            isHorizontalFadingEdgeEnabled = true
            useCustomEmoji = true
        }
    }

    private val cardThumbnail: CardThumbnailView by lazy {
        CardThumbnailView(context)
    }

    private val badgesLabel: WLabel by lazy {
        WLabel(context).apply {
            setStyle(12f)
            setSingleLine()
        }
    }

    private val valueLabel: WSensitiveDataContainer<WLabel> by lazy {
        val lbl = WLabel(context)
        lbl.setStyle(adaptiveFontSize())
        lbl.gravity = Gravity.LEFT
        lbl.layoutDirection = LAYOUT_DIRECTION_LTR
        WSensitiveDataContainer(
            lbl,
            WSensitiveDataContainer.MaskConfig(0, 2, Gravity.END or Gravity.CENTER_VERTICAL)
        )
    }

    private val trailingContainerView: WFrameLayout by lazy {
        WFrameLayout(context).apply {
            addView(
                valueLabel,
                FrameLayout.LayoutParams(WRAP_CONTENT, WRAP_CONTENT).apply {
                    gravity = Gravity.END or Gravity.CENTER_VERTICAL
                }
            )
        }
    }

    private val contentView = WView(context).apply {
        clipChildren = false
        clipToPadding = false
        addView(iconView, LayoutParams(39.dp, 39.dp))
        addView(
            titleLabel,
            LayoutParams(WRAP_CONTENT, WRAP_CONTENT)
        )
        addView(
            cardThumbnail,
            LayoutParams(22.dp, 14.dp)
        )
        addView(
            badgesLabel,
            LayoutParams(WRAP_CONTENT, WRAP_CONTENT)
        )
        addView(trailingContainerView)

        setConstraints {
            // Icon
            toStart(iconView, 12f)
            toCenterY(iconView)

            // Title
            toCenterY(titleLabel)
            toStart(titleLabel, 64f)
            setHorizontalBias(titleLabel.id, 0f)
            constrainedWidth(titleLabel.id, true)

            // Card-Thumbnail
            centerYToCenterY(cardThumbnail, titleLabel)
            startToEnd(cardThumbnail, titleLabel, 6f)
            setHorizontalBias(cardThumbnail.id, 0f)

            // Badges
            centerYToCenterY(badgesLabel, titleLabel)
            startToEnd(badgesLabel, cardThumbnail, 8f)
            setHorizontalBias(badgesLabel.id, 0f)

            // Value
            toCenterY(trailingContainerView)
            toEnd(trailingContainerView, 20f)
            setHorizontalBias(trailingContainerView.id, 1f)
            endToStartPx(cardThumbnail, trailingContainerView, 4.dp)
            endToStartPx(badgesLabel, trailingContainerView, 4.dp)
        }
    }

    init {
        super.setupViews()

        addView(contentView, LayoutParams(MATCH_PARENT, 50.dp))
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
        isEnabled: Boolean,
        onTap: () -> Unit
    ) {
        val account = item.account!!
        val accountChanged = this.account != account
        val avatarUrlChanged = accountAvatarUrl != account.telegramAvatarUrl
        if (!accountChanged &&
            !avatarUrlChanged &&
            titleLabel.text == account.name &&
            this.isFirst == isFirst &&
            this.isLast == isLast
        ) {
            updateTheme()
            notifyBalanceChange()
            return
        }

        this.account = account
        accountAvatarUrl = account.telegramAvatarUrl
        this.isFirst = isFirst
        this.isLast = isLast

        iconView.config(account)
        cardThumbnail.configure(account)
        titleLabel.text = account.name
        updateBadges()

        val badgesWidth = if (badgesLabel.text.isNullOrEmpty()) {
            0
        } else {
            6.dp + Layout.getDesiredWidth(badgesLabel.text, badgesLabel.paint).roundToInt()
        }
        contentView.setConstraints {
            endToStartPx(
                titleLabel,
                trailingContainerView,
                16.dp + (if (cardThumbnail.isGone) 0 else 28.dp) + badgesWidth
            )
        }

        heightForItem(isLast).let {
            if (layoutParams.height != it) layoutParams.height = it
        }

        setContentAlpha(if (isEnabled) 1f else 0.4f)
        this.isEnabled = isEnabled
        isClickable = isEnabled

        setOnClickListener { onTap() }

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
        if (!darkModeChanged) return
        _isDarkThemeApplied = ThemeManager.isDark

        titleLabel.setTextColor(WColor.PrimaryText.color)
        valueLabel.contentView.setTextColor(WColor.SecondaryText.color)
        updateBadges()
    }

    private fun setContentAlpha(alpha: Float) {
        iconView.alpha = alpha
        titleLabel.alpha = alpha
        cardThumbnail.alpha = alpha
        badgesLabel.alpha = alpha
        trailingContainerView.alpha = alpha
    }

    private fun updateBadges() {
        val account = account ?: return
        badgesLabel.text = SpannableHelpers.accountBadgesSpan(
            context,
            account,
            BADGE_WIDTH.dp,
            BADGE_SPACING.dp,
            WColor.SecondaryText.color
        )
    }

    fun notifyBalanceChange() {
        val accountId = account?.accountId ?: return
        val baseCurrency = WalletCore.baseCurrency
        CoroutineScope(Dispatchers.Main).launch {
            val balanceDouble = withContext(Dispatchers.Default) {
                BalanceStore.totalBalanceInBaseCurrency(accountId)
            } ?: run {
                if (valueLabel.contentView.text != "") valueLabel.contentView.text = ""
                return@launch
            }
            val newValue = balanceDouble.toString(
                baseCurrency.decimalsCount,
                baseCurrency.sign,
                baseCurrency.decimalsCount,
                true
            )
            if (valueLabel.contentView.text != newValue) valueLabel.contentView.text = newValue
        }
    }
}
