package org.mytonwallet.app_air.walletbasecontext.utils

typealias Vec2i = IntArray

fun vec2i(x: Int = 0, y: Int = 0): Vec2i = intArrayOf(x, y)

var IntArray.x: Int
    get() = this[0]
    set(value) {
        this[0] = value
    }

var IntArray.y: Int
    get() = this[1]
    set(value) {
        this[1] = value
    }
