package org.mytonwallet.app_air.uicomponents.widgets;

import android.annotation.SuppressLint;
import android.content.Context;
import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.LinearGradient;
import android.graphics.Paint;
import android.graphics.PorterDuff;
import android.graphics.PorterDuffXfermode;
import android.graphics.Rect;
import android.graphics.Shader;
import android.widget.FrameLayout;

import androidx.annotation.NonNull;

@SuppressLint("ViewConstructor")
public class AlphaGradientLayout extends FrameLayout {

    private static final int DIRTY_FLAG_TOP = 1;

    private static final int[] FADE_COLORS = new int[]{Color.TRANSPARENT, Color.BLACK};

    private final boolean fadeTop = true;
    private int gradientSizeTop;
    private Paint gradientPaintTop;
    private Rect gradientRectTop;
    private int gradientDirtyFlags;

    public AlphaGradientLayout(Context context, int gradientSizeTop) {
        super(context);
        init(gradientSizeTop);
    }

    private void init(int gradientSizeTop) {
        this.gradientSizeTop = gradientSizeTop;

        PorterDuffXfermode mode = new PorterDuffXfermode(PorterDuff.Mode.DST_IN);
        gradientPaintTop = new Paint(Paint.ANTI_ALIAS_FLAG);
        gradientPaintTop.setXfermode(mode);

        gradientRectTop = new Rect();
    }

    @Override
    public void setPadding(int left, int top, int right, int bottom) {
        if (getPaddingTop() != top) {
            gradientDirtyFlags |= DIRTY_FLAG_TOP;
        }
        super.setPadding(left, top, right, bottom);
    }

    @Override
    protected void onSizeChanged(int w, int h, int oldw, int oldh) {
        super.onSizeChanged(w, h, oldw, oldh);
        if (h != oldh) {
            gradientDirtyFlags |= DIRTY_FLAG_TOP;
        }
    }

    @Override
    protected void dispatchDraw(@NonNull Canvas canvas) {
        int newWidth = getWidth(), newHeight = getHeight();
        boolean fadeAnyEdge = fadeTop;
        if (getVisibility() == GONE || newWidth == 0 || newHeight == 0 || !fadeAnyEdge) {
            super.dispatchDraw(canvas);
            return;
        }

        if ((gradientDirtyFlags & DIRTY_FLAG_TOP) == DIRTY_FLAG_TOP) {
            gradientDirtyFlags &= ~DIRTY_FLAG_TOP;

            int actualHeight = getHeight() - getPaddingTop() - getPaddingBottom();
            int size = Math.min(gradientSizeTop, actualHeight);
            int l = getPaddingLeft();
            int t = getPaddingTop();
            int r = getWidth() - getPaddingRight();
            int b = t + size;
            gradientRectTop.set(l, t, r, b);
            LinearGradient gradient = new LinearGradient(l, t, l, b, FADE_COLORS, null, Shader.TileMode.CLAMP);
            gradientPaintTop.setShader(gradient);
        }

        int count = canvas.saveLayer(0.0f, 0.0f, (float) getWidth(), (float) getHeight(), null, Canvas.ALL_SAVE_FLAG);
        super.dispatchDraw(canvas);
        if (fadeTop && gradientSizeTop > 0) {
            canvas.drawRect(gradientRectTop, gradientPaintTop);
        }
        canvas.restoreToCount(count);
    }
}
