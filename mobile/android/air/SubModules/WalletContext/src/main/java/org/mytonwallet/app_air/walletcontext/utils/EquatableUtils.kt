package org.mytonwallet.app_air.walletcontext.utils

interface WEquatable<T> {
    fun isSame(comparing: WEquatable<*>): Boolean
    fun isChanged(comparing: WEquatable<*>): Boolean
}

// IndexPath to represent the position in section
data class IndexPath(val section: Int, val row: Int)
