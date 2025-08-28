package org.mytonwallet.app_air.uicomponents.extensions

import org.mytonwallet.app_air.walletcontext.helpers.ApplicationContextHolder
import kotlin.math.roundToInt

val Int.dp get() = (this * ApplicationContextHolder.density).roundToInt()
val Float.dp get() = this * ApplicationContextHolder.density
