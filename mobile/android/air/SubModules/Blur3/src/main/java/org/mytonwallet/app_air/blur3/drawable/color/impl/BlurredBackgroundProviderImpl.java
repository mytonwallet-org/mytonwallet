package org.mytonwallet.app_air.blur3.drawable.color.impl;

import static org.mytonwallet.app_air.blur3.compat.Blur3Dp.dpf2;

import android.graphics.Color;

import androidx.core.graphics.ColorUtils;
import androidx.core.math.MathUtils;

import org.mytonwallet.app_air.blur3.compat.Blur3Colors;
import org.mytonwallet.app_air.blur3.compat.Blur3Settings;
import org.mytonwallet.app_air.blur3.compat.Blur3Theme;
import org.mytonwallet.app_air.blur3.drawable.color.BlurredBackgroundProvider;
import org.mytonwallet.app_air.blur3.drawable.color.BlurredBackgroundProviderBuilder;

/**
 * Blur3 port: Telegram ships ~20 screen-specific presets here keyed by its own theme keys. Only
 * the two panel presets and the shadow-only preset are generic; they take the background color
 * key instead of hard-coding one. App-level presets live in the UI layer.
 */
public class BlurredBackgroundProviderImpl {

    /** Telegram's {@code bottomPanelChatActivity}: the composer / input pill. */
    public static BlurredBackgroundProvider bottomPanel(Blur3Theme.ResourcesProvider resourcesProvider, int backgroundKey) {
        return new BlurredBackgroundProviderBuilder(resourcesProvider)
                .setBackgroundColor((r, isDark) -> {
                    if (!checkBlurEnabled(resourcesProvider)) {
                        return ColorUtils.setAlphaComponent(Blur3Theme.getColor(backgroundKey, r), 255);
                    }

                    final float alpha = Blur3Settings.isLiquidGlassEnabled() ? 0.85f : 0.76f;
                    final int colorBg = Blur3Theme.getColor(backgroundKey, r);
                    return Blur3Colors.multAlpha(colorBg, alpha);
                })
                .setStrokeColorTop(0xFFFFFFFF, 0x28FFFFFF)
                .setStrokeColorBottom(0xFFFFFFFF, 0x14FFFFFF)
                .setShadowColor(0x20000000, 0)
                .setStrokeWidth(dpf2(0.5f), dpf2(0.5f))
                .build();
    }

    /** Telegram's {@code topPanelChatActivity}: the action-bar pills. */
    public static BlurredBackgroundProvider topPanel(Blur3Theme.ResourcesProvider resourcesProvider, int backgroundKey) {
        return new BlurredBackgroundProviderBuilder(resourcesProvider)
                .setBackgroundColor((r, isDark) -> {
                    if (!checkBlurEnabled(resourcesProvider)) {
                        return ColorUtils.setAlphaComponent(Blur3Theme.getColor(backgroundKey, r), 255);
                    }

                    final float alpha = Blur3Settings.isLiquidGlassEnabled() ? 0.85f : 0.76f;
                    final int colorBg = Blur3Theme.getColor(backgroundKey, r);
                    return Blur3Colors.multAlpha(colorBg, alpha);
                })
                .setStrokeColorTop(0xFFFFFFFF, 0x20FFFFFF)
                .setStrokeColorBottom(0xFFFFFFFF, 0x14FFFFFF)
                .setShadowColor(0x20000000, 0)
                .setStrokeWidth(dpf2(0.55f), dpf2(0.55f))
                .build();
    }

    /** Telegram's {@code shadow}: no fill, rim and shadow only. */
    public static BlurredBackgroundProvider shadow(Blur3Theme.ResourcesProvider resourcesProvider) {
        return new BlurredBackgroundProviderBuilder(resourcesProvider)
            .setStrokeColorTop(0, 0x28FFFFFF)
            .setStrokeColorBottom(0, 0x14FFFFFF)
            .setShadowColor(0x30000000, 0x04FFFFFF)
            .setShadowLayer(dpf2(12 / 3f), 0, dpf2(1 / 3f))
            .setStrokeWidth(dpf2(0.4f), dpf2(0.4f))
            .build();
    }

    public static int solveSrcColor(int bgColor, int outColor, float alpha) {
        alpha = MathUtils.clamp(alpha, 0, 1);

        // Edge cases
        if (alpha <= 0f) {
            return Color.argb(0, 0, 0, 0);
        }
        if (alpha >= 1f) {
            return Color.argb(255, Color.red(outColor), Color.green(outColor), Color.blue(outColor));
        }

        final int bgR = Color.red(bgColor);
        final int bgG = Color.green(bgColor);
        final int bgB = Color.blue(bgColor);

        final int outR = Color.red(outColor);
        final int outG = Color.green(outColor);
        final int outB = Color.blue(outColor);

        final float invA = 1f - alpha;

        final int srcR = MathUtils.clamp(Math.round((outR - bgR * invA) / alpha), 0, 255);
        final int srcG = MathUtils.clamp(Math.round((outG - bgG * invA) / alpha), 0, 255);
        final int srcB = MathUtils.clamp(Math.round((outB - bgB * invA) / alpha), 0, 255);

        final int a8 = MathUtils.clamp(Math.round(alpha * 255f), 0, 255);

        return Color.argb(a8, srcR, srcG, srcB);
    }

    public static boolean checkBlurEnabled(Blur3Theme.ResourcesProvider resourcesProvider) {
        return Blur3Settings.isBlurEnabled();
    }
}
