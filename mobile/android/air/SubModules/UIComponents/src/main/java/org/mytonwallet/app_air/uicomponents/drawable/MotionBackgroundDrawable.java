package org.mytonwallet.app_air.uicomponents.drawable;

import android.annotation.SuppressLint;
import android.graphics.Bitmap;
import android.graphics.BitmapShader;
import android.graphics.BlendMode;
import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.ColorFilter;
import android.graphics.ComposeShader;
import android.graphics.Matrix;
import android.graphics.Paint;
import android.graphics.PixelFormat;
import android.graphics.PorterDuff;
import android.graphics.PorterDuffColorFilter;
import android.graphics.PorterDuffXfermode;
import android.graphics.Rect;
import android.graphics.RectF;
import android.graphics.Shader;
import android.graphics.drawable.Drawable;
import android.graphics.drawable.GradientDrawable;
import android.os.Build;
import android.os.Handler;
import android.os.Looper;
import android.os.SystemClock;
import android.view.View;

import androidx.core.graphics.ColorUtils;

import org.mytonwallet.app_air.uicomponents.helpers.CubicBezierInterpolator;
import org.mytonwallet.n.utils.NativeUtilities;

import java.lang.ref.WeakReference;
import java.util.ArrayList;
import java.util.List;

public class MotionBackgroundDrawable extends Drawable {


    private final static int ANIMATION_CACHE_BITMAPS_COUNT = 3;

    private static final boolean useLegacyBitmap = Build.VERSION.SDK_INT < 28;
    private static final boolean useSoftLight = Build.VERSION.SDK_INT >= 29;
    private static boolean errorWhileGenerateLegacyBitmap = false;
    private static float legacyBitmapScale = 0.7f;

    private int[] colors = new int[]{
        0xff426D57,
        0xffF7E48B,
        0xff87A284,
        0xffFDF6CA
    };

    private long lastUpdateTime;
    private WeakReference<View> parentView;

    private boolean ignoreInterpolator;
    private final CubicBezierInterpolator interpolator = new CubicBezierInterpolator(0.33, 0.0, 0.0, 1.0);

    private int translationY;

    public boolean isPreview;

    public float posAnimationProgress = 1.0f;
    private int phase;

    private RectF rect = new RectF();
    private Bitmap currentBitmap;
    private Bitmap gradientFromBitmap;
    private Bitmap[] gradientToBitmap = new Bitmap[ANIMATION_CACHE_BITMAPS_COUNT];
    private Paint paint = new Paint(Paint.FILTER_BITMAP_FLAG);
    private Paint paint2 = new Paint(Paint.FILTER_BITMAP_FLAG);
    private Paint paint3 = new Paint();
    private int intensity = 100;
    private Canvas gradientCanvas;
    private Canvas gradientFromCanvas;

    private boolean postInvalidateParent;

    private Bitmap patternBitmap;
    private BitmapShader bitmapShader;
    private BitmapShader gradientShader;
    private boolean disableGradientShaderScaling;
    private Matrix matrix;

    private boolean fastAnimation;

    private Canvas legacyCanvas;
    private Bitmap legacyBitmap;
    private Canvas legacyCanvas2;
    private Bitmap legacyBitmap2;
    private GradientDrawable gradientDrawable = new GradientDrawable();
    private boolean invalidateLegacy;

    private GenericProvider<MotionBackgroundDrawable, Float> animationProgressProvider;

    private boolean rotationBack;

    private boolean rotatingPreview;

    private Runnable updateAnimationRunnable = () -> {
        updateAnimation(true);
    };

    private Rect patternBounds = new Rect();

    private ColorFilter patternColorFilter;
    private int roundRadius;
    private float patternAlpha = 1f;
    private float backgroundAlpha = 1f;
    private int alpha = 255;

    private ColorFilter legacyBitmapColorFilter;
    private int legacyBitmapColor;

    private float indeterminateSpeedScale = 1f;
    private boolean isIndeterminateAnimation;
    private Paint overrideBitmapPaint;
    private int bitmapWidth = 60;
    private int bitmapHeight = 80;

    public MotionBackgroundDrawable() {
        super();
        init();
    }

    public MotionBackgroundDrawable(int c1, int c2, int c3, int c4, boolean preview) {
        this(c1, c2, c3, c4, 0, preview);
    }

    public MotionBackgroundDrawable(int c1, int c2, int c3, int c4, int rotation, boolean preview) {
        this(c1, c2, c3, c4, rotation, preview, false);
    }

    public MotionBackgroundDrawable(int c1, int c2, int c3, int c4, int rotation, boolean preview, boolean square) {
        super();
        if (square) {
            bitmapWidth = 80;
            bitmapHeight = 80;
        }
        isPreview = preview;
        setColors(c1, c2, c3, c4, rotation, false);
        init();
    }

    @SuppressLint("NewApi")
    private void init() {
        currentBitmap = Bitmap.createBitmap(bitmapWidth, bitmapHeight, Bitmap.Config.ARGB_8888);
        for (int i = 0; i < ANIMATION_CACHE_BITMAPS_COUNT; i++) {
            gradientToBitmap[i] = Bitmap.createBitmap(bitmapWidth, bitmapHeight, Bitmap.Config.ARGB_8888);
        }
        gradientCanvas = new Canvas(currentBitmap);

        gradientFromBitmap = Bitmap.createBitmap(bitmapWidth, bitmapHeight, Bitmap.Config.ARGB_8888);
        gradientFromCanvas = new Canvas(gradientFromBitmap);

        NativeUtilities.generateGradient(currentBitmap, true, phase, interpolator.getInterpolation(posAnimationProgress), currentBitmap.getWidth(), currentBitmap.getHeight(), currentBitmap.getRowBytes(), colors);
        if (useSoftLight) {
            paint2.setBlendMode(BlendMode.SOFT_LIGHT);
        }
    }

