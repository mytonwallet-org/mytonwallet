package org.mytonwallet.app_air.uicomponents.helpers

import android.graphics.Rect
import android.view.View
import org.mytonwallet.app_air.uicomponents.AnimationConstants
import org.mytonwallet.app_air.uicomponents.base.IChromeOverlapHost
import org.mytonwallet.app_air.uicomponents.base.WNavigationController
import org.mytonwallet.app_air.uicomponents.widgets.fadeIn
import org.mytonwallet.app_air.uicomponents.widgets.fadeOut

/**
 * Fades out the bars over [windowRect], [view]'s frame by default: its ancestors', its screen's, the tab bar's and
 * [extraHosts]'. Returns the callback that brings them back, which runs once, or null when none was hidden
 */
fun hideChromeOverlapping(
    view: View,
    navigationController: WNavigationController?,
    windowRect: Rect = IntArray(2).also(view::getLocationInWindow).let {
        Rect(it[0], it[1], it[0] + view.width, it[1] + view.height)
    },
    extraHosts: List<IChromeOverlapHost> = emptyList()
): (() -> Unit)? {
    val hosts = mutableListOf<IChromeOverlapHost>()
    var parent = view.parent
    while (parent != null) {
        if (parent is IChromeOverlapHost) hosts += parent
        parent = parent.parent
    }
    navigationController?.viewControllers?.lastOrNull()?.let { hosts += it }
    navigationController?.tabBarController?.let { hosts += it }
    hosts += extraHosts
    val hidingHosts = hosts.filter { it.hideChromeOverlapping(windowRect) }
    if (hidingHosts.isEmpty()) return null
    var isShown = false
    return {
        if (!isShown) {
            isShown = true
            hidingHosts.forEach { it.showOverlappedChrome() }
        }
    }
}

/** Fades bars out while a window rect overlaps them, then back to the alpha each had */
class OverlappedChromeFader {
    private val hiddenAlphas = mutableMapOf<View, Float>()

    /** Fades out [views] when one of [overlapFrames] intersects [windowRect]; returns whether they are hidden */
    fun hideIfOverlapping(windowRect: Rect, overlapFrames: List<Rect>, views: List<View>): Boolean {
        if (hiddenAlphas.isNotEmpty()) return true
        if (overlapFrames.none { Rect.intersects(it, windowRect) }) return false
        for (view in views) {
            if (!view.isShown || view.alpha == 0f) continue
            hiddenAlphas[view] = view.alpha
            view.animate().cancel()
            view.fadeOut(AnimationConstants.QUICK_ANIMATION / 2)
        }
        return hiddenAlphas.isNotEmpty()
    }

    fun show() {
        for ((view, alpha) in hiddenAlphas) {
            view.animate().cancel()
            view.fadeIn(AnimationConstants.QUICK_ANIMATION / 2, targetAlpha = alpha)
        }
        hiddenAlphas.clear()
    }
}

/** The frame of this view in the window, without [topInset] and [bottomInset]; null while it doesn't show */
fun View.frameInWindow(topInset: Int = 0, bottomInset: Int = 0): Rect? {
    if (!isShown || alpha == 0f || width == 0 || height <= topInset + bottomInset) return null
    val location = IntArray(2).also(::getLocationInWindow)
    return Rect(
        location[0],
        location[1] + topInset,
        location[0] + width,
        location[1] + height - bottomInset
    )
}
