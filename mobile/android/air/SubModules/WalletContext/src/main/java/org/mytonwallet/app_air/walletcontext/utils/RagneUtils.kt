package org.mytonwallet.app_air.walletcontext.utils

fun IntRange.shift(offset: Int): IntRange = IntRange(this.first + offset, this.last + offset)
