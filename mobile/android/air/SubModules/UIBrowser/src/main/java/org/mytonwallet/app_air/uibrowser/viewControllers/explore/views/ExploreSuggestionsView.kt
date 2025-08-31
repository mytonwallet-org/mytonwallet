package org.mytonwallet.app_air.uibrowser.viewControllers.explore.views

import android.annotation.SuppressLint
import android.content.Context
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import androidx.recyclerview.widget.RecyclerView
import org.mytonwallet.app_air.uibrowser.viewControllers.exploreCategory.cells.ExploreCategorySiteCell
import org.mytonwallet.app_air.uicomponents.base.WRecyclerViewAdapter
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.helpers.LinearLayoutManagerAccurateOffset
import org.mytonwallet.app_air.uicomponents.widgets.WCell
import org.mytonwallet.app_air.uicomponents.widgets.WRecyclerView
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.uicomponents.widgets.WView
import org.mytonwallet.app_air.uicomponents.widgets.setBackgroundColor
import org.mytonwallet.app_air.walletcontext.theme.ViewConstants
import org.mytonwallet.app_air.walletcontext.theme.WColor
import org.mytonwallet.app_air.walletcontext.theme.color
import org.mytonwallet.app_air.walletcontext.utils.IndexPath
import org.mytonwallet.app_air.walletcore.models.MExploreSite
import java.lang.ref.WeakReference

@SuppressLint("ViewConstructor")
class ExploreSuggestionsView(
    context: Context,
    private val onSiteTap: (site: MExploreSite) -> Unit
) :
    WView(context),
    WThemedView,
    WRecyclerViewAdapter.WRecyclerViewDataSource {

    private var suggestions = emptyList<MExploreSite>()

    companion object {
        val SUGGESTION_CELL = WCell.Type(1)
    }

    private val rvAdapter =
        WRecyclerViewAdapter(
            WeakReference(this),
            arrayOf(
                SUGGESTION_CELL
            )
        )

    private val recyclerView = WRecyclerView(context).apply {
        adapter = rvAdapter
        val layoutManager = LinearLayoutManagerAccurateOffset(context)
        layoutManager.isSmoothScrollbarEnabled = true
        setLayoutManager(layoutManager)
        setItemAnimator(null)
        clipToPadding = false
    }

    override fun setupViews() {
        super.setupViews()

        addView(recyclerView, LayoutParams(MATCH_PARENT, MATCH_PARENT))
        setConstraints {
            allEdges(recyclerView)
            constrainMaxHeight(recyclerView.id, 266.dp)
        }

        updateTheme()
    }

    override fun updateTheme() {
        rvAdapter.reloadData()
        setBackgroundColor(WColor.Background.color, ViewConstants.STANDARD_ROUNDS.dp, true)
    }

    fun config(suggestions: List<MExploreSite>) {
        this.suggestions = suggestions
        rvAdapter.reloadData()
    }

    override fun recyclerViewNumberOfSections(rv: RecyclerView): Int {
        return 1
    }

    override fun recyclerViewNumberOfItems(rv: RecyclerView, section: Int): Int {
        return suggestions.size
    }

    override fun recyclerViewCellType(rv: RecyclerView, indexPath: IndexPath): WCell.Type {
        return SUGGESTION_CELL
    }

    override fun recyclerViewCellView(rv: RecyclerView, cellType: WCell.Type): WCell {
        return ExploreCategorySiteCell(context, onSiteTap = {
            onSiteTap(it)
        })
    }

    override fun recyclerViewConfigureCell(
        rv: RecyclerView,
        cellHolder: WCell.Holder,
        indexPath: IndexPath
    ) {
        (cellHolder.cell as ExploreCategorySiteCell).configure(
            suggestions[indexPath.row],
            indexPath.row == 0,
            indexPath.row == suggestions.size - 1
        )
    }
}
