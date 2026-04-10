package org.mytonwallet.n.utils;

import android.graphics.Bitmap;
import android.graphics.Canvas;

public class NativeUtilities {
    private static native void generateGradientNative(Bitmap bitmap, boolean unpin, int phase, float progress, int width, int height, int stride, int[] colors);

    public static void generateGradient(Bitmap bitmap, boolean unpin, int phase, float progress, int width, int height, int stride, int[] colors) {
        try {
            generateGradientNative(bitmap, unpin, phase, progress, width, height, stride, colors);
        } catch (Throwable e) {
            if (bitmap != null && colors != null && colors.length > 0) {
                new Canvas(bitmap).drawColor(colors[0]);
            }
        }
    }
}
