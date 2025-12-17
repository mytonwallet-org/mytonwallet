package org.mytonwallet.app_air.uicomponents.widgets

import android.annotation.SuppressLint
import android.graphics.Rect
import android.view.View
import android.widget.ScrollView
import me.everything.android.ui.overscroll.OverScrollBounceEffectDecoratorBase
import me.everything.android.ui.overscroll.VerticalOverScrollBounceEffectDecorator
import me.everything.android.ui.overscroll.adapters.ScrollViewOverScrollDecorAdapter
import org.mytonwallet.app_air.uicomponents.base.WViewController
import org.mytonwallet.app_air.uicomponents.extensions.dp
import java.lang.ref.WeakReference
import kotlin.math.max

@SuppressLint("ViewConstructor")
open class WScrollView(private val viewController: WeakReference<WViewController>) :
    ScrollView(viewController.get()!!.context) {
    init {
        id = generateViewId()
        isVerticalScrollBarEnabled = false
    }

    private var verticalOverScrollBounceEffectDecorator: VerticalOverScrollBounceEffectDecorator? =
        null

    fun setupOverScroll() {
        verticalOverScrollBounceEffectDecorator = VerticalOverScrollBounceEffectDecorator(
            ScrollViewOverScrollDecorAdapter(this),
            OverScrollBounceEffectDecoratorBase.DEFAULT_DECELERATE_FACTOR
        )
    }

    var onScrollChange: ((Int) -> Unit)? = null

    override fun onScrollChanged(l: Int, t: Int, oldl: Int, oldt: Int) {
        super.onScrollChanged(l, t, oldl, oldt)
        onScrollChange?.invoke(t)
    }

    fun scrollToBottom() {
        smoothScrollTo(0, getChildAt(0).bottom);
    }

    private fun getDistanceFromViewToScrollViewBottom(view: View): Int {
        val rect = Rect()
        view.getGlobalVisibleRect(rect)
        return height - rect.bottom
    }

    fun makeViewVisible(view: WView) {
        val vc = viewController.get()
        val topInset = vc?.navigationController?.getSystemBars()?.top ?: 0
        val bottomInset = max(
            vc?.window?.imeInsets?.bottom ?: 0,
            vc?.navigationController?.getSystemBars()?.bottom ?: 0
        )

        val minTopSpace = 100.dp
        val bottomPadding = 100.dp

        val rect = Rect()
        view.getDrawingRect(rect)
        offsetDescendantRectToMyCoords(view, rect)

        val visibleTop = scrollY + topInset + minTopSpace
        val visibleBottom = scrollY + height - bottomInset

        val desiredY = when {
            rect.bottom > visibleBottom ->
                rect.bottom - height + bottomInset + bottomPadding

            rect.top < visibleTop ->
                rect.top - topInset - minTopSpace

            else -> null
        }

        desiredY?.let { target ->
            val maxScroll = max(0, (getChildAt(0)?.height ?: 0) - height)
            post { smoothScrollTo(0, target.coerceIn(0, maxScroll)) }
        }
    }

}
