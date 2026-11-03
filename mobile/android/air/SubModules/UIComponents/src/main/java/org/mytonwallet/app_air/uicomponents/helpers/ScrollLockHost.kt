package org.mytonwallet.app_air.uicomponents.helpers

/** A recognized hold owns scrolling until the returned release is called. */
interface ScrollLockHost {
    fun acquireScrollLock(): (() -> Unit)?
}
