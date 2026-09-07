package org.mytonwallet.app_air.blur3.drawable.color;

import androidx.core.graphics.ColorUtils;

import org.mytonwallet.app_air.blur3.compat.Blur3Colors;
import org.mytonwallet.app_air.blur3.compat.Blur3Resources;
import org.mytonwallet.app_air.blur3.compat.Blur3Settings;
import org.mytonwallet.app_air.blur3.compat.Blur3Colors;
import org.mytonwallet.app_air.blur3.compat.Blur3Theme;

public class BlurredBackgroundColorProviderThemed implements BlurredBackgroundColorProvider {

    private final Blur3Theme.ResourcesProvider resourcesProvider;
    private final int backgroundColorId;
    private float alpha;

    public BlurredBackgroundColorProviderThemed(Blur3Theme.ResourcesProvider resourcesProvider, int backgroundColorId) {
        this(resourcesProvider, backgroundColorId, Blur3Settings.isLiquidGlassEnabled() ? 0.85f : 0.76f);
    }

    public BlurredBackgroundColorProviderThemed(Blur3Theme.ResourcesProvider resourcesProvider, int backgroundColorId, float alpha) {
        this.resourcesProvider = resourcesProvider;
        this.backgroundColorId = backgroundColorId;
        this.alpha = alpha;

        updateColors();
    }

    public void setAlpha(float alpha) {
        this.alpha = alpha;
        updateColors();
    }

    private int backgroundColor, shadowColor, strokeColorTop, strokeColorBottom;

    public boolean isDark() {
        final int color = Blur3Theme.getColor(backgroundColorId, resourcesProvider);
        return Blur3Colors.computePerceivedBrightness(color) < .721f;
    }

    public void updateColors() {
        final int color = Blur3Theme.getColor(backgroundColorId, resourcesProvider);
        backgroundColor = Blur3Colors.multAlpha(color, alpha);

        if (isDark()) {
            strokeColorTop = 0x28FFFFFF;
            strokeColorBottom = 0x14FFFFFF;
            shadowColor = 0;
        } else {
            strokeColorTop = 0xFFFFFFFF;
            strokeColorBottom = 0xFFFFFFFF;
            shadowColor = 0x20000000; //0x19000000;
        }
    }

    @Override
    public int getShadowColor() {
        return shadowColor;
    }

    @Override
    public int getBackgroundColor() {
        return backgroundColor;
    }

    @Override
    public int getStrokeColorTop() {
        return strokeColorTop;
    }

    @Override
    public int getStrokeColorBottom() {
        return strokeColorBottom;
    }
}

