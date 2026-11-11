package org.mytonwallet.app_air.uifutures.viewControllers.futuresOpen

import android.annotation.SuppressLint
import android.content.Context
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch
import org.mytonwallet.app_air.uicomponents.base.WNavigationController
import org.mytonwallet.app_air.uicomponents.widgets.menu.WMenuPopup
import org.mytonwallet.app_air.uifutures.viewControllers.futures.helpers.fundingText
import org.mytonwallet.app_air.uifutures.viewControllers.futuresAmount.FuturesAmountVC
import org.mytonwallet.app_air.uifutures.viewControllers.futuresEdit.FuturesEditPositionView
import org.mytonwallet.app_air.uifutures.viewControllers.futuresEdit.formatBridgeFee
import org.mytonwallet.app_air.uifutures.viewControllers.futuresEdit.loadFuturesFunding
import org.mytonwallet.app_air.uifutures.viewControllers.futuresEdit.networkFeeText
import org.mytonwallet.app_air.uifutures.viewControllers.futuresEdit.previewFuturesQuote
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.WalletEvent
import org.mytonwallet.app_air.walletcore.moshi.MApiPerpsListedAsset
import org.mytonwallet.app_air.walletcore.moshi.MApiPerpsNativePosition
import org.mytonwallet.app_air.walletcore.moshi.MApiPerpsSide
import org.mytonwallet.app_air.walletcore.moshi.api.ApiMethod
import org.mytonwallet.app_air.walletcore.stores.PerpsStore

/** Opens an isolated long or short with the entered margin and the picked leverage. */
@SuppressLint("ViewConstructor")
class FuturesOpenPositionVC(
    context: Context,
    private val asset: MApiPerpsListedAsset,
    private val side: MApiPerpsSide,
    override val displayName: String
) : FuturesAmountVC(context) {
    @Suppress("PropertyName")
    override val TAG = "FuturesOpenPosition"

    override val model = FuturesOpenPositionModel(asset, side, displayedAccount.accountId)
    private var fundingJob: Job? = null

    override val amountView = FuturesEditPositionView(
        context,
        model,
        onLeverageTap = ::presentLeverage,
        onFundsHintAction = ::presentFundsBuy,
        onFundingSelected = ::onFundingSelected,
        onChange = ::onInputChanged,
        onReview = ::openReview
    )

    override val navTitle: String
        get() = LocaleController.getStringWithKeyValues(
            if (side == MApiPerpsSide.SHORT) "\$perps_order_short" else "\$perps_order_long",
            listOf("%asset%" to displayName)
        )

    override val reviewedPosition: MApiPerpsNativePosition? = null

    override val explanationKeys = listOf("\$perps_position_size_hint")

    override fun setupViews() {
        super.setupViews()
        refreshEmptyFunding()
    }

    override fun onWalletEvent(walletEvent: WalletEvent) {
        when (walletEvent) {
            WalletEvent.BalanceChanged -> onBalanceChanged()

            WalletEvent.TokensChanged -> onTokensChanged()

            WalletEvent.PerpsUpdated -> {
                PerpsStore.assetsById[model.asset.id]?.let { model.asset = it }
                updatePriceSubtitle()
                refreshMissingFunding()
                refreshEstimate()
                amountView.render()
            }

            else -> {}
        }
    }

    override fun refreshFunding() {
        refreshEmptyFunding()
        scheduleEstimate()
    }

    override fun refreshBlockedFunding() {
        refreshEmptyFunding()
        if (model.estimate?.funding != null) scheduleEstimate() else amountView.render()
    }

    override fun scheduleEstimate() {
        model.pendingFraction?.let { percent ->
            val key = model.currentKey
            val draft = model.draft(key.copy(amount = "")).copy(fraction = percent)
            estimate(isDebounced = false) {
                val result = previewFuturesQuote(displayedAccount.accountId, draft)
                model.updateAvailableCollateral(result.funding, key.isFromBalance)
                model.applyFractionResult(result)
            }
            return
        }
        if (model.margin <= 0) {
            cancelEstimate()
            return
        }
        val key = model.currentKey
        estimate {
            val result = previewFuturesQuote(displayedAccount.accountId, model.draft(key))
            model.updateAvailableCollateral(result.funding, key.isFromBalance)
            model.setEstimate(key, result)
        }
    }

    override fun reviewRequest(): ReviewRequest {
        val key = model.currentKey
        return ReviewRequest(model.draft(key)) { model.setEstimate(key, it) }
    }

    override fun menuItems(): List<WMenuPopup.Item> = listOfNotNull(
        model.currentEstimate?.formatBridgeFee()?.let { menuItem("PerpsBridgeFee", it) },
        model.currentEstimate?.networkFeeText()?.let { menuItem("Network Fee", it) },
        menuItem("Funding Rate", asset.context?.fundingText()).apply { hasSeparator = true }
    )

    private fun refreshMissingFunding() {
        if (model.hasAvailableCollateral || fundingJob?.isActive == true) return
        refreshEmptyFunding()
    }

    private fun refreshEmptyFunding() {
        fundingJob?.cancel()
        val key = model.currentKey.copy(amount = "")
        val draft = model.draft(key)
        fundingJob = scope.launch {
            val funding = loadFuturesFunding(displayedAccount.accountId, draft)
            model.emptyFunding = funding
            model.updateAvailableCollateral(funding, key.isFromBalance)
            amountView.render()
        }
    }

    private fun presentLeverage() {
        val window = window ?: return
        val margin = model.margin
        val key = model.currentKey
        val accountId = displayedAccount.accountId
        val nav = WNavigationController(
            window,
            WNavigationController.PresentationConfig(
                style = WNavigationController.PresentationStyle.BottomSheet,
                aboveKeyboard = true
            )
        )
        nav.setRoot(
            FuturesLeverageVC(
                context,
                maxLeverage = asset.maxLeverage,
                leverage = model.leverage,
                priceTitle = LocaleController.getStringWithKeyValues(
                    "\$perps_asset_price",
                    listOf("%asset%" to displayName)
                ),
                markPrice = model.markPrice,
                estimate = model.liquidationPrice?.let { FuturesLeverageVC.Estimate(it) },
                loadEstimate = if (margin > 0 && accountId != null) {
                    { leverage ->
                        FuturesLeverageVC.Estimate(
                            WalletCore.call(
                                ApiMethod.Perps.GetLeverageEstimate(
                                    accountId,
                                    model.draft(key.copy(leverage = leverage))
                                )
                            ).liquidationPrice?.toDoubleOrNull()
                        )
                    }
                } else {
                    null
                }
            ) { leverage ->
                model.setLeverage(leverage)
                refreshEmptyFunding()
                onInputChanged()
            }
        )
        window.present(nav)
    }
}
