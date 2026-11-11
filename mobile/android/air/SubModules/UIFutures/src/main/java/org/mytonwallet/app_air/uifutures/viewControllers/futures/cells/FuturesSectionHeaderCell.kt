package org.mytonwallet.app_air.uifutures.viewControllers.futures.cells

import android.annotation.SuppressLint
import android.content.Context
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import androidx.recyclerview.widget.RecyclerView
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.extensions.setPaddingLocalized
import org.mytonwallet.app_air.uicomponents.widgets.WCell
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.uicomponents.widgets.WView
import org.mytonwallet.app_air.uimarket.viewControllers.market.views.MarketSectionHeaderView

/** The top of a rows section card: its title and See All, styled like the Market screen's. */
@SuppressLint("ViewConstructor")
class FuturesSectionHeaderCell(context: Context) :
    WCell(context, RecyclerView.LayoutParams(MATCH_PARENT, WRAP_CONTENT)),
    WThemedView {

    private var onSeeAll: (() -> Unit)? = null
    private val cardView = WView(context)
    private val headerView = MarketSectionHeaderView(context) { onSeeAll?.invoke() }

    init {
        cardView.addView(headerView, LayoutParams(MATCH_PARENT, HEADER_HEIGHT.dp))
        cardView.setConstraints {
            allEdges(headerView)
        }
        addView(cardView, LayoutParams(MATCH_PARENT, WRAP_CONTENT))
        setConstraints {
            allEdges(cardView)
        }
        updateTheme()
    }

    fun configure(title: String, showsSeeAll: Boolean, onSeeAll: () -> Unit) {
        setCardPadding(0)
        this.onSeeAll = onSeeAll
        headerView.configure(title, showsSeeAll)
        updateTheme()
    }

    override fun updateTheme() {
        cardView.setPositionsCardBackground(isFirst = true, isLast = false)
        headerView.updateTheme()
    }

    private companion object {
        const val HEADER_HEIGHT = 48
    }
}
