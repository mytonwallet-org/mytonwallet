package org.mytonwallet.app_air.uisettings.viewControllers.assetsAndActivities.cells

import android.annotation.SuppressLint
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import androidx.recyclerview.widget.RecyclerView
import org.mytonwallet.app_air.icons.R
import org.mytonwallet.app_air.uicomponents.base.WNavigationController
import org.mytonwallet.app_air.uicomponents.commonViews.cells.HeaderCell
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.helpers.adaptiveFontSize
import org.mytonwallet.app_air.uicomponents.viewControllers.selector.TokenSelectorHelper
import org.mytonwallet.app_air.uicomponents.widgets.WCell
import org.mytonwallet.app_air.uicomponents.widgets.WImageView
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.uicomponents.widgets.WSwitch
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.uicomponents.widgets.WView
import org.mytonwallet.app_air.uicomponents.widgets.setBackgroundColor
import org.mytonwallet.app_air.uisettings.viewControllers.assetsAndActivities.ChainDisplaySettingsVC
import org.mytonwallet.app_air.uisettings.viewControllers.assetsAndActivities.views.ChainIconStackView
import org.mytonwallet.app_air.uisettings.viewControllers.baseCurrency.BaseCurrencyVC
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.theme.ViewConstants
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletbasecontext.utils.getDrawableCompat
import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage
import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.WalletEvent
import org.mytonwallet.app_air.walletcore.models.blockchain.MBlockchain
import org.mytonwallet.app_air.walletcore.stores.AccountStore
import org.mytonwallet.app_air.walletcore.stores.TokenStore

