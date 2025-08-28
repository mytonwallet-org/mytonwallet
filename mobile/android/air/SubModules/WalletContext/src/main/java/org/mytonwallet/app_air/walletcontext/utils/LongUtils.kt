package org.mytonwallet.app_air.walletcontext.utils

import java.util.Calendar
import java.util.TimeZone

fun Long.stringForTimestamp(local: Boolean = true): String {
    val calendar = Calendar.getInstance()
    if (local) {
        calendar.timeInMillis = this
    } else {
        calendar.timeZone = TimeZone.getTimeZone("UTC")
        calendar.timeInMillis = this
    }

    val hours = calendar.get(Calendar.HOUR_OF_DAY)
    val minutes = calendar.get(Calendar.MINUTE)

    return stringForShortTimestamp(hours, minutes)
}

fun stringForShortTimestamp(hours: Int, minutes: Int): String {
    val hourString = if (hours < 10) "0$hours" else "$hours"

    return if (minutes >= 10) {
        "$hourString:$minutes"
    } else {
        "$hourString:0$minutes"
    }
}