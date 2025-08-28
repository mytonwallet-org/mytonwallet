package org.mytonwallet.app_air.walletcontext.utils

import android.graphics.Color

class AnimUtils {
    companion object {
        fun lerp(a: Float, b: Float, f: Float): Float {
            return a + f * (b - a)
        }

        fun getOffsetColor(color1: Int, color2: Int, offset: Float, alpha: Float): Int {
            val rF = Color.red(color2)
            val gF = Color.green(color2)
            val bF = Color.blue(color2)
            val aF = Color.alpha(color2)
            val rS = Color.red(color1)
            val gS = Color.green(color1)
            val bS = Color.blue(color1)
            val aS = Color.alpha(color1)
            return Color.argb(
                ((aS + (aF - aS) * offset) * alpha).toInt(),
                (rS + (rF - rS) * offset).toInt(),
                (gS + (gF - gS) * offset).toInt(),
                (bS + (bF - bS) * offset).toInt()
            )
        }
    }
}