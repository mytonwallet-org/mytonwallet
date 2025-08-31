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
class WScrollView(private val viewController: WeakReference<WViewController>) :
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
        val distanceFromBottom = getDistanceFromViewToScrollViewBottom(view)
        val newY = scrollY +
            max(
                (viewController.get()?.window?.imeInsets?.bottom ?: 0),
                (viewController.get()?.navigationController?.getSystemBars()?.bottom ?: 0)
            ) - distanceFromBottom + 100.dp
        if (scrollY < newY) {
            post {
                smoothScrollTo(0, newY)
            }
        }
    }

}
