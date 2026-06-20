package org.mytonwallet.uihome.home.cells

import org.mytonwallet.app_air.uiassets.viewControllers.assets.AssetsVC
import org.mytonwallet.app_air.uiassets.viewControllers.tokens.TokensVC
import org.mytonwallet.app_air.uicomponents.widgets.WCell

/**
 * Shared surface of the home-screen assets cell, implemented by both [HomePhoneAssetsCell]
 * (segmented control) and [HomeTabletAssetsCell] (side-by-side columns). ActivityListView/HomeVC
 * talk to whichever variant is active through this interface.
 *
 * The hosted ViewControllers live in a shared [HomeAssetsVCPool] that outlives the cell, so a cell
 * is a thin host: [attachHost] points the pool's per-host callbacks and mutable callbacks at this
 * cell, and [onDestroy] only DETACHES/unmounts the VC views — it never tears the VCs down (the pool
 * does, once, in [HomeAssetsVCPool.destroy]).
 */
interface IHomeAssetsCell {
    val asCell: WCell get() = this as WCell

    val horizontalScrollOffset: Int get() = 0

    var onScrollToVisibleRequested: (() -> Unit)?

    /** Make this cell the active host for [pool]'s ViewControllers; re-binds per-host callbacks. */
    fun attachHost(pool: HomeAssetsVCPool)

    fun configure(accountId: String?)
    fun reloadTabs(resetSelection: Boolean): Boolean
    fun updateSegmentItemsTheme()
    fun scrollToFirst()
    fun setAnimations(paused: Boolean)

    /** Detach/unmount only. Does NOT destroy the pooled ViewControllers. */
    fun onDestroy()

    val isDraggingCollectible: Boolean

    val isInDragMode: Boolean
    val isInSelectionMode: Boolean
    fun startSorting()
    fun endSorting(save: Boolean)
    fun closeSelectionMode()
    fun hideSelectedAssets()
    fun selectAllVisibleAssets()
    fun sendSelectedNfts(): Boolean
    fun burnSelectedNfts(): Boolean
}

/**
 * The host-specific behaviours the pooled ViewControllers' immutable constructor callbacks forward
 * to. Implemented by both cell variants; the pool calls these on the currently-mounting host.
 */
interface IHomeAssetsHost {
    val areAssetsShown: Boolean
    fun onVcHeightChanged()
    fun onVcAssetsShown(vc: TokensVC)
    fun onVcNftsShown(vc: AssetsVC)
    fun onVcScroll(vc: org.mytonwallet.app_air.uicomponents.base.WViewController)
    fun requestReordering(reordering: Boolean)
}
