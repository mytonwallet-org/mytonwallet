package org.mytonwallet.app_air.uibrowser.viewControllers.explore.cells

import android.annotation.SuppressLint
import android.content.Context
import android.view.ViewGroup
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import android.widget.HorizontalScrollView
import android.widget.LinearLayout
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.widgets.WCell
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.walletcore.models.MExploreSite

@SuppressLint("ViewConstructor")
class ExploreTrendingCell(
    context: Context,
    private val cellWidth: Int,
    private val onSiteTap: (site: MExploreSite) -> Unit,
) :
    WCell(context, LayoutParams(MATCH_PARENT, WRAP_CONTENT)), WThemedView {

    @SuppressLint("ClickableViewAccessibility")
    private val horizontalScrollView = HorizontalScrollView(context).apply {
        id = generateViewId()
        layoutParams = ViewGroup.LayoutParams(
            MATCH_PARENT,
            WRAP_CONTENT
        )
        isHorizontalScrollBarEnabled = false
    }

    private val container = LinearLayout(context).apply {
        orientation = LinearLayout.HORIZONTAL
        layoutParams = ViewGroup.LayoutParams(
            MATCH_PARENT,
            WRAP_CONTENT
        )
    }

    init {
        horizontalScrollView.addView(container)
        addView(horizontalScrollView)
        setConstraints {
            toTop(horizontalScrollView, 0f)
            toBottom(horizontalScrollView)
            toCenterX(horizontalScrollView)
        }
        updateTheme()
    }

    fun configure(sites: Array<MExploreSite>?) {
        container.removeAllViews()

        for (site in sites ?: emptyArray()) {
            container.addView(
                ExploreTrendingItemCell(
                    context,
                    cellWidth,
                    site,
                    onSiteTap
                )
            )
        }
        container.setPadding(6.dp, 0, 6.dp, 0)
    }

    override fun updateTheme() {
    }
}
