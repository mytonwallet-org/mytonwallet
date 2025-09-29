package org.mytonwallet.app_air.widgets.utils

import org.mytonwallet.app_air.walletbasecontext.utils.ApplicationContextHolder
import kotlin.math.roundToInt

val Int.dp get() = (this * ApplicationContextHolder.density).roundToInt()
val Float.dp get() = this * ApplicationContextHolder.density
