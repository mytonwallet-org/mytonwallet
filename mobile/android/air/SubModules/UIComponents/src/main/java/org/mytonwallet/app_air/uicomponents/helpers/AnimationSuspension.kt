package org.mytonwallet.app_air.uicomponents.helpers

import android.view.View
import java.util.Collections
import java.util.WeakHashMap

/**
 * Subtrees whose content changes take their final state at once instead of animating, for
 * screens that are not visible yet or are being revealed by a transition of their own.
 */
object AnimationSuspension {
    private val roots = Collections.newSetFromMap(WeakHashMap<View, Boolean>())

    fun suspend(root: View) {
        roots.add(root)
    }

    fun resume(root: View) {
        roots.remove(root)
    }

    fun covers(view: View): Boolean {
        if (roots.isEmpty()) return false
        var current: View? = view
        while (current != null) {
            if (current in roots) return true
            current = current.parent as? View
        }
        return false
    }
}
