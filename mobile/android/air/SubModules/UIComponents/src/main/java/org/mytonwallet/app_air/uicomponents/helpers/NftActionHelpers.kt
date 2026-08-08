package org.mytonwallet.app_air.uicomponents.helpers

import org.mytonwallet.app_air.uicomponents.base.ITabsVC
import org.mytonwallet.app_air.uicomponents.base.WWindow
import org.mytonwallet.app_air.uicomponents.base.showAlert
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.logger.Logger
import org.mytonwallet.app_air.walletcontext.models.MBlockchainNetwork
import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.models.blockchain.MBlockchain
import org.mytonwallet.app_air.walletcore.moshi.ApiNft
import org.mytonwallet.app_air.walletcore.moshi.api.ApiMethod
import org.mytonwallet.app_air.walletcore.stores.NftStore

object NftActionHelpers {
    fun hideNft(window: WWindow?, accountId: String, nft: ApiNft) {
        val presentingViewController = window.presentingViewController() ?: return
        presentingViewController.showAlert(
            title = LocaleController.getString("Hide NFT"),
            text = LocaleController.getString(
                "Do you also want to report this NFT as inappropriate? " +
                    "It will be then permanently removed on this device."
            ),
            button = LocaleController.getString("Hide and Report"),
            buttonPressed = {
                hideAndReportNft(accountId, nft)
            },
            secondaryButton = LocaleController.getString("Only Hide"),
            secondaryButtonPressed = {
                hideNftLocally(accountId, nft)
            },
            preferPrimary = false,
            primaryIsDanger = true
        )
    }

    fun reportNft(window: WWindow?, accountId: String, nft: ApiNft) {
        val presentingViewController = window.presentingViewController() ?: return
        presentingViewController.showAlert(
            title = LocaleController.getString("Report NFT"),
            text = LocaleController.getString(
                "This NFT will remain hidden on this device and be reported."
            ),
            button = LocaleController.getString("Report"),
            buttonPressed = {
                reportNft(accountId, nft)
            },
            secondaryButton = LocaleController.getString("Cancel"),
            preferPrimary = false,
            primaryIsDanger = true
        )
    }

    fun hideAndReportNft(window: WWindow?, accountId: String, nft: ApiNft) {
        val presentingViewController = window.presentingViewController() ?: return
        presentingViewController.showAlert(
            title = LocaleController.getString("Hide and Report NFT"),
            text = LocaleController.getString(
                "This NFT will be permanently hidden on this device and reported."
            ),
            button = LocaleController.getString("Hide and Report"),
            buttonPressed = {
                hideAndReportNft(accountId, nft)
            },
            secondaryButton = LocaleController.getString("Cancel"),
            preferPrimary = false,
            primaryIsDanger = true
        )
    }

    private fun hideNftLocally(accountId: String, nft: ApiNft) {
        NftStore.hideNft(accountId, nft)
    }

    private fun hideAndReportNft(accountId: String, nft: ApiNft) {
        hideNftLocally(accountId, nft)
        reportNft(accountId, nft)
    }

    private fun reportNft(accountId: String, nft: ApiNft) {
        WalletCore.call(
            ApiMethod.Nft.ReportNft(
                chain = nft.chain ?: MBlockchain.ton,
                network = MBlockchainNetwork.ofAccountId(accountId),
                nftAddress = nft.address
            )
        ) { _, error ->
            if (error != null) {
                Logger.e(
                    Logger.LogTag.WALLET_CORE,
                    "Failed to report NFT ${nft.address}: ${error.message}"
                )
            }
        }
    }

    private fun WWindow?.presentingViewController() = this?.topViewController?.let { top ->
        (top as? ITabsVC)?.activeNavigationController?.viewControllers?.lastOrNull() ?: top
    }
}
