package org.mytonwallet.app_air.uisettings.viewControllers.assetsAndActivities.cells

import android.annotation.SuppressLint
import android.view.Gravity
import android.view.View
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import androidx.recyclerview.widget.RecyclerView
import org.mytonwallet.app_air.icons.R
import org.mytonwallet.app_air.uicomponents.base.WNavigationController
import org.mytonwallet.app_air.uicomponents.base.WViewController
import org.mytonwallet.app_air.uicomponents.commonViews.KeyValueRowView
import org.mytonwallet.app_air.uicomponents.commonViews.cells.HeaderCell
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.helpers.adaptiveFontSize
import org.mytonwallet.app_air.uicomponents.viewControllers.selector.TokenSelectorHelper
import org.mytonwallet.app_air.uicomponents.widgets.WCell
import org.mytonwallet.app_air.uicomponents.widgets.WEditableItemView
import org.mytonwallet.app_air.uicomponents.widgets.WImageView
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.uicomponents.widgets.WSwitch
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.uicomponents.widgets.WView
import org.mytonwallet.app_air.uicomponents.widgets.menu.WMenuPopup
import org.mytonwallet.app_air.uicomponents.widgets.menu.WMenuPopup.BackgroundStyle
import org.mytonwallet.app_air.uicomponents.widgets.setBackgroundColor
import org.mytonwallet.app_air.uisettings.viewControllers.assetsAndActivities.ChainDisplaySettingsVC
import org.mytonwallet.app_air.uisettings.viewControllers.assetsAndActivities.views.ChainIconStackView
import org.mytonwallet.app_air.uisettings.viewControllers.baseCurrency.BaseCurrencyVC
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.logger.Logger
import org.mytonwallet.app_air.walletbasecontext.theme.ViewConstants
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletbasecontext.utils.getDrawableCompat
import org.mytonwallet.app_air.walletbasecontext.utils.withLocalizedNumbers
import org.mytonwallet.app_air.walletcontext.WalletContextManager
import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage
import org.mytonwallet.app_air.walletcontext.models.MTokenChangeThreshold
import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.WalletEvent
import org.mytonwallet.app_air.walletcore.models.blockchain.MBlockchain
import org.mytonwallet.app_air.walletcore.stores.AccountStore
import org.mytonwallet.app_air.walletcore.stores.NftStore
import org.mytonwallet.app_air.walletcore.stores.TokenStore

