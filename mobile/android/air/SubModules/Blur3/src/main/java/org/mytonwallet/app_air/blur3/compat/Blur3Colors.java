package org.mytonwallet.app_air.blur3.compat;

import android.graphics.Color;

import androidx.core.graphics.ColorUtils;
import androidx.core.math.MathUtils;

/** Blur3 port: replaces Telegram's {@code Theme.multAlpha} and {@code AndroidUtilities.computePerceivedBrightness}. */
public final class Blur3Colors {

    private Blur3Colors() {}

    public static int multAlpha(int color, float multiply) {
        if (multiply == 1f) {
            return color;
        }
        return ColorUtils.setAlphaComponent(color, MathUtils.clamp((int) (Color.alpha(color) * multiply), 0, 0xFF));
    }

    public static float computePerceivedBrightness(int color) {
        return (Color.red(color) * 0.2126f + Color.green(color) * 0.7152f + Color.blue(color) * 0.0722f) / 255f;
    }
}
