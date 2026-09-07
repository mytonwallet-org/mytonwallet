package org.mytonwallet.app_air.blur3.compat;

import android.os.Build;

import androidx.annotation.ChecksSdkIntAtLeast;

import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage;

/**
 * Blur3 port: replaces Telegram's {@code LiteMode.FLAG_CHAT_BLUR / FLAG_LIQUID_GLASS} and
 * {@code SharedConfig.chatBlurEnabled()} with the app's blur and liquid-glass switches.
 * <p>
 * Render-node blur needs API 31; the refraction shader needs API 33. Below 31 glass surfaces
 * blur through a software bitmap capture instead, and refraction is unavailable.
 */
public final class Blur3Settings {

    private Blur3Settings() {}

    @ChecksSdkIntAtLeast(api = Build.VERSION_CODES.S)
    public static boolean isRenderNodeGlassAvailable() {
        return Build.VERSION.SDK_INT >= Build.VERSION_CODES.S;
    }

    @ChecksSdkIntAtLeast(api = Build.VERSION_CODES.TIRAMISU)
    public static boolean isLiquidGlassAvailable() {
        return Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU;
    }

    public static boolean isBlurEnabled() {
        return WGlobalStorage.INSTANCE.isBlurEnabled();
    }

    public static boolean isLiquidGlassEnabled() {
        return isLiquidGlassAvailable() && isBlurEnabled() && WGlobalStorage.INSTANCE.isLiquidGlassEnabled();
    }
}
