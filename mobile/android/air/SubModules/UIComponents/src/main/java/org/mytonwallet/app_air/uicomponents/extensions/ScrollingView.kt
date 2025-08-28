package org.mytonwallet.app_air.uicomponents.extensions

import androidx.core.view.ScrollingView

val ScrollingView.isTopScrollReached: Boolean
    get() {
        return computeVerticalScrollOffset() == 0
    }

val ScrollingView.isBottomScrollReached: Boolean
    get() {
        val maxScroll = computeVerticalScrollRange()
        val currentScroll = computeVerticalScrollOffset() + computeVerticalScrollExtent()
        return currentScroll >= maxScroll
    }
