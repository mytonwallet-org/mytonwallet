package org.mytonwallet.app_air.uisettings.viewControllers.assetsAndActivities.cells

import WNavigationController
import android.annotation.SuppressLint
import android.view.ViewGroup
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import androidx.core.content.ContextCompat
import androidx.recyclerview.widget.RecyclerView
import org.mytonwallet.app_air.uicomponents.drawable.SeparatorBackgroundDrawable
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.viewControllers.selector.TokenSelectorVC
import org.mytonwallet.app_air.uicomponents.widgets.WBaseView
import org.mytonwallet.app_air.uicomponents.widgets.WCell
import org.mytonwallet.app_air.uicomponents.widgets.WImageView
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.uicomponents.widgets.WSwitch
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.uicomponents.widgets.WView
import org.mytonwallet.app_air.uicomponents.widgets.setBackgroundColor
import org.mytonwallet.app_air.uisettings.R
import org.mytonwallet.app_air.uisettings.viewControllers.baseCurrency.BaseCurrencyVC
import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage
import org.mytonwallet.app_air.walletcontext.helpers.LocaleController
import org.mytonwallet.app_air.walletcontext.theme.ThemeManager
import org.mytonwallet.app_air.walletcontext.theme.ViewConstants
import org.mytonwallet.app_air.walletcontext.theme.WColor
import org.mytonwallet.app_air.walletcontext.theme.color
import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.WalletEvent
import org.mytonwallet.app_air.walletcore.models.MBlockchain
import org.mytonwallet.app_air.walletcore.stores.AccountStore
import org.mytonwallet.app_air.walletcore.stores.TokenStore

