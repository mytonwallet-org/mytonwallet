package org.mytonwallet.app_air.uicomponents.widgets.menu

import android.content.Context
import android.graphics.Rect
import androidx.core.graphics.Insets
import androidx.core.view.children
import org.mytonwallet.app_air.uicomponents.base.WWindow
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.helpers.PopupHelpers
import org.mytonwallet.app_air.uicomponents.widgets.WFrameLayout
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.uicomponents.widgets.WView
import java.lang.ref.WeakReference

class WPopupHost(context: Context) : WFrameLayout(context), WThemedView {

    private val safeAreaBounds: Rect = Rect()
    private var windowRef: WeakReference<WWindow>? = null
    val windowView: WView? get() = windowRef?.get()?.windowView

    fun attachWindow(window: WWindow) {
        windowRef = WeakReference(window)
        PopupHelpers.attachPopupHost(this)
    }

    fun getContentAreaBounds(): Rect {
        val extraPadding = 8.dp
        val insets = windowRef?.get()?.systemBars ?: Insets.NONE
        return Rect(
            insets.left + extraPadding,
            insets.top + extraPadding,
            measuredWidth - (insets.right + extraPadding),
            measuredHeight - (insets.bottom + safeAreaBounds.bottom)
        )
    }

    override fun updateTheme() {
        children.filterIsInstance<WThemedView>().forEach { it.updateTheme() }
    }
}
