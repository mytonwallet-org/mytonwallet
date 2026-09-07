package org.mytonwallet.app_air.blur3.compat;

import android.graphics.Paint;

import androidx.annotation.Nullable;

import org.mytonwallet.app_air.walletbasecontext.theme.ThemeManager;
import org.mytonwallet.app_air.walletbasecontext.theme.WColor;

/**
 * Blur3 port: replaces Telegram's {@code Theme} for the two things blur3 needs from it,
 * a keyed color lookup and the dark-theme flag.
 * <p>
 * Color keys are {@link WColor#ordinal()} values, so callers pass {@code WColor.X.ordinal()}
 * where Telegram passed {@code Theme.key_x}.
 */
public final class Blur3Theme {

    private Blur3Theme() {}

    public interface ResourcesProvider {
        int getColor(int key);

        boolean isDark();
    }

    public static int key(WColor color) {
        return color.ordinal();
    }

    public static int getColor(int key, @Nullable ResourcesProvider resourcesProvider) {
        if (resourcesProvider != null) {
            return resourcesProvider.getColor(key);
        }
        return getColor(key);
    }

    public static int getColor(int key) {
        return ThemeManager.INSTANCE.getColor(WColor.values()[key]);
    }

    public static boolean isCurrentThemeDark() {
        return ThemeManager.INSTANCE.isDark();
    }

    public static final Paint DEBUG_GREEN_STROKE = new Paint();

    static {
        DEBUG_GREEN_STROKE.setColor(0xff00ff00);
        DEBUG_GREEN_STROKE.setStrokeWidth(2);
        DEBUG_GREEN_STROKE.setStyle(Paint.Style.STROKE);
    }
}
