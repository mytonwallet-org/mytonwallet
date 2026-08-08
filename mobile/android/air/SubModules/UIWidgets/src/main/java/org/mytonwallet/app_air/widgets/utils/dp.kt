@file:Suppress("ktlint:standard:filename")

package org.mytonwallet.app_air.widgets.utils

import kotlin.math.roundToInt
import org.mytonwallet.app_air.walletbasecontext.utils.ApplicationContextHolder

val Int.dp get() = (this * ApplicationContextHolder.density).roundToInt()
val Float.dp get() = this * ApplicationContextHolder.density
