package org.mytonwallet.app_air.uicomponents.base

import android.graphics.Rect

/** Hosts bars floating over content, which a menu lifting a cell through a cutout of the window reveals */
interface IChromeOverlapHost {
    /** Fades out the bars floating over [windowRect] until [showOverlappedChrome]; returns whether any was hidden */
    fun hideChromeOverlapping(windowRect: Rect): Boolean = false
    fun showOverlappedChrome() {}
}
