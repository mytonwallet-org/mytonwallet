package org.mytonwallet.app_air.uicomponents.helpers

import android.view.View
import java.util.WeakHashMap

/**
 * Subtrees being revealed by a transition. Content updates inside them wait until the transition
 * ends, and only the latest update per key is applied then.
 */
object RevealUpdates {
    private val held = WeakHashMap<View, LinkedHashMap<Any, () -> Unit>>()

    fun hold(root: View) {
        held.getOrPut(root) { LinkedHashMap() }
    }

    fun release(root: View) {
        held.remove(root)?.values?.forEach { it() }
    }

    fun isHeld(view: View): Boolean = heldUpdates(view) != null

    inline fun runOrHold(view: View, key: Any, crossinline update: () -> Unit) {
        val updates = heldUpdates(view)
        if (updates == null) {
            update()
            return
        }
        updates.remove(key)
        updates[key] = { update() }
    }

    @PublishedApi
    internal fun heldUpdates(view: View): LinkedHashMap<Any, () -> Unit>? {
        if (held.isEmpty()) return null
        var current: View? = view
        while (current != null) {
            held[current]?.let { return it }
            current = current.parent as? View
        }
        return null
    }
}