    public void setRoundRadius(int rad) {
        roundRadius = rad;
        matrix = new Matrix();
        bitmapShader = new BitmapShader(currentBitmap, Shader.TileMode.CLAMP, Shader.TileMode.CLAMP);
        paint.setShader(bitmapShader);
        invalidateParent();
    }

    public BitmapShader getBitmapShader() {
        return bitmapShader;
    }

    public Bitmap getBitmap() {
        return currentBitmap;
    }

    public Bitmap getPatternBitmap() {
        return patternBitmap;
    }

    public int getIntensity() {
        return intensity;
    }

    public static boolean isDark(int color1, int color2, int color3, int color4) {
        int averageColor = getAverageColor(color1, color2);
        if (color3 != 0) {
            averageColor = getAverageColor(averageColor, color3);
        }
        if (color4 != 0) {
            averageColor = getAverageColor(averageColor, color4);
        }
        float[] hsb = RGBtoHSB(Color.red(averageColor), Color.green(averageColor), Color.blue(averageColor));
        return hsb[2] < 0.3f;
    }

    @Override
    public void setBounds(Rect bounds) {
        super.setBounds(bounds);
        patternBounds.set(bounds);
    }

    public void setPatternBounds(int left, int top, int right, int bottom) {
        patternBounds.set(left, top, right, bottom);
    }

    public static int getPatternColor(int color1, int color2, int color3, int color4) {
        if (isDark(color1, color2, color3, color4)) {
            return !useSoftLight ? 0x7fffffff : 0xffffffff;
        } else {
            if (!useSoftLight) {
                int averageColor = getAverageColor(color3, getAverageColor(color1, color2));
                if (color4 != 0) {
                    averageColor = getAverageColor(color4, averageColor);
                }
                return (getPatternColor(averageColor, true) & 0x00ffffff) | 0x64000000;
            } else {
                return 0xff000000;
            }
        }
    }

    public int getPatternColor() {
        return getPatternColor(colors[0], colors[1], colors[2], colors[3]);
    }

    public int getPhase() {
        return phase;
    }

    public void setPostInvalidateParent(boolean value) {
        postInvalidateParent = value;
    }

    public void rotatePreview(boolean back) {
        if (posAnimationProgress < 1.0f) {
            return;
        }
        rotatingPreview = true;
        posAnimationProgress = 0.0f;
        rotationBack = back;
        invalidateParent();
    }

    public void setPhase(int value) {
        phase = value;
        if (phase < 0) {
            phase = 0;
        } else if (phase > 7) {
            phase = 7;
        }
        NativeUtilities.generateGradient(currentBitmap, true, phase, interpolator.getInterpolation(posAnimationProgress), currentBitmap.getWidth(), currentBitmap.getHeight(), currentBitmap.getRowBytes(), colors);
    }

    public float getPosAnimationProgress() {
        return posAnimationProgress;
    }

    public void setPosAnimationProgress(float posAnimationProgress) {
        this.posAnimationProgress = posAnimationProgress;
        updateAnimation(true);
    }

    public void switchToNextPosition() {
        switchToNextPosition(false);
    }

    public void switchToNextPosition(boolean fast) {
        if (posAnimationProgress < 1.0f) {
            return;
        }
        rotatingPreview = false;
        rotationBack = false;
        fastAnimation = fast;
        posAnimationProgress = 0.0f;
        phase--;
        if (phase < 0) {
            phase = 7;
        }
        invalidateParent();
        gradientFromCanvas.drawBitmap(currentBitmap, 0, 0, null);
        generateNextGradient();
    }

    public void generateNextGradient() {
        if (useLegacyBitmap && intensity < 0) {
            try {
                if (legacyBitmap != null) {
                    if (legacyBitmap2 == null || legacyBitmap2.getHeight() != legacyBitmap.getHeight() || legacyBitmap2.getWidth() != legacyBitmap.getWidth()) {
                        if (legacyBitmap2 != null) {
                            legacyBitmap2.recycle();
                        }
                        legacyBitmap2 = Bitmap.createBitmap(legacyBitmap.getWidth(), legacyBitmap.getHeight(), Bitmap.Config.ARGB_8888);
                        legacyCanvas2 = new Canvas(legacyBitmap2);
                    } else {
                        legacyBitmap2.eraseColor(Color.TRANSPARENT);
                    }
                    legacyCanvas2.drawBitmap(legacyBitmap, 0, 0, null);
                }
            } catch (Throwable e) {
                // FileLog.e(e);
                if (legacyBitmap2 != null) {
                    legacyBitmap2.recycle();
                    legacyBitmap2 = null;
                }
            }

            NativeUtilities.generateGradient(currentBitmap, true, phase, 1f, currentBitmap.getWidth(), currentBitmap.getHeight(), currentBitmap.getRowBytes(), colors);
            invalidateLegacy = true;
        }
        for (int i = -1; i < ANIMATION_CACHE_BITMAPS_COUNT; i++) {
            float p = (i + 1) / (float) ANIMATION_CACHE_BITMAPS_COUNT;
            NativeUtilities.generateGradient(i < 0 ? gradientFromBitmap : gradientToBitmap[i], true, phase, p, currentBitmap.getWidth(), currentBitmap.getHeight(), currentBitmap.getRowBytes(), colors);
        }
    }

    public void switchToPrevPosition(boolean fast) {
        if (posAnimationProgress < 1.0f) {
            return;
        }
        rotatingPreview = false;
        fastAnimation = fast;
        rotationBack = true;
        posAnimationProgress = 0.0f;
        invalidateParent();
        NativeUtilities.generateGradient(gradientFromBitmap, true, phase, 0, currentBitmap.getWidth(), currentBitmap.getHeight(), currentBitmap.getRowBytes(), colors);
        generateNextGradient();
    }

    public int[] getColors() {
        return colors;
    }

    public void setParentView(View view) {
        parentView = new WeakReference<>(view);
    }

    public void setColors(int c1, int c2, int c3, int c4) {
        setColors(c1, c2, c3, c4, 0, true);
    }

