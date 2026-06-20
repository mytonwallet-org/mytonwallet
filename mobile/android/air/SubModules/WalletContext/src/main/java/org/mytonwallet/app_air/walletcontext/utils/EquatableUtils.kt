package org.mytonwallet.app_air.walletcontext.utils

interface WEquatable<T> {
    fun isSame(comparing: WEquatable<*>): Boolean
    fun isChanged(comparing: WEquatable<*>): Boolean
}

// IndexPath to represent the position in section
data class IndexPath(val section: Int, val row: Int)

fun List<WEquatable<*>>.isChanged(comparing: List<WEquatable<*>>?): Boolean {
    if (comparing == null)
        return true
    if (size != comparing.size)
        return true
    return indices.any { i ->
        !this[i].isSame(comparing[i]) || this[i].isChanged(comparing[i])
    }
}
