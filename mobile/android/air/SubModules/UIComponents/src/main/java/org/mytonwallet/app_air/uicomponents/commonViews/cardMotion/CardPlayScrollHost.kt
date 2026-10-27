package org.mytonwallet.app_air.uicomponents.commonViews.cardMotion

/** A recognized card hold owns scrolling until the returned release is called. */
interface CardPlayScrollHost {
    fun acquireCardPlayScrollLock(): (() -> Unit)?
}
