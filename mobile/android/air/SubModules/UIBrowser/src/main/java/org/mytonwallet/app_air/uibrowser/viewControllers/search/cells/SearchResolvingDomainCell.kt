package org.mytonwallet.app_air.uibrowser.viewControllers.search.cells

import android.content.Context
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import androidx.constraintlayout.widget.ConstraintLayout.LayoutParams.MATCH_CONSTRAINT
import androidx.core.view.doOnLayout
import org.mytonwallet.app_air.uicomponents.commonViews.SkeletonView
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.widgets.WBaseView
import org.mytonwallet.app_air.uicomponents.widgets.WCell
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.uicomponents.widgets.setBackgroundColor
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletcontext.utils.colorWithAlpha

class SearchResolvingDomainCell(context: Context) :
    WCell(context, LayoutParams(MATCH_PARENT, 60.dp)),
    WThemedView {

    private val circle = WBaseView(context)
    private val title = WBaseView(context)
    private val subtitle = WBaseView(context)
    private val skeleton = SkeletonView(context, isVertical = false)

    override fun setupViews() {
        super.setupViews()
        addView(circle, LayoutParams(24.dp, 24.dp))
        addView(title, LayoutParams(80.dp, 12.dp))
        addView(subtitle, LayoutParams(128.dp, 9.dp))
        addView(skeleton, LayoutParams(MATCH_CONSTRAINT, MATCH_CONSTRAINT))
        setConstraints {
            toStart(circle, 18f)
            toCenterY(circle)
            toStart(title, 56f)
            toTop(title, 13f)
            toStart(subtitle, 56f)
            topToBottom(subtitle, title, 9f)
            allEdges(skeleton)
        }
        skeleton.doOnLayout {
            skeleton.applyMask(
                listOf(circle, title, subtitle),
                hashMapOf(0 to 12.dp.toFloat(), 1 to 6.dp.toFloat(), 2 to 4.5f.dp)
            )
            skeleton.startAnimating()
        }
        updateTheme()
    }

    fun configure(domain: String) {
        contentDescription = "$domain, ${LocaleController.getString("Loading...")}"
    }

    override fun updateTheme() {
        val color = WColor.SecondaryText.color.colorWithAlpha(45)
        circle.setBackgroundColor(color, 12.dp.toFloat())
        title.setBackgroundColor(color, 6.dp.toFloat())
        subtitle.setBackgroundColor(color, 4.5f.dp)
        skeleton.updateTheme()
    }
}