@SuppressLint("ViewConstructor")
class AssetsAndActivitiesHeaderCell(
    navigationController: WNavigationController,
    recyclerView: RecyclerView
) :
    WCell(recyclerView.context, LayoutParams(MATCH_PARENT, WRAP_CONTENT)),
    WThemedView {

    private val baseCurrencyLabel: WLabel by lazy {
        val lbl = WLabel(context)
        lbl.setStyle(16f)
        lbl.text =
            LocaleController.getString("Base Currency")
        lbl
    }

    private val currentBaseCurrencyLabel: WLabel by lazy {
        val lbl = WLabel(context)
        lbl.setStyle(16f)
        lbl
    }

    private val baseCurrencySeparatorView: WBaseView by lazy {
        val v = WBaseView(context)
        v
    }

    private val baseCurrencyView: WView by lazy {
        val v = WView(context)
        v.addView(baseCurrencyLabel)
        v.addView(currentBaseCurrencyLabel)
        v.addView(baseCurrencySeparatorView, ViewGroup.LayoutParams(MATCH_PARENT, 1))
        v.setConstraints {
            toStart(baseCurrencyLabel, 20f)
            toCenterY(baseCurrencyLabel)
            toEnd(currentBaseCurrencyLabel, 20f)
            toCenterY(currentBaseCurrencyLabel)
            toStart(baseCurrencySeparatorView, 20f)
            toEnd(baseCurrencySeparatorView, 16f)
            toBottom(baseCurrencySeparatorView)
        }
        v.setOnClickListener {
            navigationController.push(BaseCurrencyVC(context))
        }
        v
    }

    private val hideTinyTransfersLabel: WLabel by lazy {
        val lbl = WLabel(context)
        lbl.setStyle(16f)
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

    private val hideTokensWithNoCostLabel: WLabel by lazy {
        val lbl = WLabel(context)
        lbl.setStyle(16f)
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

    private val separatorBackgroundDrawable: SeparatorBackgroundDrawable by lazy {
        SeparatorBackgroundDrawable().apply {
            backgroundWColor = WColor.Background
        }
    }

    private val tokensOnHomeScreenLabel: WLabel by lazy {
        val lbl = WLabel(context)
        lbl.setStyle(16f, WFont.Medium)
        lbl.text =
            LocaleController.getString("Tokens on Home Screen")
        lbl
    }

    private val tokensOnHomeScreenView: WView by lazy {
        val v = WView(context)
        v.addView(tokensOnHomeScreenLabel)
        v.setConstraints {
            toStart(tokensOnHomeScreenLabel, 20f)
            toCenterY(tokensOnHomeScreenLabel)
        }
        v
    }

    private val addIcon: WImageView by lazy {
        val iv = WImageView(context)
        iv.setImageDrawable(ContextCompat.getDrawable(context, R.drawable.ic_plus)?.apply {
            setTint(WColor.Tint.color)
        })
        iv
    }

    private val addTokenLabel: WLabel by lazy {
        val lbl = WLabel(context)
        lbl.setStyle(16f, WFont.Medium)
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
            toStart(addTokenLabel, 76f)
            toCenterY(addIcon)
            toStart(addIcon, 28f)
        }
        v.setOnClickListener {
            navigationController.push(
                TokenSelectorVC(
                    context,
                    LocaleController.getString("Add Token"),
                    TokenStore.swapAssets2?.filter {
                        MBlockchain.supportedChainValues.contains(it.chain)
                    } ?: emptyList(),
                    false
                ).apply {
                    setOnAssetSelectListener { asset ->
                        val assetsAndActivityData = AccountStore.assetsAndActivityData
                        assetsAndActivityData.deletedTokens =
                            ArrayList(assetsAndActivityData.deletedTokens.filter {
                                it != asset.slug
                            })
                        if (assetsAndActivityData.getAllTokens(shouldSort = false)
                                .firstOrNull {
                                    it.token == asset.slug
                                } == null
                        ) {
                            assetsAndActivityData.addedTokens.add(asset.slug)
                        }
                        if (!assetsAndActivityData.visibleTokens.any { visibleToken ->
                                visibleToken == asset.slug
                            }) {
                            assetsAndActivityData.visibleTokens.add(asset.slug)
                        }
                        AccountStore.updateAssetsAndActivityData(
                            assetsAndActivityData,
                            notify = true
                        )
                    }
                })
        }
        v
    }

    override fun setupViews() {
        super.setupViews()

        addView(baseCurrencyView, LayoutParams(MATCH_PARENT, 56.dp))
        addView(hideTinyTransfersRow, LayoutParams(MATCH_PARENT, 56.dp))
        addView(hideTokensWithNoCostRow, LayoutParams(MATCH_PARENT, 56.dp))
        addView(tokensOnHomeScreenView, LayoutParams(MATCH_PARENT, 48.dp))
        addView(addTokenView, LayoutParams(MATCH_PARENT, 56.dp))

        setConstraints {
            toTop(baseCurrencyView)
            toCenterX(baseCurrencyView)
            topToBottom(hideTinyTransfersRow, baseCurrencyView)
            toCenterX(hideTinyTransfersRow)
            topToBottom(hideTokensWithNoCostRow, hideTinyTransfersRow, ViewConstants.GAP.toFloat())
            toCenterX(hideTokensWithNoCostRow)
            topToBottom(
                tokensOnHomeScreenView,
                hideTokensWithNoCostRow,
                ViewConstants.GAP.toFloat()
            )
            toCenterX(tokensOnHomeScreenView)
            topToBottom(addTokenView, tokensOnHomeScreenView)
            toCenterX(addTokenView)
            toBottom(addTokenView)
        }

        updateTheme()
    }

    override fun updateTheme() {
        baseCurrencyView.setBackgroundColor(
            WColor.Background.color,
            ViewConstants.TOP_RADIUS.dp,
            0f,
        )
        baseCurrencyView.addRippleEffect(WColor.SecondaryBackground.color)
        baseCurrencyLabel.setTextColor(WColor.PrimaryText.color)
        currentBaseCurrencyLabel.setTextColor(WColor.SecondaryText.color)
        baseCurrencySeparatorView.setBackgroundColor(WColor.Separator.color)

        hideTinyTransfersRow.addRippleEffect(WColor.SecondaryBackground.color)
        hideTinyTransfersLabel.setTextColor(WColor.PrimaryText.color)

        hideTokensWithNoCostRow.addRippleEffect(WColor.SecondaryBackground.color)
        hideTokensWithNoCostLabel.setTextColor(WColor.PrimaryText.color)

        if (ThemeManager.uiMode.hasRoundedCorners) {
            hideTinyTransfersRow.setBackgroundColor(
                WColor.Background.color,
                0f,
                ViewConstants.BIG_RADIUS.dp
            )
            hideTokensWithNoCostRow.setBackgroundColor(
                WColor.Background.color,
                ViewConstants.BIG_RADIUS.dp
            )
        } else {
            hideTinyTransfersRow.background = separatorBackgroundDrawable
            hideTokensWithNoCostRow.background = separatorBackgroundDrawable
            separatorBackgroundDrawable.invalidateSelf()
        }

        tokensOnHomeScreenView.setBackgroundColor(
            WColor.Background.color,
            ViewConstants.BIG_RADIUS.dp,
            0f,
        )
        tokensOnHomeScreenLabel.setTextColor(WColor.Tint.color)

        addTokenView.setBackgroundColor(WColor.Background.color)
        addTokenView.addRippleEffect(WColor.SecondaryBackground.color)
        addTokenLabel.setTextColor(WColor.Tint.color)
    }

    private lateinit var onHideNoCostTokensChanged: (hidden: Boolean) -> Unit
    fun configure(onHideNoCostTokensChanged: (hidden: Boolean) -> Unit) {
        this.onHideNoCostTokensChanged = onHideNoCostTokensChanged
        currentBaseCurrencyLabel.text = WalletCore.baseCurrency?.currencySymbol
    }

}
