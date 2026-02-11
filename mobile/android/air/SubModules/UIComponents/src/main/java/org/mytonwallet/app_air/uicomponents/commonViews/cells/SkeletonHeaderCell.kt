package org.mytonwallet.app_air.uicomponents.commonViews.cells

import android.annotation.SuppressLint
import android.content.Context
import android.view.View
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.widgets.WBaseView
import org.mytonwallet.app_air.uicomponents.widgets.WCell
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.uicomponents.widgets.setBackgroundColor
import org.mytonwallet.app_air.walletbasecontext.theme.ViewConstants
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color

@SuppressLint("ViewConstructor")
class SkeletonHeaderCell(
    context: Context,
    private val defaultHeight: Int = 56.dp
) : WCell(context), WThemedView, SkeletonContainer {

    companion object {
        val TITLE_SKELETON_RADIUS = 8f.dp
    }

    private val titleSkeleton = WBaseView(context).apply {
        layoutParams = LayoutParams(160.dp, 16.dp)
    }

    override fun setupViews() {
        super.setupViews()

        layoutParams.height = defaultHeight

        addView(titleSkeleton)
        setConstraints {
            toTop(titleSkeleton, 24f)
            toStart(titleSkeleton, 16f)
        }

        updateTheme()
        setOnClickListener { }
    }

    override fun updateTheme() {
        setBackgroundColor(WColor.Background.color, ViewConstants.BLOCK_RADIUS.dp, 0f)
        titleSkeleton.setBackgroundColor(WColor.SecondaryBackground.color, TITLE_SKELETON_RADIUS)
    }

    override fun getChildViewMap(): HashMap<View, Float> = hashMapOf(
        (titleSkeleton to TITLE_SKELETON_RADIUS)
    )
}