    public void setColors(int c1, int c2, int c3, int c4, Bitmap bitmap) {
        colors[0] = c1;
        colors[1] = c2;
        colors[2] = c3;
        colors[3] = c4;
        NativeUtilities.generateGradient(bitmap, true, phase, interpolator.getInterpolation(posAnimationProgress), currentBitmap.getWidth(), currentBitmap.getHeight(), currentBitmap.getRowBytes(), colors);
    }

    public void setColors(int c1, int c2, int c3, int c4, int rotation, boolean invalidate) {
        if (isPreview && c3 == 0 && c4 == 0) {
            gradientDrawable = new GradientDrawable(getGradientOrientation(rotation), new int[]{c1, c2});
        } else {
            gradientDrawable = null;
        }
        if (colors[0] == c1 && colors[1] == c2 && colors[2] == c3 && colors[3] == c4) {
            return;
        }
        colors[0] = c1;
        colors[1] = c2;
        colors[2] = c3;
        colors[3] = c4;
        if (currentBitmap != null) {
            NativeUtilities.generateGradient(currentBitmap, true, phase, interpolator.getInterpolation(posAnimationProgress), currentBitmap.getWidth(), currentBitmap.getHeight(), currentBitmap.getRowBytes(), colors);
            if (invalidate) {
                invalidateParent();
            }
        }
    }

    private void invalidateParent() {
        invalidateSelf();
        if (parentView != null && parentView.get() != null) {
            parentView.get().invalidate();
        }
        if (postInvalidateParent) {
            // NotificationCenter.getGlobalInstance().postNotificationName(NotificationCenter.invalidateMotionBackground);
            updateAnimation(false);
            cancelRunOnUIThread(updateAnimationRunnable);
            runOnUIThread(updateAnimationRunnable, 16);
        }
    }

    public boolean hasPattern() {
        return patternBitmap != null;
    }

    @Override
    public int getIntrinsicWidth() {
        if (patternBitmap != null) {
            return patternBitmap.getWidth();
        }
        return super.getIntrinsicWidth();
    }

    @Override
    public int getIntrinsicHeight() {
        if (patternBitmap != null) {
            return patternBitmap.getHeight();
        }
        return super.getIntrinsicHeight();
    }

    public void setTranslationY(int y) {
        translationY = y;
    }

    public void setPatternBitmap(int intensity) {
        setPatternBitmap(intensity, patternBitmap, true);
    }

    public void setPatternBitmap(int intensity, Bitmap bitmap) {
        setPatternBitmap(intensity, bitmap, true);
    }

    @SuppressLint("NewApi")
    public void setPatternBitmap(int intensity, Bitmap bitmap, boolean doNotScale) {
        this.intensity = intensity;
        patternBitmap = bitmap;
        invalidateLegacy = true;
        if (patternBitmap == null) {
            return;
        }
        if (useSoftLight) {
            if (intensity >= 0) {
                paint2.setBlendMode(BlendMode.SOFT_LIGHT);
            } else {
                paint2.setBlendMode(null);
            }
        }
        if (intensity < 0) {
            if (!useLegacyBitmap) {
                bitmapShader = new BitmapShader(currentBitmap, Shader.TileMode.CLAMP, Shader.TileMode.CLAMP);
                gradientShader = new BitmapShader(patternBitmap, Shader.TileMode.REPEAT, Shader.TileMode.REPEAT);
                disableGradientShaderScaling = doNotScale;
                paint2.setShader(new ComposeShader(bitmapShader, gradientShader, PorterDuff.Mode.DST_IN));
                paint2.setFilterBitmap(true);
                matrix = new Matrix();
            } else {
                createLegacyBitmap();
                if (!errorWhileGenerateLegacyBitmap) {
                    paint2.setXfermode(new PorterDuffXfermode(PorterDuff.Mode.DST_IN));
                } else {
                    paint2.setXfermode(null);
                }
            }
        } else {
            if (!useLegacyBitmap) {

            } else {
                paint2.setXfermode(null);
            }
        }
    }

    public void setPatternColorFilter(int color) {
        patternColorFilter = new PorterDuffColorFilter(color, PorterDuff.Mode.SRC_IN);
        invalidateParent();
    }

    public void setPatternAlpha(float alpha) {
        this.patternAlpha = alpha;
        invalidateParent();
    }

    public void setBackgroundAlpha(float alpha) {
        this.backgroundAlpha = alpha;
        invalidateParent();
    }

    @Override
    public void setBounds(int left, int top, int right, int bottom) {
        super.setBounds(left, top, right, bottom);
        patternBounds.set(left, top, right, bottom);
        createLegacyBitmap();
    }

