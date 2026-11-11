package org.mytonwallet.app_air.uifutures.viewControllers.futures.cells

import android.annotation.SuppressLint
import android.content.Context
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import androidx.recyclerview.widget.RecyclerView
import org.mytonwallet.app_air.icons.R as IconsR
import org.mytonwallet.app_air.uicomponents.commonViews.cells.ShowAllView
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.widgets.WCell
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.uicomponents.widgets.WView

@SuppressLint("ViewConstructor")
class FuturesShowAllPositionsCell(context: Context, text: String, onShowAll: () -> Unit) :
    WCell(context, RecyclerView.LayoutParams(MATCH_PARENT, WRAP_CONTENT)),
    WThemedView {

    private val cardView = WView(context)
    private val showAllView = ShowAllView(context).apply {
        configure(
            icon = IconsR.drawable.ic_show_assets,
            text = text
        )
        onTap = onShowAll
    }

    init {
        cardView.addView(showAllView, LayoutParams(MATCH_PARENT, ROW_HEIGHT.dp))
        cardView.setConstraints {
            allEdges(showAllView)
        }
        addView(cardView, LayoutParams(MATCH_PARENT, WRAP_CONTENT))
        setConstraints {
            allEdges(cardView)
        }
        updateTheme()
    }

    /** `onShowAll` replaces the tap action, for a cell reused across groups. */
    fun configure(count: Int, onShowAll: (() -> Unit)? = null) {
        configureCard(isLast = true)
        showAllView.setCounter(count)
        onShowAll?.let { showAllView.onTap = it }
        updateTheme()
    }

    override fun updateTheme() {
        cardView.setPositionsCardBackground(isFirst = false, isLast = true)
        showAllView.updateTheme()
    }

    private companion object {
        const val ROW_HEIGHT = 50
    }
}
