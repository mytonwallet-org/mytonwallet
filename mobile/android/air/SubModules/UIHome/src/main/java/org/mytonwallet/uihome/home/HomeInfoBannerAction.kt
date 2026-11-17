package org.mytonwallet.uihome.home

import org.mytonwallet.app_air.uicomponents.base.WNavigationController
import org.mytonwallet.app_air.uicomponents.base.WWindow
import org.mytonwallet.app_air.uistake.staking.StakingVC
import org.mytonwallet.app_air.uistake.staking.StakingViewModel
import org.mytonwallet.app_air.walletcore.TONCOIN_SLUG
import org.mytonwallet.app_air.walletcore.moshi.ApiPromotion
import org.mytonwallet.app_air.walletcore.stores.AccountStore

// Opens TON staking for a Home banner whose button offers it, once the account's data has loaded
internal fun presentHomeInfoBannerAction(
    window: WWindow,
    promotion: ApiPromotion,
    isGeneralDataAvailable: Boolean
) {
    val action = promotion.infoBanner?.actionButton?.onClickAction
    if (action != "openEarn" && action != "unstakeForeign") return
    if (!isGeneralDataAvailable && AccountStore.activeAccount?.isNew != true) return
    val navVC = WNavigationController(
        window,
        WNavigationController.PresentationConfig.PreferredFullScreen
    )
    navVC.setRoot(StakingVC(window, TONCOIN_SLUG, StakingViewModel.Mode.STAKE))
    window.present(navVC)
}
