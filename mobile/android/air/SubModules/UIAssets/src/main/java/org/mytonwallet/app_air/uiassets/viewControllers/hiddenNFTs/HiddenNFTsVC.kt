package org.mytonwallet.app_air.uiassets.viewControllers.hiddenNFTs

import android.content.Context
import android.view.ViewGroup
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.RecyclerView
import java.lang.ref.WeakReference
import org.mytonwallet.app_air.uiassets.viewControllers.hiddenNFTs.cells.HiddenNFTsItemCell
import org.mytonwallet.app_air.uiassets.viewControllers.nft.NftVC
import org.mytonwallet.app_air.uicomponents.base.WNavigationBar
import org.mytonwallet.app_air.uicomponents.base.WRecyclerViewAdapter
import org.mytonwallet.app_air.uicomponents.base.WViewController
import org.mytonwallet.app_air.uicomponents.commonViews.cells.HeaderCell
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.extensions.setPaddingLocalized
import org.mytonwallet.app_air.uicomponents.widgets.WCell
import org.mytonwallet.app_air.uicomponents.widgets.WRecyclerView
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.theme.ViewConstants
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage
import org.mytonwallet.app_air.walletcontext.utils.IndexPath
import org.mytonwallet.app_air.walletcore.moshi.ApiNft
import org.mytonwallet.app_air.walletcore.stores.NftStore