@SuppressLint("ViewConstructor")
class AssetsAndActivitiesHeaderCell(
    navigationController: WNavigationController,
    recyclerView: RecyclerView
) : WCell(recyclerView.context, LayoutParams(MATCH_PARENT, WRAP_CONTENT)),
    WThemedView {

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
        val v = WView(context)
        v.addView(baseCurrencyLabel)
        v.addView(currentBaseCurrencyLabel)
        v.setConstraints {
            toStart(baseCurrencyLabel, 20f)
            toCenterY(baseCurrencyLabel)
            toEnd(currentBaseCurrencyLabel, 20f)
            toCenterY(currentBaseCurrencyLabel)
        }
        v.setOnClickListener {
            navigationController.push(BaseCurrencyVC(context))
        }
        v
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
        val v = WView(context)
        v.addView(hideTinyTransfersLabel)
        v.addView(hideTinyTransfersSwitch)
        v.setConstraints {
            toStart(hideTinyTransfersLabel, 20f)
            toCenterY(hideTinyTransfersLabel)
            toEnd(hideTinyTransfersSwitch, 20f)
            toCenterY(hideTinyTransfersSwitch)
        }
        v.setOnClickListener {
            hideTinyTransfersSwitch.isChecked = !hideTinyTransfersSwitch.isChecked
        }
        v
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
        val v = WView(context)
        v.addView(hideUnverifiedNftsLabel)
        v.addView(hideUnverifiedNftsSwitch)
        v.setConstraints {
            toStart(hideUnverifiedNftsLabel, 20f)
            toCenterY(hideUnverifiedNftsLabel)
            toEnd(hideUnverifiedNftsSwitch, 20f)
            toCenterY(hideUnverifiedNftsSwitch)
        }
        v.setOnClickListener {
            hideUnverifiedNftsSwitch.isChecked = !hideUnverifiedNftsSwitch.isChecked
        }
        v
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
            context.getDrawableCompat(
                org.mytonwallet.app_air.icons.R.drawable.ic_arrow_right_24
            )?.apply {
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

    private val tokensHeaderCell: HeaderCell by lazy {
        HeaderCell(context).apply {
            configure(
                LocaleController.getString("Tokens"),
                titleColor = WColor.Tint,
                topRounding = HeaderCell.TopRounding.NORMAL
            )
        }
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
        val v = WView(context)
        v.addView(hideTokensWithNoCostLabel)
        v.addView(hideTokensWithNoCostSwitch)
        v.setConstraints {
            toStart(hideTokensWithNoCostLabel, 20f)
            toCenterY(hideTokensWithNoCostLabel)
            toEnd(hideTokensWithNoCostSwitch, 20f)
            toCenterY(hideTokensWithNoCostSwitch)
        }
        v.setOnClickListener {
            hideTokensWithNoCostSwitch.isChecked = !hideTokensWithNoCostSwitch.isChecked
        }
        v
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
        val v = WView(context)
        v.addView(localizedTokenNamesLabel)
        v.addView(localizedTokenNamesSwitch)
        v.setConstraints {
            toStart(localizedTokenNamesLabel, 20f)
            toCenterY(localizedTokenNamesLabel)
            toEnd(localizedTokenNamesSwitch, 20f)
            toCenterY(localizedTokenNamesSwitch)
        }
        v.setOnClickListener {
            localizedTokenNamesSwitch.isChecked = !localizedTokenNamesSwitch.isChecked
        }
        v
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

        addView(baseCurrencyView, LayoutParams(MATCH_PARENT, 50.dp))
        addView(hideTinyTransfersRow, LayoutParams(MATCH_PARENT, 50.dp))
        addView(hideUnverifiedNftsRow, LayoutParams(MATCH_PARENT, 50.dp))
        if (showBlockchainsSection) {
            addView(blockchainsHeaderCell, LayoutParams(MATCH_PARENT, 48.dp))
            addView(blockchainsView, LayoutParams(MATCH_PARENT, 64.dp))
            addView(tokensHeaderCell, LayoutParams(MATCH_PARENT, 48.dp))
        }
        addView(hideTokensWithNoCostRow, LayoutParams(MATCH_PARENT, 50.dp))
        if (showLocalizedTokenNamesRow) {
            addView(localizedTokenNamesRow, LayoutParams(MATCH_PARENT, 50.dp))
        }
        addView(tokensOnHomeScreenLabel, LayoutParams(MATCH_PARENT, 48.dp))
        addView(addTokenView, LayoutParams(MATCH_PARENT, 50.dp))

        setConstraints {
            toTop(baseCurrencyView)
            toCenterX(baseCurrencyView)
            topToBottom(hideTinyTransfersRow, baseCurrencyView)
            toCenterX(hideTinyTransfersRow)
            topToBottom(hideUnverifiedNftsRow, hideTinyTransfersRow)
            toCenterX(hideUnverifiedNftsRow)
            if (showBlockchainsSection) {
                topToBottom(
                    blockchainsHeaderCell,
                    hideUnverifiedNftsRow,
                    ViewConstants.GAP.toFloat()
                )
                toCenterX(blockchainsHeaderCell)
                topToBottom(blockchainsView, blockchainsHeaderCell)
                toCenterX(blockchainsView)
                topToBottom(tokensHeaderCell, blockchainsView, ViewConstants.GAP.toFloat())
                toCenterX(tokensHeaderCell)
                topToBottom(hideTokensWithNoCostRow, tokensHeaderCell)
            } else {
                topToBottom(
                    hideTokensWithNoCostRow,
                    hideUnverifiedNftsRow,
                    ViewConstants.GAP.toFloat()
                )
            }
            toCenterX(hideTokensWithNoCostRow)
            if (showLocalizedTokenNamesRow) {
                topToBottom(localizedTokenNamesRow, hideTokensWithNoCostRow)
                toCenterX(localizedTokenNamesRow)
            }
            topToBottom(
                tokensOnHomeScreenLabel,
                if (showLocalizedTokenNamesRow) localizedTokenNamesRow else hideTokensWithNoCostRow,
                ViewConstants.GAP.toFloat()
            )
            toCenterX(tokensOnHomeScreenLabel)
            topToBottom(addTokenView, tokensOnHomeScreenLabel)
            toCenterX(addTokenView)
            toBottom(addTokenView)
        }

        updateTheme()
    }

    override fun updateTheme() {
        baseCurrencyView.setBackgroundColor(
            WColor.Background.color,
            ViewConstants.TOOLBAR_RADIUS.dp,
            0f
        )
        baseCurrencyView.addRippleEffect(WColor.SecondaryBackground.color)
        baseCurrencyLabel.setTextColor(WColor.PrimaryText.color)
        currentBaseCurrencyLabel.setTextColor(WColor.SecondaryText.color)

        hideTinyTransfersRow.addRippleEffect(WColor.SecondaryBackground.color)
        hideTinyTransfersLabel.setTextColor(WColor.PrimaryText.color)

        hideUnverifiedNftsRow.addRippleEffect(WColor.SecondaryBackground.color)
        hideUnverifiedNftsLabel.setTextColor(WColor.PrimaryText.color)

        hideTokensWithNoCostRow.addRippleEffect(WColor.SecondaryBackground.color)
        hideTokensWithNoCostLabel.setTextColor(WColor.PrimaryText.color)

        if (showLocalizedTokenNamesRow) {
            localizedTokenNamesRow.addRippleEffect(WColor.SecondaryBackground.color)
            localizedTokenNamesLabel.setTextColor(WColor.PrimaryText.color)
        }

        hideTinyTransfersRow.setBackgroundColor(
            WColor.Background.color,
            0f,
            0f
        )
        hideUnverifiedNftsRow.setBackgroundColor(
            WColor.Background.color,
            0f,
            ViewConstants.BLOCK_RADIUS.dp
        )
        val tokensSectionBottomRadius =
            if (showLocalizedTokenNamesRow) 0f else 25f.dp
        if (showBlockchainsSection) {
            blockchainsHeaderCell.updateTheme()
            tokensHeaderCell.updateTheme()
            blockchainsView.setBackgroundColor(
                WColor.Background.color,
                0f,
                ViewConstants.BLOCK_RADIUS.dp
            )
            blockchainsView.addRippleEffect(WColor.SecondaryBackground.color)
            hideTokensWithNoCostRow.setBackgroundColor(
                WColor.Background.color,
                0f,
                tokensSectionBottomRadius
            )
        } else {
            hideTokensWithNoCostRow.setBackgroundColor(
                WColor.Background.color,
                25f.dp,
                tokensSectionBottomRadius
            )
        }
        if (showLocalizedTokenNamesRow) {
            localizedTokenNamesRow.setBackgroundColor(
                WColor.Background.color,
                0f,
                25f.dp
            )
        }

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
        if (showBlockchainsSection) {
            chainIconStackView.configure(
                AccountStore.activeAccount?.displayedChains()?.mapNotNull { entry ->
                    MBlockchain.valueOfOrNull(entry.key)
                } ?: emptyList()
            )
        }
        updateAddTokenViewRadius()
    }
}
