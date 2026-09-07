package org.mytonwallet.app_air.blur3.compat;

import org.mytonwallet.app_air.walletbasecontext.utils.ApplicationContextHolder;

/** Blur3 port: replaces Telegram's {@code AndroidUtilities.dp / dpf2 / lerp}. */
public final class Blur3Dp {

    private Blur3Dp() {}

    private static float density() {
        return ApplicationContextHolder.INSTANCE.getDensity();
    }

    public static int dp(float value) {
        if (value == 0) {
            return 0;
        }
        return (int) Math.ceil(density() * value);
    }

    public static float dpf2(float value) {
        if (value == 0) {
            return 0;
        }
        return density() * value;
    }

    public static int lerp(int a, int b, float f) {
        return (int) (a + f * (b - a));
    }
}
