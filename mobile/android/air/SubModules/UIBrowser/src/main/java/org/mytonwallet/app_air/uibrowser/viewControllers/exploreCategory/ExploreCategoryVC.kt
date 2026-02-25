package org.mytonwallet.app_air.uibrowser.viewControllers.exploreCategory

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.view.ViewGroup
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.RecyclerView
import org.mytonwallet.app_air.uibrowser.viewControllers.exploreCategory.cells.ExploreCategorySiteCell
import org.mytonwallet.app_air.uicomponents.base.WNavigationController
import org.mytonwallet.app_air.uicomponents.base.WRecyclerViewAdapter
import org.mytonwallet.app_air.uicomponents.base.WViewController
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.helpers.LastItemPaddingDecoration
import org.mytonwallet.app_air.uicomponents.widgets.WCell
import org.mytonwallet.app_air.uicomponents.widgets.WRecyclerView
import org.mytonwallet.app_air.uiinappbrowser.InAppBrowserVC
import org.mytonwallet.app_air.walletbasecontext.theme.ViewConstants
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletcontext.utils.IndexPath
import org.mytonwallet.app_air.walletcore.models.InAppBrowserConfig
import org.mytonwallet.app_air.walletcore.models.MExploreCategory
import org.mytonwallet.app_air.walletcore.models.MExploreSite
import java.lang.ref.WeakReference

class ExploreCategoryVC(context: Context, val category: MExploreCategory) :
    WViewController(context),
    WRecyclerViewAdapter.WRecyclerViewDataSource {
    override val TAG = "ExploreCategory"

    companion object {
        val EXPLORE_SITE_CELL = WCell.Type(1)
    }

    override val shouldDisplayTopBar = true
    override val shouldDisplayBottomBar = true

    override var title = category.name

    private val rvAdapter =
        WRecyclerViewAdapter(
            WeakReference(this),
            arrayOf(EXPLORE_SITE_CELL)
        )

    private val scrollListener = object : RecyclerView.OnScrollListener() {
        override fun onScrollStateChanged(recyclerView: RecyclerView, newState: Int) {
            super.onScrollStateChanged(recyclerView, newState)
            if (recyclerView.computeVerticalScrollOffset() == 0)
                updateBlurViews(recyclerView)
        }

        override fun onScrolled(recyclerView: RecyclerView, dx: Int, dy: Int) {
            super.onScrolled(recyclerView, dx, dy)
            if (dx == 0 && dy == 0)
                return
            updateBlurViews(recyclerView)
        }
    }

    private val recyclerView: WRecyclerView by lazy {
        val rv = WRecyclerView(this)
        rv.adapter = rvAdapter
        val layoutManager = LinearLayoutManager(context)
        layoutManager.isSmoothScrollbarEnabled = true
        rv.layoutManager = layoutManager
        rv.setLayoutManager(layoutManager)
        rv.addItemDecoration(
            LastItemPaddingDecoration(
                navigationController?.getSystemBars()?.bottom ?: 0
            )
        )
        rv.addOnScrollListener(scrollListener)
        rv.clipToPadding = false
        rv
    }

    override fun insetsUpdated() {
        super.insetsUpdated()
        recyclerView.removeItemDecorationAt(0)
        recyclerView.addItemDecoration(
            LastItemPaddingDecoration(
                navigationController?.getSystemBars()?.bottom ?: 0
            )
        )
    }

    override fun setupViews() {
        super.setupViews()

        setupNavBar(true)

        view.addView(recyclerView, ViewGroup.LayoutParams(MATCH_PARENT, MATCH_PARENT))
        view.setConstraints {
            allEdges(recyclerView)
        }
        recyclerView.setPadding(
            ViewConstants.HORIZONTAL_PADDINGS.dp,
            navigationBar?.calculatedMinHeight ?: 0,
            ViewConstants.HORIZONTAL_PADDINGS.dp,
            0
        )

        updateTheme()
    }

    override fun updateTheme() {
        super.updateTheme()
        view.setBackgroundColor(WColor.SecondaryBackground.color)
    }

    private fun onSiteTap(app: MExploreSite) {
        if (app.url.isNullOrEmpty())
            return
        if (app.isExternal ||
            (!app.url!!.startsWith("http://") && !app.url!!.startsWith("https://")) ||
            app.isTelegram
        ) {
            val intent = Intent(Intent.ACTION_VIEW)
            intent.setData(Uri.parse(app.url))
            window!!.startActivity(intent)
            return
        }
        val inAppBrowserVC = InAppBrowserVC(
            context,
            navigationController?.tabBarController,
            InAppBrowserConfig(
                url = app.url!!,
                title = app.name,
                thumbnail = app.iconUrl,
                injectDappConnect = true,
                saveInVisitedHistory = true,
            )
        )
        val nav = WNavigationController(window!!)
        nav.setRoot(inAppBrowserVC)
        window!!.present(nav)
    }

    override fun recyclerViewNumberOfSections(rv: RecyclerView): Int {
        return 1
    }

    override fun recyclerViewNumberOfItems(rv: RecyclerView, section: Int): Int {
        return category.sites.size
    }

    override fun recyclerViewCellType(rv: RecyclerView, indexPath: IndexPath): WCell.Type {
        return EXPLORE_SITE_CELL
    }

    override fun recyclerViewCellView(rv: RecyclerView, cellType: WCell.Type): WCell {
        val weakThis = WeakReference(this)
        return ExploreCategorySiteCell(context) {
            weakThis.get()?.onSiteTap(it)
        }
    }

    override fun recyclerViewConfigureCell(
        rv: RecyclerView,
        cellHolder: WCell.Holder,
        indexPath: IndexPath
    ) {
        (cellHolder.cell as ExploreCategorySiteCell).configure(
            category.sites[indexPath.row],
            indexPath.row == 0,
            indexPath.row == category.sites.size - 1
        )
    }

    override fun onDestroy() {
        super.onDestroy()
        recyclerView.removeOnScrollListener(scrollListener)
    }

}
