package org.mytonwallet.app_air.uiassets.viewControllers.assetsTab

import android.annotation.SuppressLint
import android.content.Context
import org.mytonwallet.app_air.uiassets.viewControllers.CollectionsMenuHelpers
import org.mytonwallet.app_air.uiassets.viewControllers.assets.AssetsVC
import org.mytonwallet.app_air.uiassets.viewControllers.tokens.TokensVC
import org.mytonwallet.app_air.uicomponents.base.WViewController
import org.mytonwallet.app_air.uicomponents.widgets.segmentedController.WSegmentedController
import org.mytonwallet.app_air.uicomponents.widgets.segmentedController.WSegmentedControllerItem
import org.mytonwallet.app_air.walletcontext.theme.WColor
import org.mytonwallet.app_air.walletcontext.theme.color
import org.mytonwallet.app_air.walletcore.stores.NftStore
import java.util.concurrent.Executors

@SuppressLint("ViewConstructor")
class AssetsTabVC(context: Context, defaultSelectedIndex: Int = 0) : WViewController(context) {
    companion object {
        const val ASSETS_IDENTIFIER = "a"

        const val TAB_COINS = "app:coins"
        const val TAB_COLLECTIBLES = "app:collectibles"
    }

    private val backgroundExecutor = Executors.newSingleThreadExecutor()

    override val shouldDisplayTopBar = false
    override val shouldDisplayBottomBar = true
    override val isSwipeBackAllowed = false

    private val segmentedController: WSegmentedController by lazy {
        val sc = WSegmentedController(
            navigationController!!,
            arrayOf(
                WSegmentedControllerItem(
                    TokensVC(
                        context,
                        TokensVC.Mode.ALL,
                        onScroll = { recyclerView ->
                            updateBlurViews(recyclerView)
                            segmentedController.updateBlurViews(recyclerView)
                        }),
                ),
                WSegmentedControllerItem(
                    AssetsVC(
                        context,
                        AssetsVC.Mode.COMPLETE,
                        window,
                        onScroll = { recyclerView ->
                            updateBlurViews(recyclerView)
                            segmentedController.updateBlurViews(recyclerView)
                        }),
                    identifier = ASSETS_IDENTIFIER,
                ),
            ),
            defaultSelectedIndex,
        )
        sc
    }

    override fun setupViews() {
        super.setupViews()

        segmentedController.addCloseButton()
        view.addView(segmentedController)

        view.setConstraints {
            allEdges(segmentedController)
        }

        updateCollectiblesClick()
        updateTheme()
    }

    fun updateCollectiblesClick() {
        backgroundExecutor.execute {
            val hiddenNFTsExist =
                NftStore.nftData?.cachedNfts?.firstOrNull { it.isHidden == true } != null ||
                    NftStore.nftData?.blacklistedNftAddresses?.isNotEmpty() == true
            val showCollectionsMenu = !NftStore.getCollections().isEmpty() || hiddenNFTsExist
            segmentedController.updateOnClick(
                identifier = ASSETS_IDENTIFIER,
                onClick = if (showCollectionsMenu) {
                    { v ->
                        CollectionsMenuHelpers.presentCollectionsMenuOn(
                            v,
                            navigationController!!
                        )
                    }
                } else {
                    null
                }
            )
        }
    }

    override fun updateTheme() {
        view.setBackgroundColor(WColor.SecondaryBackground.color)
    }

    override fun scrollToTop() {
        super.scrollToTop()
        segmentedController.scrollToTop()
    }

    override fun onDestroy() {
        super.onDestroy()
        segmentedController.onDestroy()
    }

}
