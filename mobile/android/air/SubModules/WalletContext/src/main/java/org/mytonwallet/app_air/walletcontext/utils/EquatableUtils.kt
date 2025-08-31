package org.mytonwallet.app_air.walletcontext.utils

// Define the WEquatable interface with a method for checking if an item has changed
interface WEquatable<T> {
    fun isSame(comparing: WEquatable<*>): Boolean
    fun isChanged(comparing: WEquatable<*>): Boolean
}

// Define the EquatableChange sealed class with three types: Insert, Delete, and Update
sealed class EquatableChange<T> {
    data class Insert<T>(val item: T) : EquatableChange<T>()
    data class Delete<T>(val item: T) : EquatableChange<T>()
    data class Update<T>(val item: T) : EquatableChange<T>()
}

// Extension function for List<WEquatable> to compute the differences
fun List<WEquatable<*>>.diff(
    newList: List<WEquatable<*>>,
    section: Int = 0
): List<EquatableChange<IndexPath>> {
    val changes = mutableListOf<EquatableChange<IndexPath>>()

    // Find deletions
    for ((index, element) in this.withIndex()) {
        if (newList.find { element.isSame(it) } == null) {
            changes.add(EquatableChange.Delete(IndexPath(index, section)))
        }
    }

    // Find insertions and updates
    for ((index, element) in newList.withIndex()) {
        val oldIndex = indexOfFirst { element.isSame(it) }
        if (oldIndex != -1) {
            if (index != oldIndex || element.isChanged(comparing = this[oldIndex])) {
                // If the element exists in both lists but has moved or changed, consider it as an update
                changes.add(EquatableChange.Update(IndexPath(oldIndex, section)))
            }
        } else {
            // If the element exists only in the new list, consider it as an insertion
            changes.add(EquatableChange.Insert(IndexPath(index, section)))
        }
    }

    return changes
}

// IndexPath to represent the position in section
data class IndexPath(val section: Int, val row: Int)
