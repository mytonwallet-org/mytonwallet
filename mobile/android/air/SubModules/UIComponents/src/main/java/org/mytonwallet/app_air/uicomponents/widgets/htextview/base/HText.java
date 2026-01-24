package org.mytonwallet.app_air.uicomponents.widgets.htextview.base;

import android.graphics.Canvas;
import android.graphics.Paint;
import android.os.Build;
import android.text.Layout;
import android.text.TextPaint;
import android.util.AttributeSet;
import android.view.ViewTreeObserver;

import androidx.core.view.ViewCompat;

import java.util.ArrayList;
import java.util.List;

/**
 * abstract class
 * Created by hanks on 15-12-19.
 * Fixed text width measurement & kerning issues
 */
public abstract class HText implements IHText {

    protected int mHeight, mWidth;
    protected CharSequence mText, mOldText;
    protected TextPaint mPaint, mOldPaint;
    protected HTextView mHTextView;
    protected List<Float> gapList = new ArrayList<>();
    protected List<Float> oldGapList = new ArrayList<>();
    protected float progress; // 0 ~ 1
    protected float mTextSize;
    protected float oldStartX = 0;
    protected AnimationListener animationListener;

    public void setProgress(float progress) {
        this.stopAnimator();
        this.progress = progress;
        mHTextView.invalidate();
    }

    @Override
    public void init(HTextView hTextView, AttributeSet attrs, int defStyle) {
        mHTextView = hTextView;
        mOldText = "";
        mText = hTextView.getText();
        progress = 1;

        mPaint = new TextPaint(Paint.ANTI_ALIAS_FLAG);
        mOldPaint = new TextPaint(mPaint);

        mHTextView.getViewTreeObserver().addOnGlobalLayoutListener(new ViewTreeObserver.OnGlobalLayoutListener() {
            @Override
            public void onGlobalLayout() {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.JELLY_BEAN) {
                    mHTextView.getViewTreeObserver().removeOnGlobalLayoutListener(this);
                } else {
                    mHTextView.getViewTreeObserver().removeGlobalOnLayoutListener(this);
                }
                mTextSize = mHTextView.getTextSize();
                mWidth = mHTextView.getWidth();
                mHeight = mHTextView.getHeight();
                oldStartX = 0;

                try {
                    int layoutDirection = ViewCompat.getLayoutDirection(mHTextView);
                    Layout layout = mHTextView.getLayout();
                    if (layout != null) {
                        oldStartX = layoutDirection == ViewCompat.LAYOUT_DIRECTION_LTR
                            ? layout.getLineLeft(0)
                            : layout.getLineRight(0);
                    }
                } catch (Exception e) {
                    e.printStackTrace();
                }

                initVariables();
            }
        });
        prepareAnimate();
    }

    private void syncPaint(TextPaint paint) {
        paint.setTextSize(mHTextView.getTextSize());
        paint.setColor(mHTextView.getCurrentTextColor());
        paint.setTypeface(mHTextView.getTypeface());
        paint.setTextScaleX(mHTextView.getTextScaleX());

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
            paint.setLetterSpacing(mHTextView.getLetterSpacing());
        }
    }

    private void prepareAnimate() {
        syncPaint(mPaint);
        syncPaint(mOldPaint);

        gapList.clear();
        oldGapList.clear();

        if (mText != null && mText.length() > 0) {
            float[] widths = new float[mText.length()];
            mPaint.getTextWidths(mText.toString(), widths);
            for (float w : widths) {
                gapList.add(w);
            }
        }

        if (mOldText != null && mOldText.length() > 0) {
            float[] oldWidths = new float[mOldText.length()];
            mOldPaint.getTextWidths(mOldText.toString(), oldWidths);
            for (float w : oldWidths) {
                oldGapList.add(w);
            }
        }
    }

    @Override
    public void animateText(CharSequence text, boolean animated) {
        mHTextView.setText(text);
        mOldText = mText;
        mText = text;
        prepareAnimate();
        animatePrepare(text);
        animateStart(text);
        if (!animated) {
            setProgress(1f);
        }
    }

    @Override
    public void setAnimationListener(AnimationListener listener) {
        animationListener = listener;
    }

    @Override
    public void onDraw(Canvas canvas) {
        drawFrame(canvas);
    }

    protected abstract void initVariables();

    protected abstract void animateStart(CharSequence text);

    protected abstract void animatePrepare(CharSequence text);

    protected abstract void drawFrame(Canvas canvas);
}