class HiddenNFTsVC(context: Context, private val showingAccountId: String) :
    WViewController(context),
    WRecyclerViewAdapter.WRecyclerViewDataSource {
    @Suppress("PropertyName")
    override val TAG = "HiddenNFTs"

    companion object {
        val HEADER_CELL = WCell.Type(1)
        val NFT_CELL = WCell.Type(2)
    }

    override val shouldDisplayBottomBar = true

    private val blacklistedNFTs = NftStore.nftData?.cachedNfts?.filter {
        NftStore.isHiddenByUser(showingAccountId, it)
    } ?: emptyList()
    private val unverifiedNFTs = if (WGlobalStorage.getAreUnverifiedNftsHidden()) {
        NftStore.nftData?.cachedNfts?.filter {
            !NftStore.isHiddenByUser(showingAccountId, it) &&
                it.isHidden != true &&
                it.isUnverified == true
        } ?: emptyList()
    } else {
        emptyList()
    }
    private val hiddenNFTs = NftStore.nftData?.cachedNfts?.filter {
        it.isHidden == true && !NftStore.isHiddenByUser(showingAccountId, it)
    } ?: emptyList()

    private fun nftsForSection(section: Int): List<ApiNft> = when (section) {
        0 -> blacklistedNFTs
        1 -> unverifiedNFTs
        else -> hiddenNFTs
    }

    private fun titleForSection(section: Int): String = when (section) {
        0 -> "Hidden By Me"
        1 -> "Unverified"
        else -> "Probably Scam"
    }

    private val rvAdapter =
        WRecyclerViewAdapter(WeakReference(this), arrayOf(HEADER_CELL, NFT_CELL))

    private val scrollListener = object : RecyclerView.OnScrollListener() {
        override fun onScrolled(recyclerView: RecyclerView, dx: Int, dy: Int) {
            super.onScrolled(recyclerView, dx, dy)
            if (dx == 0 && dy == 0) return
            updateBlurViews(recyclerView)
        }

        override fun onScrollStateChanged(recyclerView: RecyclerView, newState: Int) {
            super.onScrollStateChanged(recyclerView, newState)
            if (recyclerView.scrollState != RecyclerView.SCROLL_STATE_IDLE) {
                updateBlurViews(recyclerView)
            }
        }
    }

    private val recyclerView: WRecyclerView by lazy {
        val rv = WRecyclerView(this)
        rv.adapter = rvAdapter
        val layoutManager = LinearLayoutManager(context)
        layoutManager.isSmoothScrollbarEnabled = true
        rv.layoutManager = layoutManager
        rv.setLayoutManager(layoutManager)
        rv.clipToPadding = false
        rv.addOnScrollListener(scrollListener)
        rv.setPaddingLocalized(
            ViewConstants.HORIZONTAL_PADDINGS.dp + additionalTabletPadding,
            (navigationController?.getSystemBars()?.top ?: 0) +
                WNavigationBar.DEFAULT_HEIGHT.dp,
            ViewConstants.HORIZONTAL_PADDINGS.dp,
            (navigationController?.getSystemBars()?.bottom ?: 0)
        )
        rv.clipToPadding = false
        rv
    }

    override fun setupViews() {
        super.setupViews()

        setNavTitle(LocaleController.getString("Hidden NFTs"))
        setupNavBar(true)

        view.addView(recyclerView, ViewGroup.LayoutParams(MATCH_PARENT, MATCH_PARENT))
        view.setConstraints {
            allEdges(recyclerView)
        }

        updateTheme()
    }

    override fun updateTheme() {
        super.updateTheme()

        view.setBackgroundColor(WColor.SecondaryBackground.color)
        rvAdapter.reloadData()
    }

    override fun insetsUpdated() {
        super.insetsUpdated()
        recyclerView.setPaddingLocalized(
            ViewConstants.HORIZONTAL_PADDINGS.dp + additionalTabletPadding + systemBarStartInset,
            WNavigationBar.DEFAULT_HEIGHT.dp + (navigationController?.getSystemBars()?.top ?: 0),
            ViewConstants.HORIZONTAL_PADDINGS.dp + systemBarEndInset,
            (navigationController?.getSystemBars()?.bottom ?: 0)
        )
    }

    override fun recyclerViewNumberOfSections(rv: RecyclerView): Int = 3

    override fun recyclerViewNumberOfItems(rv: RecyclerView, section: Int): Int {
        val nfts = nftsForSection(section)
        return if (nfts.isEmpty()) 0 else 1 + nfts.size
    }

    override fun recyclerViewCellType(rv: RecyclerView, indexPath: IndexPath): WCell.Type =
        when (indexPath.row) {
            0 -> {
                HEADER_CELL
            }

            else -> {
                NFT_CELL
            }
        }

    override fun recyclerViewCellView(rv: RecyclerView, cellType: WCell.Type): WCell =
        when (cellType) {
            HEADER_CELL -> {
                HeaderCell(context, startMargin = 16f)
            }

            else -> {
                HiddenNFTsItemCell(
                    recyclerView,
                    showingAccountId,
                    onSelect = { nft ->
                        push(
                            NftVC(
                                context,
                                showingAccountId,
                                nft,
                                blacklistedNFTs + unverifiedNFTs + hiddenNFTs
                            )
                        )
                    }
                )
            }
        }

    override fun recyclerViewConfigureCell(
        rv: RecyclerView,
        cellHolder: WCell.Holder,
        indexPath: IndexPath
    ) {
        when (cellHolder.cell) {
            is HeaderCell -> {
                (cellHolder.cell as HeaderCell).configure(
                    LocaleController.getString(titleForSection(indexPath.section)),
                    WColor.Tint,
                    topRounding = if (rvAdapter.indexPathToPosition(indexPath) ==
                        0
                    ) {
                        HeaderCell.TopRounding.FIRST_ITEM
                    } else {
                        HeaderCell.TopRounding.ZERO
                    }
                )
            }

            is HiddenNFTsItemCell -> {
                val list = nftsForSection(indexPath.section)
                (cellHolder.cell as HiddenNFTsItemCell).configure(
                    list[indexPath.row - 1],
                    indexPath.row == list.size &&
                        ((indexPath.section + 1) until 3).all {
                            nftsForSection(it).isEmpty()
                        },
                    showSeparator = indexPath.row < list.size
                )
            }
        }
    }
}
