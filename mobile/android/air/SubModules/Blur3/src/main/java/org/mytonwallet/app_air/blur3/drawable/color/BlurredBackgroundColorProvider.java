package org.mytonwallet.app_air.blur3.drawable.color;

import androidx.annotation.ColorInt;

public interface BlurredBackgroundColorProvider {
    @ColorInt int getShadowColor();
    @ColorInt int getBackgroundColor();
    @ColorInt int getStrokeColorTop();
    @ColorInt int getStrokeColorBottom();
}
