package org.mytonwallet.n.utils;

import android.graphics.Bitmap;

public class NativeUtilities {
    public static native void generateGradient(Bitmap bitmap, boolean unpin, int phase, float progress, int width, int height, int stride, int[] colors);
}
