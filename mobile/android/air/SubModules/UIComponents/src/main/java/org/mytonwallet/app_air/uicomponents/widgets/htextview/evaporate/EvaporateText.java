package org.mytonwallet.app_air.uicomponents.widgets.htextview.evaporate;

import android.animation.Animator;
import android.animation.ValueAnimator;
import android.graphics.Canvas;
import android.graphics.Rect;
import android.util.AttributeSet;
import android.view.View;
import android.view.animation.AccelerateDecelerateInterpolator;

import org.mytonwallet.app_air.uicomponents.widgets.htextview.base.CharacterDiffResult;
import org.mytonwallet.app_air.uicomponents.widgets.htextview.base.CharacterUtils;
import org.mytonwallet.app_air.uicomponents.widgets.htextview.base.DefaultAnimatorListener;
import org.mytonwallet.app_air.uicomponents.widgets.htextview.base.HText;
import org.mytonwallet.app_air.uicomponents.widgets.htextview.base.HTextView;

import java.util.ArrayList;
import java.util.List;


/**
 * EvaporateText
 * Created by hanks on 2017/3/16.
 */
public class EvaporateText extends HText {

    float charTime = 300;
    int mostCount = 20;
    private int mTextHeight;

    private List<CharacterDiffResult> differentList = new ArrayList<>();
    private long duration;
    private ValueAnimator animator;
    private final char[] mCharBuffer = new char[1];

    public static final int RESIZE_ANCHOR_START = 0;
    public static final int RESIZE_ANCHOR_CENTER = 1;
    public static final int RESIZE_ANCHOR_END = 2;

    // Which edge stays put when a text change resizes a wrap-content view. The old glyphs keep
    // their position by shifting with the moving edge.
    private int mResizeAnchor = RESIZE_ANCHOR_START;
    private int mOldViewWidth;
    private Runnable pendingAnimate;

    public void setResizeAnchor(int anchor) {
        mResizeAnchor = anchor;
    }

    private float resizeAnchorFactor() {
        boolean isRtl = mHTextView.getLayoutDirection() == View.LAYOUT_DIRECTION_RTL;
        switch (mResizeAnchor) {
            case RESIZE_ANCHOR_END:
                return isRtl ? 0f : 1f;
            case RESIZE_ANCHOR_CENTER:
                return 0.5f;
            default:
                return isRtl ? 1f : 0f;
        }
    }

    @Override
    public void init(final HTextView hTextView, AttributeSet attrs, int defStyle) {
        super.init(hTextView, attrs, defStyle);
        animator = new ValueAnimator();
        animator.setInterpolator(new AccelerateDecelerateInterpolator());
        animator.addListener(new DefaultAnimatorListener() {
            @Override
            public void onAnimationEnd(Animator animation) {
                if (animationListener != null) {
                    animationListener.onAnimationEnd(mHTextView);
                }
            }
        });
        animator.addUpdateListener(new ValueAnimator.AnimatorUpdateListener() {
            @Override
            public void onAnimationUpdate(ValueAnimator animation) {
                progress = (float) animation.getAnimatedValue();
                mHTextView.invalidate();
            }
        });
        int n = mText.length();
        n = n <= 0 ? 1 : n;
        duration = (long) (charTime + charTime / mostCount * (n - 1));
    }

    @Override
    public void animateText(final CharSequence text, final boolean animated) {
        if (mHTextView == null) {
            return;
        }
        if (pendingAnimate != null) {
            mHTextView.removeCallbacks(pendingAnimate);
            pendingAnimate = null;
        }

        Runnable animate = () -> {
            pendingAnimate = null;
            if (mHTextView.getLayout() == null) {
                return;
            }
            oldStartX = mHTextView.getLayout().getLineLeft(0);
            mOldViewWidth = mHTextView.getWidth();
            EvaporateText.super.animateText(text, animated);
        };

        if (mHTextView.getLayout() != null) {
            animate.run();
        } else if (!animated) {
            // Nothing is animated from the old layout, so the text applies now instead of on attach.
            mOldViewWidth = mHTextView.getWidth();
            EvaporateText.super.animateText(text, false);
        } else {
            pendingAnimate = animate;
            mHTextView.post(animate);
        }
    }

    @Override
    protected void initVariables() {
    }

    @Override
    protected void animateStart(CharSequence text) {
        int n = mText.length();
        n = n <= 0 ? 1 : n;
        duration = (long) (charTime + charTime / mostCount * (n - 1));
        animator.cancel();
        animator.setFloatValues(0, 1);
        animator.setDuration(duration);
        animator.start();
    }

    @Override
    protected void animatePrepare(CharSequence text) {
        differentList.clear();
        differentList.addAll(CharacterUtils.diff(mOldText, mText));

        Rect bounds = new Rect();
        mPaint.getTextBounds(mText.toString(), 0, mText.length(), bounds);
        mTextHeight = bounds.height();
    }

    @Override
    public void stopAnimator() {
        animator.cancel();
    }

    @Override
    protected void drawFrame(Canvas canvas) {
        if (mHTextView.getLayout() == null) {
            return;
        }

        float startX = mHTextView.getLayout().getLineLeft(0);
        float startY = mHTextView.getBaseline();

        float oldStartX = this.oldStartX +
            (mHTextView.getWidth() - mOldViewWidth) * resizeAnchorFactor();

        float offset = startX;
        float oldOffset = oldStartX;

        int maxLength = Math.max(mText.length(), mOldText.length());

        for (int i = 0; i < maxLength; i++) {

            // draw old text
            if (i < mOldText.length()) {
                //
                float pp = progress * duration / (charTime + charTime / mostCount * (mText.length() - 1));

                mOldPaint.setTextSize(mTextSize);
                int move = CharacterUtils.needMove(i, differentList);
                mCharBuffer[0] = mOldText.charAt(i);
                if (move != -1) {
                    mOldPaint.setAlpha(255);
                    float p = pp * 2f;
                    p = p > 1 ? 1 : p;
                    float distX = CharacterUtils.getOffset(i, move, p, startX, oldStartX, gapList, oldGapList);
                    canvas.drawText(mCharBuffer, 0, 1, distX, startY, mOldPaint);
                } else {
                    mOldPaint.setAlpha((int) ((1 - pp) * 255));
                    float y = startY - pp * mTextHeight;
                    float width = mOldPaint.measureText(mCharBuffer, 0, 1);
                    canvas.drawText(mCharBuffer, 0, 1, oldOffset + (oldGapList.get(i) - width) / 2, y, mOldPaint);
                }
                oldOffset += oldGapList.get(i);
            }

            // draw new text
            if (i < mText.length()) {

                if (!CharacterUtils.stayHere(i, differentList)) {

                    int alpha = (int) (255f / charTime * (progress * duration - charTime * i / mostCount));
                    alpha = alpha > 255 ? 255 : alpha;
                    alpha = alpha < 0 ? 0 : alpha;

                    mPaint.setAlpha(alpha);
                    mPaint.setTextSize(mTextSize);
                    float pp = progress * duration / (charTime + charTime / mostCount * (mText.length() - 1));
                    float y = mTextHeight + startY - pp * mTextHeight;

                    mCharBuffer[0] = mText.charAt(i);
                    float width = mPaint.measureText(mCharBuffer, 0, 1);
                    canvas.drawText(mCharBuffer, 0, 1, offset + (gapList.get(i) - width) / 2, y, mPaint);
                }

                offset += gapList.get(i);
            }
        }
    }

}
