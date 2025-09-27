package org.mytonwallet.app_air.uicomponents.helpers

import android.graphics.Rect
import android.view.View
import androidx.recyclerview.widget.RecyclerView
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController

class PositionBasedItemDecoration(
    private val spacingProvider: (position: Int) -> Rect
) : RecyclerView.ItemDecoration() {

    override fun getItemOffsets(
        outRect: Rect,
        view: View,
        parent: RecyclerView,
        state: RecyclerView.State
    ) {
        val position = parent.getChildAdapterPosition(view)
        if (position == RecyclerView.NO_POSITION) return

        val spacing = spacingProvider(position)
        outRect.set(
            if (LocaleController.isRTL) spacing.right else spacing.left,
            spacing.top,
            if (LocaleController.isRTL) spacing.left else spacing.right,
            spacing.bottom
        )
    }
}