    private void createLegacyBitmap() {
        if (useLegacyBitmap && intensity < 0 && !errorWhileGenerateLegacyBitmap) {
            int w = (int) (patternBounds.width() * legacyBitmapScale);
            int h = (int) (patternBounds.height() * legacyBitmapScale);
            if (w > 0 && h > 0 && (legacyBitmap == null || legacyBitmap.getWidth() != w || legacyBitmap.getHeight() != h)) {
                if (legacyBitmap != null) {
                    legacyBitmap.recycle();
                }
                if (legacyBitmap2 != null) {
                    legacyBitmap2.recycle();
                    legacyBitmap2 = null;
                }
                try {
                    legacyBitmap = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888);
                    legacyCanvas = new Canvas(legacyBitmap);
                    invalidateLegacy = true;
                } catch (Throwable e) {
                    if (legacyBitmap != null) {
                        legacyBitmap.recycle();
                        legacyBitmap = null;
                    }
                    // FileLog.e(e);
                    errorWhileGenerateLegacyBitmap = true;
                    paint2.setXfermode(null);
                }
            }
        }
    }

    public void drawBackground(Canvas canvas) {
        Rect bounds = getBounds();
        canvas.save();
        float tr = patternBitmap != null ? bounds.top : translationY;
        int bitmapWidth = currentBitmap.getWidth();
        int bitmapHeight = currentBitmap.getHeight();
        float w = bounds.width();
        float h = bounds.height();
        float maxScale = Math.max(w / bitmapWidth, h / bitmapHeight);
        float width = bitmapWidth * maxScale;
        float height = bitmapHeight * maxScale;
        float x = (w - width) / 2;
        float y = (h - height) / 2;
        if (isPreview) {
            x += bounds.left;
            y += bounds.top;
            canvas.clipRect(bounds.left, bounds.top, bounds.right, bounds.bottom);
        }
        if (intensity < 0) {
            canvas.drawColor(ColorUtils.setAlphaComponent(Color.BLACK, (int) (alpha * backgroundAlpha)));
        } else {
            if (roundRadius != 0) {
                matrix.reset();
                matrix.setTranslate(x, y);
                float scaleW = (currentBitmap.getWidth() / (float) bounds.width());
                float scaleH = (currentBitmap.getHeight() / (float) bounds.height());
                float scale = 1.0f / Math.min(scaleW, scaleH);
                matrix.preScale(scale, scale);
                bitmapShader.setLocalMatrix(matrix);

                rect.set(bounds.left, bounds.top, bounds.right, bounds.bottom);
                int wasAlpha = paint.getAlpha();
                paint.setAlpha((int) (wasAlpha * backgroundAlpha));
                canvas.drawRoundRect(rect, roundRadius, roundRadius, paint);
                paint.setAlpha(wasAlpha);
            } else {
                canvas.translate(0, tr);
                if (gradientDrawable != null) {
                    gradientDrawable.setBounds((int) x, (int) y, (int) (x + width), (int) (y + height));
                    gradientDrawable.setAlpha((int) (255 * backgroundAlpha));
                    gradientDrawable.draw(canvas);
                } else {
                    rect.set(x, y, x + width, y + height);
                    Paint bitmapPaint = overrideBitmapPaint != null ? overrideBitmapPaint : paint;
                    int wasAlpha = bitmapPaint.getAlpha();
                    bitmapPaint.setAlpha((int) (wasAlpha * backgroundAlpha));
                    canvas.drawBitmap(currentBitmap, null, rect, bitmapPaint);
                    bitmapPaint.setAlpha(wasAlpha);
                }
            }
        }
        canvas.restore();

        updateAnimation(true);
    }

    public void drawPattern(Canvas canvas) {
        Rect bounds = getBounds();
        canvas.save();
        float tr = patternBitmap != null ? bounds.top : translationY;
        int bitmapWidth = currentBitmap.getWidth();
        int bitmapHeight = currentBitmap.getHeight();
        float w = bounds.width();
        float h = bounds.height();
        float maxScale = Math.max(w / bitmapWidth, h / bitmapHeight);
        float width = bitmapWidth * maxScale;
        float height = bitmapHeight * maxScale;
        float x = (w - width) / 2;
        float y = (h - height) / 2;
        if (isPreview) {
            x += bounds.left;
            y += bounds.top;
            canvas.clipRect(bounds.left, bounds.top, bounds.right, bounds.bottom);
        }
        if (intensity < 0) {
            if (patternBitmap != null) {
                if (useLegacyBitmap) {
                    if (errorWhileGenerateLegacyBitmap) {
                        bitmapWidth = patternBitmap.getWidth();
                        bitmapHeight = patternBitmap.getHeight();
                        maxScale = Math.max(w / bitmapWidth, h / bitmapHeight);
                        width = bitmapWidth * maxScale;
                        height = bitmapHeight * maxScale;
                        x = (w - width) / 2;
                        y = (h - height) / 2;
                        rect.set(x, y, x + width, y + height);

                        int averageColor = getAverageColor(colors[2], getAverageColor(colors[0], colors[1]));
                        if (colors[3] != 0) {
                            averageColor = getAverageColor(colors[3], averageColor);
                        }
                        if (legacyBitmapColorFilter == null || averageColor != legacyBitmapColor) {
                            legacyBitmapColor = averageColor;
                            legacyBitmapColorFilter = new PorterDuffColorFilter(averageColor, PorterDuff.Mode.SRC_IN);
                        }
                        paint2.setColorFilter(legacyBitmapColorFilter);
                        paint2.setAlpha((int) ((Math.abs(intensity) / 100f) * alpha * patternAlpha));
                        canvas.translate(0, tr);
                        canvas.drawBitmap(patternBitmap, null, rect, paint2);
                    } else if (legacyBitmap != null) {
                        if (invalidateLegacy) {
                            rect.set(0, 0, legacyBitmap.getWidth(), legacyBitmap.getHeight());
                            int oldAlpha = paint.getAlpha();
                            paint.setAlpha(255);
                            legacyCanvas.drawBitmap(currentBitmap, null, rect, paint);
                            paint.setAlpha(oldAlpha);

                            bitmapWidth = patternBitmap.getWidth();
                            bitmapHeight = patternBitmap.getHeight();
                            maxScale = Math.max(w / bitmapWidth, h / bitmapHeight);
                            width = bitmapWidth * maxScale;
                            height = bitmapHeight * maxScale;
                            x = (w - width) / 2;
                            y = (h - height) / 2;
                            rect.set(x, y, x + width, y + height);

                            paint2.setColorFilter(null);
                            paint2.setAlpha((int) ((Math.abs(intensity) / 100f) * 255));
                            legacyCanvas.save();
                            legacyCanvas.scale(legacyBitmapScale, legacyBitmapScale);
                            legacyCanvas.drawBitmap(patternBitmap, null, rect, paint2);
                            legacyCanvas.restore();
                            invalidateLegacy = false;
                        }

                        rect.set(bounds.left, bounds.top, bounds.right, bounds.bottom);
                        if (legacyBitmap2 != null && posAnimationProgress != 1f) {
                            paint.setAlpha((int) (alpha * patternAlpha * (1f - posAnimationProgress)));
                            canvas.drawBitmap(legacyBitmap2, null, rect, paint);

                            paint.setAlpha((int) (alpha * patternAlpha * posAnimationProgress));
                            canvas.drawBitmap(legacyBitmap, null, rect, paint);
                            paint.setAlpha(alpha);
                        } else {
                            canvas.drawBitmap(legacyBitmap, null, rect, paint);
                        }
                    }
                } else {
                    if (matrix == null) {
                        matrix = new Matrix();
                    }
                    matrix.reset();
                    matrix.setTranslate(x, y + tr);
                    float scaleW = (currentBitmap.getWidth() / (float) bounds.width());
                    float scaleH = (currentBitmap.getHeight() / (float) bounds.height());
                    float scale = 1.0f / Math.min(scaleW, scaleH);
                    matrix.preScale(scale, scale);
                    bitmapShader.setLocalMatrix(matrix);

                    matrix.reset();
                    bitmapWidth = patternBitmap.getWidth();
                    bitmapHeight = patternBitmap.getHeight();
                    maxScale = Math.max(w / bitmapWidth, h / bitmapHeight);
                    width = bitmapWidth * maxScale;
                    height = bitmapHeight * maxScale;
                    x = (w - width) / 2;
                    y = (h - height) / 2;
                    matrix.setTranslate((int) x, (int) (y + tr));
                    if (!disableGradientShaderScaling || maxScale > 1.4f || maxScale < 0.8f) {
                        matrix.preScale(maxScale, maxScale);
                    }
                    gradientShader.setLocalMatrix(matrix);
                    paint2.setColorFilter(null);
                    paint2.setAlpha((int) ((Math.abs(intensity) / 100f) * alpha * patternAlpha));
                    rect.set(bounds.left, bounds.top, bounds.right, bounds.bottom);
                    canvas.drawRoundRect(rect, roundRadius, roundRadius, paint2);
                }
            }
        } else {
            if (patternBitmap != null) {
                bitmapWidth = patternBitmap.getWidth();
                bitmapHeight = patternBitmap.getHeight();
                maxScale = Math.max(w / bitmapWidth, h / bitmapHeight);
                width = bitmapWidth * maxScale;
                height = bitmapHeight * maxScale;
                x = (w - width) / 2;
                y = (h - height) / 2;
                rect.set(x, y, x + width, y + height);

                paint2.setColorFilter(patternColorFilter);
                paint2.setAlpha((int) ((Math.abs(intensity) / 100f) * alpha * patternAlpha));
                canvas.drawBitmap(patternBitmap, null, rect, paint2);
            }
        }
        canvas.restore();

        updateAnimation(true);
    }

    @Override
    public void draw(Canvas canvas) {
        Rect bounds = getBounds();
        canvas.save();
        float tr = patternBitmap != null ? bounds.top : translationY;
        int bitmapWidth = currentBitmap.getWidth();
        int bitmapHeight = currentBitmap.getHeight();
        float w = bounds.width();
        float h = bounds.height();
        float maxScale = Math.max(w / bitmapWidth, h / bitmapHeight);
        float width = bitmapWidth * maxScale;
        float height = bitmapHeight * maxScale;
        float x = (w - width) / 2;
        float y = (h - height) / 2;
        if (isPreview) {
            x += bounds.left;
            y += bounds.top;
            canvas.clipRect(bounds.left, bounds.top, bounds.right, bounds.bottom);
        }
        if (intensity < 0) {
            canvas.drawColor(ColorUtils.setAlphaComponent(Color.BLACK, (int) (alpha * backgroundAlpha)));
            if (patternBitmap != null) {
                if (useLegacyBitmap) {
                    if (errorWhileGenerateLegacyBitmap) {
                        bitmapWidth = patternBitmap.getWidth();
                        bitmapHeight = patternBitmap.getHeight();
                        maxScale = Math.max(w / bitmapWidth, h / bitmapHeight);
                        width = bitmapWidth * maxScale;
                        height = bitmapHeight * maxScale;
                        x = (w - width) / 2;
                        y = (h - height) / 2;
                        rect.set(x, y, x + width, y + height);

                        int averageColor = getAverageColor(colors[2], getAverageColor(colors[0], colors[1]));
                        if (colors[3] != 0) {
                            averageColor = getAverageColor(colors[3], averageColor);
                        }
                        if (legacyBitmapColorFilter == null || averageColor != legacyBitmapColor) {
                            legacyBitmapColor = averageColor;
                            legacyBitmapColorFilter = new PorterDuffColorFilter(averageColor, PorterDuff.Mode.SRC_IN);
                        }
                        paint2.setColorFilter(legacyBitmapColorFilter);
                        paint2.setAlpha((int) ((Math.abs(intensity) / 100f) * alpha * patternAlpha));
                        canvas.translate(0, tr);
                        canvas.drawBitmap(patternBitmap, null, rect, paint2);
                    } else if (legacyBitmap != null) {
                        if (invalidateLegacy) {
                            rect.set(0, 0, legacyBitmap.getWidth(), legacyBitmap.getHeight());
                            int oldAlpha = paint.getAlpha();
                            paint.setAlpha(255);
                            legacyCanvas.drawBitmap(currentBitmap, null, rect, paint);
                            paint.setAlpha(oldAlpha);

                            bitmapWidth = patternBitmap.getWidth();
                            bitmapHeight = patternBitmap.getHeight();
                            maxScale = Math.max(w / bitmapWidth, h / bitmapHeight);
                            width = bitmapWidth * maxScale;
                            height = bitmapHeight * maxScale;
                            x = (w - width) / 2;
                            y = (h - height) / 2;
                            rect.set(x, y, x + width, y + height);

                            paint2.setColorFilter(null);
                            paint2.setAlpha((int) ((Math.abs(intensity) / 100f) * 255));
                            legacyCanvas.save();
                            legacyCanvas.scale(legacyBitmapScale, legacyBitmapScale);
                            legacyCanvas.drawBitmap(patternBitmap, null, rect, paint2);
                            legacyCanvas.restore();
                            invalidateLegacy = false;
                        }

                        rect.set(bounds.left, bounds.top, bounds.right, bounds.bottom);
                        if (legacyBitmap2 != null && posAnimationProgress != 1f) {
                            paint.setAlpha((int) (alpha * patternAlpha * (1f - posAnimationProgress)));
                            canvas.drawBitmap(legacyBitmap2, null, rect, paint);

                            paint.setAlpha((int) (alpha * patternAlpha * posAnimationProgress));
                            canvas.drawBitmap(legacyBitmap, null, rect, paint);
                            paint.setAlpha(alpha);
                        } else {
                            canvas.drawBitmap(legacyBitmap, null, rect, paint);
                        }
                    }
                } else {
                    if (matrix == null) {
                        matrix = new Matrix();
                    }
                    matrix.reset();
                    matrix.setTranslate(x, y + tr);
                    float scaleW = (currentBitmap.getWidth() / (float) bounds.width());
                    float scaleH = (currentBitmap.getHeight() / (float) bounds.height());
                    float scale = 1.0f / Math.min(scaleW, scaleH);
                    matrix.preScale(scale, scale);
                    bitmapShader.setLocalMatrix(matrix);

                    matrix.reset();
                    bitmapWidth = patternBitmap.getWidth();
                    bitmapHeight = patternBitmap.getHeight();
                    maxScale = Math.max(w / bitmapWidth, h / bitmapHeight);
                    width = bitmapWidth * maxScale;
                    height = bitmapHeight * maxScale;
                    x = (w - width) / 2;
                    y = (h - height) / 2;
                    matrix.setTranslate((int) x, (int) (y + tr));
                    if (!disableGradientShaderScaling || maxScale > 1.4f || maxScale < 0.8f) {
                        matrix.preScale(maxScale, maxScale);
                    }
                    gradientShader.setLocalMatrix(matrix);
                    paint2.setColorFilter(null);
                    paint2.setAlpha((int) ((Math.abs(intensity) / 100f) * alpha * patternAlpha));
                    rect.set(bounds.left, bounds.top, bounds.right, bounds.bottom);
                    canvas.drawRoundRect(rect, roundRadius, roundRadius, paint2);
                }
            }
        } else {
            if (roundRadius != 0) {
                matrix.reset();
                matrix.setTranslate(x, y);
                float scaleW = (currentBitmap.getWidth() / (float) bounds.width());
                float scaleH = (currentBitmap.getHeight() / (float) bounds.height());
                float scale = 1.0f / Math.min(scaleW, scaleH);
                matrix.preScale(scale, scale);
                bitmapShader.setLocalMatrix(matrix);

                rect.set(bounds.left, bounds.top, bounds.right, bounds.bottom);
                canvas.drawRoundRect(rect, roundRadius, roundRadius, paint);
            } else {
                canvas.translate(0, tr);
                if (gradientDrawable != null) {
                    gradientDrawable.setBounds((int) x, (int) y, (int) (x + width), (int) (y + height));
                    gradientDrawable.setAlpha((int) (255 * backgroundAlpha));
                    gradientDrawable.draw(canvas);
                } else {
                    rect.set(x, y, x + width, y + height);
                    Paint bitmapPaint = overrideBitmapPaint != null ? overrideBitmapPaint : paint;
                    int wasAlpha = bitmapPaint.getAlpha();
                    bitmapPaint.setAlpha((int) (wasAlpha * backgroundAlpha));
                    canvas.drawBitmap(currentBitmap, null, rect, bitmapPaint);
                    bitmapPaint.setAlpha(wasAlpha);
                }
            }

            if (patternBitmap != null) {
                bitmapWidth = patternBitmap.getWidth();
                bitmapHeight = patternBitmap.getHeight();
                maxScale = Math.max(w / bitmapWidth, h / bitmapHeight);
                width = bitmapWidth * maxScale;
                height = bitmapHeight * maxScale;
                x = (w - width) / 2;
                y = (h - height) / 2;
                rect.set(x, y, x + width, y + height);

                paint2.setColorFilter(patternColorFilter);
                paint2.setAlpha((int) ((Math.abs(intensity) / 100f) * alpha * patternAlpha));
                canvas.drawBitmap(patternBitmap, null, rect, paint2);
            }
        }
        canvas.restore();

        updateAnimation(true);
    }

    public void setAnimationProgressProvider(GenericProvider<MotionBackgroundDrawable, Float> animationProgressProvider) {
        this.animationProgressProvider = animationProgressProvider;
        updateAnimation(true);
    }

    public void updateAnimation(boolean invalidate) {
        long newTime = SystemClock.elapsedRealtime();
        long dt = newTime - lastUpdateTime;
        if (dt > 20) {
            dt = 17;
        }
        lastUpdateTime = newTime;
        if (dt <= 1) {
            return;
        }

        if (isIndeterminateAnimation && posAnimationProgress == 1.0f) {
            posAnimationProgress = 0f;
        }
        if (posAnimationProgress < 1.0f) {
            float progress;
            boolean isNeedGenerateGradient = postInvalidateParent || rotatingPreview;
            if (isIndeterminateAnimation) {
                posAnimationProgress += (dt / 12000f) * indeterminateSpeedScale;
                if (posAnimationProgress >= 1.0f) {
                    posAnimationProgress = 0.0f;
                }
                float progressPerPhase = 1f / 8f;
                phase = (int) (posAnimationProgress / progressPerPhase);
                progress = 1f - (posAnimationProgress - phase * progressPerPhase) / progressPerPhase;
                isNeedGenerateGradient = true;
            } else {
                if (rotatingPreview) {
                    int stageBefore;
                    float progressBefore = interpolator.getInterpolation(posAnimationProgress);
                    if (progressBefore <= 0.25f) {
                        stageBefore = 0;
                    } else if (progressBefore <= 0.5f) {
                        stageBefore = 1;
                    } else if (progressBefore <= 0.75f) {
                        stageBefore = 2;
                    } else {
                        stageBefore = 3;
                    }
                    if (animationProgressProvider != null) {
                        posAnimationProgress = animationProgressProvider.provide(this);
                    } else {
                        posAnimationProgress += dt / (rotationBack ? 1000.0f : 2000.0f);
                    }
                    if (posAnimationProgress > 1.0f) {
                        posAnimationProgress = 1.0f;
                    }
                    if (animationProgressProvider == null && !ignoreInterpolator) {
                        progress = interpolator.getInterpolation(posAnimationProgress);
                    } else {
                        progress = posAnimationProgress;
                    }
                    if (ignoreInterpolator && (progress == 0 || progress == 1)) {
                        ignoreInterpolator = false;
                    }
                    if (stageBefore == 0 && progress > 0.25f ||
                        stageBefore == 1 && progress > 0.5f ||
                        stageBefore == 2 && progress > 0.75f) {
                        if (rotationBack) {
                            phase++;
                            if (phase > 7) {
                                phase = 0;
                            }
                        } else {
                            phase--;
                            if (phase < 0) {
                                phase = 7;
                            }
                        }
                    }
                    if (progress <= 0.25f) {
                        progress /= 0.25f;
                    } else if (progress <= 0.5f) {
                        progress = (progress - 0.25f) / 0.25f;
                    } else if (progress <= 0.75f) {
                        progress = (progress - 0.5f) / 0.25f;
                    } else {
                        progress = (progress - 0.75f) / 0.25f;
                    }
                    if (rotationBack) {
                        float prevProgress = progress;
                        progress = 1.0f - progress;
                        if (posAnimationProgress >= 1.0f) {
                            phase++;
                            if (phase > 7) {
                                phase = 0;
                            }
                            progress = 1.0f;
                        }
                    }
                } else {
                    if (animationProgressProvider != null) {
                        posAnimationProgress = animationProgressProvider.provide(this);
                    } else {
                        posAnimationProgress += dt / (fastAnimation ? 300.0f : 500.0f);
                    }
                    if (posAnimationProgress > 1.0f) {
                        posAnimationProgress = 1.0f;
                    }
                    if (animationProgressProvider == null && !ignoreInterpolator) {
                        progress = interpolator.getInterpolation(posAnimationProgress);
                    } else {
                        progress = posAnimationProgress;
                    }
                    if (ignoreInterpolator && (progress == 0 || progress == 1)) {
                        ignoreInterpolator = false;
                    }
                    if (rotationBack) {
                        progress = 1.0f - progress;
                        if (posAnimationProgress >= 1.0f) {
                            phase++;
                            if (phase > 7) {
                                phase = 0;
                            }
                            progress = 1.0f;
                        }
                    }
                }
            }

            if (isNeedGenerateGradient) {
                NativeUtilities.generateGradient(currentBitmap, true, phase, progress, currentBitmap.getWidth(), currentBitmap.getHeight(), currentBitmap.getRowBytes(), colors);
                invalidateLegacy = true;
            } else {
                if (useLegacyBitmap && intensity < 0) {

                } else {
                    if (progress != 1f) {
                        float part = 1f / ANIMATION_CACHE_BITMAPS_COUNT;
                        int i = (int) (progress / part);
                        if (i == 0) {
                            gradientCanvas.drawBitmap(gradientFromBitmap, 0, 0, null);
                        } else {
                            gradientCanvas.drawBitmap(gradientToBitmap[i - 1], 0, 0, null);
                        }
                        float alpha = (progress - i * part) / part;
                        paint3.setAlpha((int) (255 * alpha));
                        gradientCanvas.drawBitmap(gradientToBitmap[i], 0, 0, paint3);
                    } else {
                        gradientCanvas.drawBitmap(gradientToBitmap[ANIMATION_CACHE_BITMAPS_COUNT - 1], 0, 0, paint3);
                    }
                }
            }
            if (invalidate) {
                invalidateParent();
            }
        }
    }

    @Override
    public void setAlpha(int alpha) {
        this.alpha = alpha;
        paint.setAlpha(alpha);
        paint2.setAlpha(alpha);
    }

    @Override
    public void setColorFilter(ColorFilter colorFilter) {

    }

    @Override
    public int getOpacity() {
        return PixelFormat.TRANSPARENT;
    }

    public boolean isOneColor() {
        return colors[0] == colors[1] && colors[0] == colors[2] && colors[0] == colors[3];
    }

    public float getIndeterminateSpeedScale() {
        return indeterminateSpeedScale;
    }

    public void setIndeterminateSpeedScale(float indeterminateSpeedScale) {
        this.indeterminateSpeedScale = indeterminateSpeedScale;
    }

    public boolean isIndeterminateAnimation() {
        return isIndeterminateAnimation;
    }

    public void setIndeterminateAnimation(boolean isIndeterminateAnimation) {
        if (!isIndeterminateAnimation && this.isIndeterminateAnimation) {
            float progressPerPhase = 1f / 8f;
            int phase = (int) (posAnimationProgress / progressPerPhase);
            posAnimationProgress = 1f - (posAnimationProgress - phase * progressPerPhase) / progressPerPhase;
            ignoreInterpolator = true;
        }
        this.isIndeterminateAnimation = isIndeterminateAnimation;
    }

    public void setOverrideBitmapPaint(Paint overrideBitmapPaint) {
        this.overrideBitmapPaint = overrideBitmapPaint;
    }


    // Todo move to another file:

    public static List<Integer> generateColorVariations(int baseColor) {
        // Извлекаем HSL компоненты из исходного цвета
        float[] hsv = new float[3];
        Color.colorToHSV(baseColor, hsv);

        List<Integer> colorVariations = new ArrayList<>();

        colorVariations.add(Color.HSVToColor(new float[]{
            (hsv[0] + 10) % 360,
            Math.min(hsv[1] + 0.075f, 1f),
            Math.max(hsv[2] - 0.075f, 0f)
        }));

        colorVariations.add(Color.HSVToColor(new float[]{
            (hsv[0] - 10 + 360) % 360,
            Math.max(hsv[1] - 0.075f, 0f),
            Math.min(hsv[2] + 0.075f, 1f)
        }));

        colorVariations.add(Color.HSVToColor(new float[]{
            hsv[0],
            Math.min(hsv[1] + 0.05f, 1f),
            Math.max(hsv[2] - 0.05f, 0f)
        }));

        return colorVariations;
    }

    private interface GenericProvider<F, T> {
        T provide(F obj);
    }

    public static GradientDrawable.Orientation getGradientOrientation(int gradientAngle) {
        switch (gradientAngle) {
            case 0:
                return GradientDrawable.Orientation.BOTTOM_TOP;
            case 90:
                return GradientDrawable.Orientation.LEFT_RIGHT;
            case 135:
                return GradientDrawable.Orientation.TL_BR;
            case 180:
                return GradientDrawable.Orientation.TOP_BOTTOM;
            case 225:
                return GradientDrawable.Orientation.TR_BL;
            case 270:
                return GradientDrawable.Orientation.RIGHT_LEFT;
            case 315:
                return GradientDrawable.Orientation.BR_TL;
            default: // 45
                return GradientDrawable.Orientation.BL_TR;
        }
    }

    public static int getAverageColor(int color1, int color2) {
        int r1 = Color.red(color1);
        int r2 = Color.red(color2);
        int g1 = Color.green(color1);
        int g2 = Color.green(color2);
        int b1 = Color.blue(color1);
        int b2 = Color.blue(color2);
        return Color.argb(255, (r1 / 2 + r2 / 2), (g1 / 2 + g2 / 2), (b1 / 2 + b2 / 2));
    }

    public static float[] RGBtoHSB(int r, int g, int b) {
        float hue, saturation, brightness;
        float[] hsbvals = new float[3];
        int cmax = Math.max(r, g);
        if (b > cmax) {
            cmax = b;
        }
        int cmin = Math.min(r, g);
        if (b < cmin) {
            cmin = b;
        }

        brightness = ((float) cmax) / 255.0f;
        if (cmax != 0) {
            saturation = ((float) (cmax - cmin)) / ((float) cmax);
        } else {
            saturation = 0;
        }
        if (saturation == 0) {
            hue = 0;
        } else {
            float redc = ((float) (cmax - r)) / ((float) (cmax - cmin));
            float greenc = ((float) (cmax - g)) / ((float) (cmax - cmin));
            float bluec = ((float) (cmax - b)) / ((float) (cmax - cmin));
            if (r == cmax) {
                hue = bluec - greenc;
            } else if (g == cmax) {
                hue = 2.0f + redc - bluec;
            } else {
                hue = 4.0f + greenc - redc;
            }
            hue = hue / 6.0f;
            if (hue < 0) {
                hue = hue + 1.0f;
            }
        }
        hsbvals[0] = hue;
        hsbvals[1] = saturation;
        hsbvals[2] = brightness;
        return hsbvals;
    }

    public static int getPatternColor(int color, boolean alwaysDark) {
        float[] hsb = RGBtoHSB(Color.red(color), Color.green(color), Color.blue(color));
        if (hsb[1] > 0.0f || (hsb[2] < 1.0f && hsb[2] > 0.0f)) {
            hsb[1] = Math.min(1.0f, hsb[1] + (alwaysDark ? 0.15f : 0.05f) + 0.1f * (1.0f - hsb[1]));
        }
        if (alwaysDark || hsb[2] > 0.5f) {
            hsb[2] = Math.max(0.0f, hsb[2] * 0.65f);
        } else {
            hsb[2] = Math.max(0.0f, Math.min(1.0f, 1.0f - hsb[2] * 0.65f));
        }
        return HSBtoRGB(hsb[0], hsb[1], hsb[2]) & (alwaysDark ? 0x99ffffff : 0x66ffffff);
    }

    public static int HSBtoRGB(float hue, float saturation, float brightness) {
        int r = 0, g = 0, b = 0;
        if (saturation == 0) {
            r = g = b = (int) (brightness * 255.0f + 0.5f);
        } else {
            float h = (hue - (float) Math.floor(hue)) * 6.0f;
            float f = h - (float) java.lang.Math.floor(h);
            float p = brightness * (1.0f - saturation);
            float q = brightness * (1.0f - saturation * f);
            float t = brightness * (1.0f - (saturation * (1.0f - f)));
            switch ((int) h) {
                case 0:
                    r = (int) (brightness * 255.0f + 0.5f);
                    g = (int) (t * 255.0f + 0.5f);
                    b = (int) (p * 255.0f + 0.5f);
                    break;
                case 1:
                    r = (int) (q * 255.0f + 0.5f);
                    g = (int) (brightness * 255.0f + 0.5f);
                    b = (int) (p * 255.0f + 0.5f);
                    break;
                case 2:
                    r = (int) (p * 255.0f + 0.5f);
                    g = (int) (brightness * 255.0f + 0.5f);
                    b = (int) (t * 255.0f + 0.5f);
                    break;
                case 3:
                    r = (int) (p * 255.0f + 0.5f);
                    g = (int) (q * 255.0f + 0.5f);
                    b = (int) (brightness * 255.0f + 0.5f);
                    break;
                case 4:
                    r = (int) (t * 255.0f + 0.5f);
                    g = (int) (p * 255.0f + 0.5f);
                    b = (int) (brightness * 255.0f + 0.5f);
                    break;
                case 5:
                    r = (int) (brightness * 255.0f + 0.5f);
                    g = (int) (p * 255.0f + 0.5f);
                    b = (int) (q * 255.0f + 0.5f);
                    break;
            }
        }
        return 0xff000000 | ((r & 0xff) << 16) | ((g & 0xff) << 8) | (b & 0xff);
    }

    public static final Handler applicationHandler = new Handler(Looper.getMainLooper());

    public static void runOnUIThread(Runnable runnable, long delay) {
        if (applicationHandler == null) {
            return;
        }
        if (delay == 0) {
            applicationHandler.post(runnable);
        } else {
            applicationHandler.postDelayed(runnable, delay);
        }
    }

    public static void cancelRunOnUIThread(Runnable runnable) {
        if (applicationHandler == null) {
            return;
        }
        applicationHandler.removeCallbacks(runnable);
    }
}
