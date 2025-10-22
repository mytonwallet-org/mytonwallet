package org.mytonwallet.app_air.uibrowser.viewControllers.explore.cells

import android.annotation.SuppressLint
import android.content.Context
import android.view.ViewGroup
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.RecyclerView
import org.mytonwallet.app_air.uicomponents.base.WRecyclerViewAdapter
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.widgets.WCell
import org.mytonwallet.app_air.uicomponents.widgets.WRecyclerView
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.walletcontext.utils.IndexPath
import org.mytonwallet.app_air.walletcore.moshi.ApiDapp
import java.lang.ref.WeakReference

@SuppressLint("ViewConstructor")
class ExploreConnectedCell(
    context: Context,
    val dAppPressed: (it: ApiDapp?) -> Unit,
    val configurePressed: () -> Unit
) :
    WCell(context, LayoutParams(MATCH_PARENT, WRAP_CONTENT)),
    WRecyclerViewAdapter.WRecyclerViewDataSource,
    WThemedView {

    companion object {
        val SMALL_CONNECTED_CELL = Type(1)
        val LARGE_CONNECTED_CELL = Type(2)
        val CONFIGURE_CELL = Type(3)

        const val MAX_DAPPS_IN_SMALL_VIEW = 3
    }

    private val rvAdapter =
        WRecyclerViewAdapter(
            WeakReference(this),
            arrayOf(SMALL_CONNECTED_CELL, LARGE_CONNECTED_CELL, CONFIGURE_CELL)
        )

    private val recyclerView = WRecyclerView(context).apply {
        layoutManager = LinearLayoutManager(context, LinearLayoutManager.HORIZONTAL, false)
        adapter = rvAdapter
        setPadding(4.dp, 0, 4.dp, 8.dp)
        clipToPadding = false
    }

    init {
        addView(recyclerView, ViewGroup.LayoutParams(MATCH_PARENT, MATCH_PARENT))
        setConstraints { allEdges(recyclerView) }
        updateTheme()
    }

    private var connectedApps: Array<ApiDapp> = emptyArray()
    fun configure(dApps: Array<ApiDapp>) {
        this.connectedApps = dApps
        recyclerView.setPadding(
            if (showLargeConnectedApps) 10.dp else 4.dp,
            0,
            4.dp,
            8.dp
        )
        rvAdapter.reloadData()
        updateTheme()
    }

    override fun updateTheme() {
    }

    val showLargeConnectedApps: Boolean
        get() {
            return connectedApps.size > MAX_DAPPS_IN_SMALL_VIEW
        }

    override fun recyclerViewNumberOfSections(rv: RecyclerView): Int {
        return 2
    }

    override fun recyclerViewNumberOfItems(rv: RecyclerView, section: Int): Int {
        return when (section) {
            0 -> connectedApps.size
            else -> 1
        }
    }

    override fun recyclerViewCellType(
        rv: RecyclerView,
        indexPath: IndexPath
    ): Type {
        return if (indexPath.section == 0 || showLargeConnectedApps)
            if (showLargeConnectedApps) LARGE_CONNECTED_CELL else SMALL_CONNECTED_CELL
        else
            CONFIGURE_CELL
    }

    override fun recyclerViewCellView(rv: RecyclerView, cellType: Type): WCell {
        return when (cellType) {
            SMALL_CONNECTED_CELL -> {
                ExploreConnectedItemCell(context) {
                    dAppPressed(it)
                }
            }

            LARGE_CONNECTED_CELL -> {
                ExploreLargeConnectedItemCell(context, 72.dp) {
                    dAppPressed(it)
                }
            }

            else -> {
                ExploreConfigureCell(context) {
                    configurePressed()
                }
            }
        }
    }

    override fun recyclerViewConfigureCell(
        rv: RecyclerView,
        cellHolder: Holder,
        indexPath: IndexPath
    ) {
        when (cellHolder.cell) {
            is ExploreConnectedItemCell -> {
                (cellHolder.cell as ExploreConnectedItemCell).configure(connectedApps[indexPath.row])
            }

            is ExploreLargeConnectedItemCell -> {
                (cellHolder.cell as ExploreLargeConnectedItemCell).configure(if (indexPath.section == 0) connectedApps[indexPath.row] else null)
            }

            is ExploreConfigureCell -> {
                (cellHolder.cell as ExploreConfigureCell).configure()
            }
        }
    }

}
