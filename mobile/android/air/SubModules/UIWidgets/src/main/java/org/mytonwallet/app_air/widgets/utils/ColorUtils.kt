package org.mytonwallet.app_air.widgets.utils

import android.graphics.Color
import androidx.core.graphics.alpha

fun Int.colorWithAlpha(alpha: Int): Int {
    return Color.argb(
        alpha * this.alpha / 255,
        Color.red(this),
        Color.green(this),
        Color.blue(this)
    );
}