@SuppressLint("ViewConstructor")
class AssetsAndActivitiesHeaderCell(
    navigationController: WNavigationController,
    recyclerView: RecyclerView
) : WCell(recyclerView.context, LayoutParams(MATCH_PARENT, WRAP_CONTENT)),
    WThemedView {

    private fun hintLabel(text: String): WLabel = WLabel(context).apply {
        setStyle(13f)
        setLineHeight(18f)
        this.text = text
        gravity = Gravity.START
    }

    private fun switchRow(label: WLabel, switchView: WSwitch): WView {
        val v = WView(context)
        v.addView(label)
        v.addView(switchView)
        v.setConstraints {
            toStart(label, 20f)
            toCenterY(label)
            toEnd(switchView, 20f)
            toCenterY(switchView)
        }
        v.setOnClickListener {
            switchView.isChecked = !switchView.isChecked
        }
        return v
    }

    private fun valueRow(label: WLabel, valueLabel: WLabel, onClick: () -> Unit): WView {
        val v = WView(context)
        v.addView(label)
        v.addView(valueLabel)
        v.setConstraints {
            toStart(label, 20f)
            toCenterY(label)
            toEnd(valueLabel, 20f)
            toCenterY(valueLabel)
        }
        v.setOnClickListener { onClick() }
        return v
    }

    private val baseCurrencyLabel: WLabel by lazy {
        val lbl = WLabel(context)
        lbl.setStyle(adaptiveFontSize())
        lbl.text =
            LocaleController.getString("Base Currency")
        lbl
    }

    private val currentBaseCurrencyLabel: WLabel by lazy {
        val lbl = WLabel(context)
        lbl.setStyle(adaptiveFontSize())
        lbl
    }

    private val baseCurrencyView: WView by lazy {
        valueRow(baseCurrencyLabel, currentBaseCurrencyLabel) {
            navigationController.push(BaseCurrencyVC(context))
        }
    }

    private val hideTinyTransfersLabel: WLabel by lazy {
        val lbl = WLabel(context)
        lbl.setStyle(adaptiveFontSize())
        lbl.text =
            LocaleController.getString("Hide Tiny Transfers")
        lbl
    }

    private val hideTinyTransfersSwitch: WSwitch by lazy {
        val switchView = WSwitch(context)
        switchView.isChecked = WGlobalStorage.getAreTinyTransfersHidden()
        switchView.setOnCheckedChangeListener { _, isChecked ->
            WGlobalStorage.setAreTinyTransfersHidden(isChecked)
            WalletCore.notifyEvent(WalletEvent.HideTinyTransfersChanged)
        }
        switchView
    }

    private val hideTinyTransfersRow: WView by lazy {
        switchRow(hideTinyTransfersLabel, hideTinyTransfersSwitch)
    }

    private val hideTinyTransfersHintLabel: WLabel by lazy {
        hintLabel(
            LocaleController.getString(
                "Don’t show transactions of less than \$0.01. Such small transactions are often used for spam and scam."
            )
        )
    }

    private val hideUnverifiedNftsLabel: WLabel by lazy {
        val lbl = WLabel(context)
        lbl.setStyle(adaptiveFontSize())
        lbl.text = LocaleController.getString("Hide Unverified NFTs")
        lbl
    }

    private val hideUnverifiedNftsSwitch: WSwitch by lazy {
        val switchView = WSwitch(context)
        switchView.isChecked = WGlobalStorage.getAreUnverifiedNftsHidden()
        switchView.setOnCheckedChangeListener { _, isChecked ->
            WGlobalStorage.setAreUnverifiedNftsHidden(isChecked)
            WalletCore.notifyEvent(WalletEvent.NftsUpdated)
        }
        switchView
    }

    private val hideUnverifiedNftsRow: WView by lazy {
        switchRow(hideUnverifiedNftsLabel, hideUnverifiedNftsSwitch)
    }

    private val hiddenNftsLabel: WLabel by lazy {
        val lbl = WLabel(context)
        lbl.setStyle(adaptiveFontSize())
        lbl.text = LocaleController.getString("Hidden NFTs")
        lbl
    }

    private val hiddenNftsCountLabel: WLabel by lazy {
        val lbl = WLabel(context)
        lbl.setStyle(adaptiveFontSize())
        lbl
    }

    private val hiddenNftsRow: WView by lazy {
        valueRow(hiddenNftsLabel, hiddenNftsCountLabel) {
            val accountId = AccountStore.activeAccountId ?: return@valueRow
            (
                WalletContextManager.delegate?.get()
                    ?.getHiddenNftsVC(accountId) as? WViewController
                )?.let {
                navigationController.push(it)
            }
        }
    }

    private val showBlockchainsSection = AccountStore.activeAccount?.isMultichain == true

    private val blockchainsHeaderCell: HeaderCell by lazy {
        HeaderCell(context).apply {
            configure(
                LocaleController.getString("Blockchains"),
                titleColor = WColor.Tint,
                topRounding = HeaderCell.TopRounding.NORMAL
            )
        }
    }

    private val chainIconStackView: ChainIconStackView by lazy {
        ChainIconStackView(context)
    }

    private val blockchainsChevronView: WImageView by lazy {
        val iv = WImageView(context)
        iv.setImageDrawable(
            context.getDrawableCompat(R.drawable.ic_arrow_right_24)?.apply {
                setTint(WColor.SecondaryText.color)
            }
        )
        iv
    }

    private val blockchainsView: WView by lazy {
        val v = WView(context)
        v.addView(chainIconStackView, LayoutParams(0, ChainIconStackView.ICON_SIZE))
        v.addView(blockchainsChevronView, LayoutParams(24.dp, 24.dp))
        v.setConstraints {
            toStart(chainIconStackView, 16f)
            toCenterY(chainIconStackView)
            endToStart(chainIconStackView, blockchainsChevronView, 12f)
            toEnd(blockchainsChevronView, 16f)
            toCenterY(blockchainsChevronView)
        }
        v.setOnClickListener {
            navigationController.push(ChainDisplaySettingsVC(context))
        }
        v
    }

    private val chainBadgesLabel: WLabel by lazy {
        val lbl = WLabel(context)
        lbl.setStyle(adaptiveFontSize())
        lbl.text = LocaleController.getString("Blockchain Badges")
        lbl
    }

    private val chainBadgesSwitch: WSwitch by lazy {
        val switchView = WSwitch(context)
        switchView.isChecked = WGlobalStorage.getAreChainBadgesShown()
        switchView.setOnCheckedChangeListener { _, isChecked ->
            Logger.d(Logger.LogTag.SETTINGS, "chainBadgesRow: isChecked=$isChecked")
            WGlobalStorage.setAreChainBadgesShown(isChecked)
            WalletCore.notifyEvent(WalletEvent.TokensChanged)
        }
        switchView
    }

    private val chainBadgesRow: WView by lazy {
        switchRow(chainBadgesLabel, chainBadgesSwitch)
    }

    private val chainBadgesHintLabel: WLabel by lazy {
        hintLabel(LocaleController.getString("\$settings_blockchain_badges_description"))
    }

    private val hideTokensWithNoCostLabel: WLabel by lazy {
        val lbl = WLabel(context)
        lbl.setStyle(adaptiveFontSize())
        lbl.text =
            LocaleController.getString("Hide Tokens With No Cost")
        lbl
    }

    private val hideTokensWithNoCostSwitch: WSwitch by lazy {
        val switchView = WSwitch(context)
        switchView.isChecked = WGlobalStorage.getAreNoCostTokensHidden()
        switchView.setOnCheckedChangeListener { _, isChecked ->
            onHideNoCostTokensChanged(isChecked)
        }
        switchView
    }

    private val hideTokensWithNoCostRow: WView by lazy {
        switchRow(hideTokensWithNoCostLabel, hideTokensWithNoCostSwitch)
    }

    private val hideTokensWithNoCostHintLabel: WLabel by lazy {
        hintLabel(
            LocaleController.getString(
                "Don’t show tokens on your account with value less than \$0.01. You can also selectively enable and disable particular tokens using the list below."
            )
        )
    }

    private val showLocalizedTokenNamesRow =
        TokenStore.tokens.values.any { it.localizedName != null }

    private val localizedTokenNamesLabel: WLabel by lazy {
        val lbl = WLabel(context)
        lbl.setStyle(adaptiveFontSize())
        lbl.text =
            LocaleController.getString("Localized Token Names")
        lbl
    }

    private val localizedTokenNamesSwitch: WSwitch by lazy {
        val switchView = WSwitch(context)
        switchView.isChecked = WGlobalStorage.getUseLocalizedTokenNames()
        switchView.setOnCheckedChangeListener { _, isChecked ->
            WGlobalStorage.setUseLocalizedTokenNames(isChecked)
            WalletCore.notifyEvent(WalletEvent.TokensChanged)
        }
        switchView
    }

    private val localizedTokenNamesRow: WView by lazy {
        switchRow(localizedTokenNamesLabel, localizedTokenNamesSwitch)
    }

    private val changeThresholdDropdownView: WEditableItemView by lazy {
        WEditableItemView(context).apply {
            id = View.generateViewId()
            drawable = context.getDrawableCompat(R.drawable.ic_arrows_18)
            setText(WGlobalStorage.getTokenChangeThreshold().displayName)
        }
    }

    private val changeThresholdRow: KeyValueRowView by lazy {
        KeyValueRowView(
            context,
            LocaleController.getString("\$settings_token_change_threshold"),
            "",
            KeyValueRowView.Mode.PRIMARY,
            isLast = true
        ).apply {
            setValueView(changeThresholdDropdownView)
            setOnClickListener {
                WMenuPopup.present(
                    changeThresholdDropdownView,
                    MTokenChangeThreshold.entries.map { threshold ->
                        WMenuPopup.Item(
                            null,
                            threshold.displayName,
                            false
                        ) {
                            if (WGlobalStorage.getTokenChangeThreshold() != threshold) {
                                Logger.d(
                                    Logger.LogTag.SETTINGS,
                                    "changeThresholdRow: threshold=${threshold.value}"
                                )
                                WGlobalStorage.setTokenChangeThreshold(threshold)
                                changeThresholdDropdownView.setText(threshold.displayName)
                                WalletCore.notifyEvent(WalletEvent.TokensChanged)
                            }
                        }
                    },
                    popupWidth = WRAP_CONTENT,
                    positioning = WMenuPopup.Positioning.BELOW,
                    windowBackgroundStyle = BackgroundStyle.Cutout.fromView(
                        changeThresholdDropdownView,
                        roundRadius = 18f.dp
                    )
                )
            }
        }
    }

    private val changeThresholdHintLabel: WLabel by lazy {
        hintLabel(LocaleController.getString("\$settings_token_change_threshold_description"))
    }

    private val tokensOnHomeScreenLabel = HeaderCell(context).apply {
        configure(
            LocaleController.getString("Tokens on Home Screen"),
            titleColor = WColor.Tint,
            topRounding = HeaderCell.TopRounding.NORMAL
        )
    }

    private val addIcon: WImageView by lazy {
        val iv = WImageView(context)
        iv.setImageDrawable(
            context.getDrawableCompat(R.drawable.ic_plus)?.apply {
                setTint(WColor.Tint.color)
            }
        )
        iv
    }

    private val addTokenLabel: WLabel by lazy {
        val lbl = WLabel(context)
        lbl.setStyle(14f, WFont.Medium)
        lbl.text =
            LocaleController.getString("Add Token")
        lbl
    }

    private val addTokenView: WView by lazy {
        val v = WView(context)
        v.addView(addIcon, LayoutParams(24.dp, 24.dp))
        v.addView(addTokenLabel)
        v.setConstraints {
            toCenterY(addTokenLabel)
            toStart(addTokenLabel, 68f)
            toCenterY(addIcon)
            toStart(addIcon, 20f)
        }
        v.setOnClickListener {
            val activeAccount = AccountStore.activeAccount ?: return@setOnClickListener
            navigationController.push(
                TokenSelectorHelper.buildAddTokenSelector(
                    context = context,
                    account = activeAccount
                )
            )
        }
        v
    }

    override fun setupViews() {
        super.setupViews()

        val gap = ViewConstants.GAP.toFloat()
        val hintGap = (ViewConstants.GAP + 4).toFloat()

        addView(baseCurrencyView, LayoutParams(MATCH_PARENT, 50.dp))
        addView(hideTinyTransfersRow, LayoutParams(MATCH_PARENT, 50.dp))
        addView(hideTinyTransfersHintLabel, LayoutParams(MATCH_PARENT, WRAP_CONTENT))
        addView(hideUnverifiedNftsRow, LayoutParams(MATCH_PARENT, 50.dp))
        addView(hiddenNftsRow, LayoutParams(MATCH_PARENT, 50.dp))
        if (showBlockchainsSection) {
            addView(blockchainsHeaderCell, LayoutParams(MATCH_PARENT, 48.dp))
            addView(blockchainsView, LayoutParams(MATCH_PARENT, 64.dp))
            addView(chainBadgesRow, LayoutParams(MATCH_PARENT, 50.dp))
            addView(chainBadgesHintLabel, LayoutParams(MATCH_PARENT, WRAP_CONTENT))
        }
        addView(hideTokensWithNoCostRow, LayoutParams(MATCH_PARENT, 50.dp))
        if (showLocalizedTokenNamesRow) {
            addView(localizedTokenNamesRow, LayoutParams(MATCH_PARENT, 50.dp))
        }
        addView(hideTokensWithNoCostHintLabel, LayoutParams(MATCH_PARENT, WRAP_CONTENT))
        addView(changeThresholdRow, LayoutParams(MATCH_PARENT, 50.dp))
        addView(changeThresholdHintLabel, LayoutParams(MATCH_PARENT, WRAP_CONTENT))
        addView(tokensOnHomeScreenLabel, LayoutParams(MATCH_PARENT, 48.dp))
        addView(addTokenView, LayoutParams(MATCH_PARENT, 50.dp))

        setConstraints {
            toTop(baseCurrencyView)
            toCenterX(baseCurrencyView)
            topToBottom(hideTinyTransfersRow, baseCurrencyView)
            toCenterX(hideTinyTransfersRow)
            topToBottom(hideTinyTransfersHintLabel, hideTinyTransfersRow, 8f)
            toCenterX(hideTinyTransfersHintLabel, 16f)

            topToBottom(hideUnverifiedNftsRow, hideTinyTransfersHintLabel, hintGap)
            toCenterX(hideUnverifiedNftsRow)
            topToBottom(hiddenNftsRow, hideUnverifiedNftsRow)
            toCenterX(hiddenNftsRow)

            if (showBlockchainsSection) {
                topToBottom(blockchainsHeaderCell, hiddenNftsRow, gap)
                toCenterX(blockchainsHeaderCell)
                topToBottom(blockchainsView, blockchainsHeaderCell)
                toCenterX(blockchainsView)
                topToBottom(chainBadgesRow, blockchainsView)
                toCenterX(chainBadgesRow)
                topToBottom(chainBadgesHintLabel, chainBadgesRow, 8f)
                toCenterX(chainBadgesHintLabel, 16f)
                topToBottom(hideTokensWithNoCostRow, chainBadgesHintLabel, hintGap)
            } else {
                topToBottom(hideTokensWithNoCostRow, hiddenNftsRow, gap)
            }
            toCenterX(hideTokensWithNoCostRow)
            if (showLocalizedTokenNamesRow) {
                topToBottom(localizedTokenNamesRow, hideTokensWithNoCostRow)
                toCenterX(localizedTokenNamesRow)
            }
            topToBottom(
                hideTokensWithNoCostHintLabel,
                if (showLocalizedTokenNamesRow) localizedTokenNamesRow else hideTokensWithNoCostRow,
                8f
            )
            toCenterX(hideTokensWithNoCostHintLabel, 16f)

            topToBottom(changeThresholdRow, hideTokensWithNoCostHintLabel, hintGap)
            toCenterX(changeThresholdRow)
            topToBottom(changeThresholdHintLabel, changeThresholdRow, 8f)
            toCenterX(changeThresholdHintLabel, 16f)

            topToBottom(tokensOnHomeScreenLabel, changeThresholdHintLabel, hintGap)
            toCenterX(tokensOnHomeScreenLabel)
            topToBottom(addTokenView, tokensOnHomeScreenLabel)
            toCenterX(addTokenView)
            toBottom(addTokenView)
        }

        updateTheme()
    }

    override fun updateTheme() {
        val blockRadius = ViewConstants.BLOCK_RADIUS.dp

        baseCurrencyView.setBackgroundColor(
            WColor.Background.color,
            ViewConstants.TOOLBAR_RADIUS.dp,
            0f
        )
        baseCurrencyView.addRippleEffect(WColor.SecondaryBackground.color)
        baseCurrencyLabel.setTextColor(WColor.PrimaryText.color)
        currentBaseCurrencyLabel.setTextColor(WColor.SecondaryText.color)

        hideTinyTransfersRow.setBackgroundColor(WColor.Background.color, 0f, blockRadius)
        hideTinyTransfersRow.addRippleEffect(WColor.SecondaryBackground.color)
        hideTinyTransfersLabel.setTextColor(WColor.PrimaryText.color)
        hideTinyTransfersHintLabel.setTextColor(WColor.SecondaryText.color)

        hideUnverifiedNftsRow.setBackgroundColor(WColor.Background.color, blockRadius, 0f)
        hideUnverifiedNftsRow.addRippleEffect(WColor.SecondaryBackground.color)
        hideUnverifiedNftsLabel.setTextColor(WColor.PrimaryText.color)
        hiddenNftsRow.setBackgroundColor(WColor.Background.color, 0f, blockRadius)
        hiddenNftsRow.addRippleEffect(WColor.SecondaryBackground.color)
        hiddenNftsLabel.setTextColor(WColor.PrimaryText.color)
        hiddenNftsCountLabel.setTextColor(WColor.SecondaryText.color)

        if (showBlockchainsSection) {
            blockchainsHeaderCell.updateTheme()
            blockchainsView.setBackgroundColor(WColor.Background.color, 0f, 0f)
            blockchainsView.addRippleEffect(WColor.SecondaryBackground.color)
            chainBadgesRow.setBackgroundColor(WColor.Background.color, 0f, blockRadius)
            chainBadgesRow.addRippleEffect(WColor.SecondaryBackground.color)
            chainBadgesLabel.setTextColor(WColor.PrimaryText.color)
            chainBadgesHintLabel.setTextColor(WColor.SecondaryText.color)
        }

        hideTokensWithNoCostRow.setBackgroundColor(
            WColor.Background.color,
            blockRadius,
            if (showLocalizedTokenNamesRow) 0f else blockRadius
        )
        hideTokensWithNoCostRow.addRippleEffect(WColor.SecondaryBackground.color)
        hideTokensWithNoCostLabel.setTextColor(WColor.PrimaryText.color)
        if (showLocalizedTokenNamesRow) {
            localizedTokenNamesRow.setBackgroundColor(WColor.Background.color, 0f, blockRadius)
            localizedTokenNamesRow.addRippleEffect(WColor.SecondaryBackground.color)
            localizedTokenNamesLabel.setTextColor(WColor.PrimaryText.color)
        }
        hideTokensWithNoCostHintLabel.setTextColor(WColor.SecondaryText.color)

        changeThresholdRow.setTopRadius(blockRadius)
        changeThresholdRow.setBackgroundColor(WColor.Background.color)
        changeThresholdHintLabel.setTextColor(WColor.SecondaryText.color)

        updateAddTokenViewRadius()
        addTokenView.addRippleEffect(WColor.SecondaryBackground.color)
        addTokenLabel.setTextColor(WColor.Tint.color)
    }

    private fun updateAddTokenViewRadius() {
        val bottomRadius = if (hasTokens) 0f else ViewConstants.BLOCK_RADIUS.dp
        addTokenView.setBackgroundColor(WColor.Background.color, 0f, bottomRadius)
    }

    private var hasTokens: Boolean = true
    private lateinit var onHideNoCostTokensChanged: (hidden: Boolean) -> Unit
    fun configure(hasTokens: Boolean, onHideNoCostTokensChanged: (hidden: Boolean) -> Unit) {
        this.hasTokens = hasTokens
        this.onHideNoCostTokensChanged = onHideNoCostTokensChanged
        currentBaseCurrencyLabel.text = WalletCore.baseCurrency.currencySymbol
        val account = AccountStore.activeAccount
        val hiddenNftsCount = account?.let { NftStore.getHiddenNftsCount(it.accountId) } ?: 0
        hiddenNftsCountLabel.text =
            if (hiddenNftsCount > 0) hiddenNftsCount.toString().withLocalizedNumbers else ""
        if (showBlockchainsSection) {
            chainIconStackView.configure(
                account?.displayedChains()?.mapNotNull { entry ->
                    MBlockchain.valueOfOrNull(entry.key)
                } ?: emptyList()
            )
        }
        updateAddTokenViewRadius()
    }
}
