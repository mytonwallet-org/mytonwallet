package org.mytonwallet.app_air.uicomponents.helpers

import android.os.SystemClock
import android.view.MotionEvent
import java.lang.ref.WeakReference
import org.mytonwallet.app_air.uicomponents.widgets.IPopup
import org.mytonwallet.app_air.uicomponents.widgets.menu.WNavigationPopup
import org.mytonwallet.app_air.uicomponents.widgets.menu.WPopupHost

object PopupHelpers {

    private val popups = ArrayList<WeakReference<IPopup>>()
    private var popupHostRef: WeakReference<WPopupHost>? = null
    val popupHost: WPopupHost? get() = popupHostRef?.get()

    /** Whether a popup, such as a menu or a dialog, is over the window */
    val isPopupShown: Boolean
        get() = popups.any { it.get() != null }

    private var isTouchDown = false
    private var touchDownTime = 0L
    private var touchPointerId = 0
    private var lastTouchY = 0f
    private var dragSelectionPopupRef: WeakReference<WNavigationPopup>? = null

    val isDragSelecting: Boolean
        get() = dragSelectionPopupRef?.get() != null

    fun attachPopupHost(popupHost: WPopupHost) {
        this.popupHostRef = WeakReference(popupHost)
    }

    fun popupShown(popup: IPopup) {
        popups.add(WeakReference(popup))
        if (isTouchDown && popup is WNavigationPopup) {
            dragSelectionPopupRef?.get()?.takeIf { it !== popup }
                ?.endDragSelection(performAction = false)
            dragSelectionPopupRef = WeakReference(popup)
            popup.beginDragSelection(lastTouchY)
            cancelContentTouch()
        }
    }

    // The menu takes the rest of the touch, so the pressed view would never get its up
    private fun cancelContentTouch() {
        val root = popupHost?.rootView ?: return
        val now = SystemClock.uptimeMillis()
        val cancelEvent = MotionEvent.obtain(now, now, MotionEvent.ACTION_CANCEL, 0f, 0f, 0)
        root.dispatchTouchEvent(cancelEvent)
        cancelEvent.recycle()
    }

    fun popupDismissed(popup: IPopup) {
        popups.removeAll {
            it.get() == popup
        }
        if (dragSelectionPopupRef?.get() === popup) dragSelectionPopupRef = null
    }

    fun dispatchDragSelectionTouch(event: MotionEvent): Boolean {
        when (event.actionMasked) {
            MotionEvent.ACTION_DOWN -> {
                isTouchDown = true
                touchDownTime = event.downTime
                touchPointerId = event.getPointerId(0)
                lastTouchY = event.y
                dragSelectionPopupRef?.get()?.endDragSelection(performAction = false)
                dragSelectionPopupRef = null
                return false
            }

            MotionEvent.ACTION_UP -> isTouchDown = false

            MotionEvent.ACTION_CANCEL -> {
                // A synthetic cancel, as from `cancelAncestorTouches`, leaves the finger down
                if (event.downTime != touchDownTime) return false
                isTouchDown = false
            }
        }
        val pointerIndex = event.findPointerIndex(touchPointerId)
        val popup = dragSelectionPopupRef?.get()
        if (popup == null) {
            if (pointerIndex >= 0) lastTouchY = event.getY(pointerIndex)
            return false
        }
        when (event.actionMasked) {
            MotionEvent.ACTION_MOVE -> if (pointerIndex >= 0) {
                popup.updateDragSelection(event.getX(pointerIndex), event.getY(pointerIndex))
            }

            MotionEvent.ACTION_POINTER_UP -> {
                if (event.getPointerId(event.actionIndex) != touchPointerId) return true
                isTouchDown = false
                dragSelectionPopupRef = null
                popup.endDragSelection(performAction = false)
            }

            MotionEvent.ACTION_UP -> {
                dragSelectionPopupRef = null
                popup.updateDragSelection(event.getX(pointerIndex), event.getY(pointerIndex))
                popup.endDragSelection(performAction = true)
            }

            MotionEvent.ACTION_CANCEL -> {
                dragSelectionPopupRef = null
                popup.endDragSelection(performAction = false)
            }
        }
        return true
    }

    fun dismissAllPopups() {
        popups.toList().forEach {
            it.get()?.dismiss()
        }
    }

    fun dismissMenuPopups() {
        popups.toList().forEach {
            (it.get() as? WNavigationPopup)?.dismiss()
        }
    }

    fun onBackPressed(): Boolean {
        if (popups.isEmpty()) return false
        popups.lastOrNull()?.get()?.onBackPressed() ?: return false
        return true
    }
}
