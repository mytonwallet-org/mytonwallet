package org.mytonwallet.app_air.uifutures.viewControllers.futuresEdit

import android.annotation.SuppressLint
import android.content.Context
import org.mytonwallet.app_air.uicomponents.widgets.menu.WMenuPopup
import org.mytonwallet.app_air.uifutures.viewControllers.futuresAmount.FuturesAmountVC
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletcore.WalletEvent
import org.mytonwallet.app_air.walletcore.moshi.MApiPerpsNativePosition
import org.mytonwallet.app_air.walletcore.moshi.MApiPerpsSide
import org.mytonwallet.app_air.walletcore.stores.PerpsStore

/** Changes the margin of a position, previewing the result before review. */
@SuppressLint("ViewConstructor")
class FuturesEditPositionVC(
    context: Context,
    position: MApiPerpsNativePosition,
    override val displayName: String
) : FuturesAmountVC(context) {
    @Suppress("PropertyName")
    override val TAG = "FuturesEditPosition"

    override val model = FuturesEditPositionModel(position, displayedAccount.accountId)

    override val amountView = FuturesEditPositionView(
        context,
        model,
        onFundsHintAction = ::presentFundsBuy,
        onFundingSelected = ::onFundingSelected,
        onChange = ::onInputChanged,
        onReview = ::openReview
    )

    override val navTitle: String
        get() = LocaleController.getStringWithKeyValues(
            if (model.position.side == MApiPerpsSide.SHORT) {
                "\$perps_edit_short"
            } else {
                "\$perps_edit_long"
            },
            listOf("%asset%" to model.position.symbol)
        )

    override val reviewedPosition: MApiPerpsNativePosition
        get() = model.position

    override val explanationKeys =
        listOf("\$perps_edit_liquidation_hint", "\$perps_position_size_hint")

    override fun onWalletEvent(walletEvent: WalletEvent) {
        when (walletEvent) {
            WalletEvent.BalanceChanged -> onBalanceChanged()

            WalletEvent.TokensChanged -> onTokensChanged()

            WalletEvent.PerpsUpdated -> {
                val assetId = model.position.asset?.id ?: return
                PerpsStore.snapshotFor(displayedAccount.accountId)?.openPositions
                    ?.firstOrNull { it.assetId == assetId }
                    ?.let {
                        // An untouched field follows the position's current margin
                        val wasChanged = model.isChanged
                        model.position = it
                        if (!wasChanged) model.resetToCurrent()
                    }
                updatePriceSubtitle()
                refreshEstimate()
                amountView.render()
            }

            else -> {}
        }
    }

    override fun refreshFunding() = scheduleEstimate()

    override fun refreshBlockedFunding() {
        if (model.estimate?.funding != null) scheduleEstimate()
    }

    override fun scheduleEstimate() {
        if (!model.isChanged || model.targetMargin <= 0 || model.position.asset == null) {
            cancelEstimate()
            return
        }
        val draft = model.draft
        estimate {
            model.setEstimate(draft, previewFuturesQuote(displayedAccount.accountId, draft))
        }
    }

    override fun reviewRequest(): ReviewRequest {
        val draft = model.draft
        return ReviewRequest(draft) { model.setEstimate(draft, it) }
    }

    override fun menuItems(): List<WMenuPopup.Item> {
        val quote = model.currentEstimate
        val networkFee = quote?.networkFeeText()
        return listOfNotNull(
            quote?.formatBridgeFee()?.let {
                menuItem("PerpsBridgeFee", it).apply { hasSeparator = networkFee == null }
            },
            networkFee?.let { menuItem("Network Fee", it).apply { hasSeparator = true } }
        )
    }
}
