package org.mytonwallet.app_air.blur3.source;

import android.graphics.Canvas;

import org.mytonwallet.app_air.blur3.drawable.BlurredBackgroundDrawable;

public interface BlurredBackgroundSource {
    BlurredBackgroundDrawable createDrawable();

    void draw(Canvas canvas, float left, float top, float right, float bottom);


    default void dispatchOnDrawablesRelativePositionChange() {}
}
