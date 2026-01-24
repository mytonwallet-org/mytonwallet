package org.mytonwallet.app_air.uicomponents.widgets.htextview.evaporate;

import android.content.Context;
import android.graphics.Canvas;
import android.text.TextUtils;
import android.util.AttributeSet;

import org.mytonwallet.app_air.uicomponents.widgets.htextview.base.AnimationListener;
import org.mytonwallet.app_air.uicomponents.widgets.htextview.base.HTextView;

/**
 * EvaporateTextView
 * Created by hanks on 2017/3/16.
 */

public class EvaporateTextView extends HTextView {

    private EvaporateText evaporateText;

    public EvaporateTextView(Context context) {
        this(context, null);
    }

    public EvaporateTextView(Context context, AttributeSet attrs) {
        this(context, attrs, 0);
    }

    public EvaporateTextView(Context context, AttributeSet attrs, int defStyleAttr) {
        super(context, attrs, defStyleAttr);
        init(attrs, defStyleAttr);
    }

    @Override
    public void setAnimationListener(AnimationListener listener) {
        evaporateText.setAnimationListener(listener);
    }

    private void init(AttributeSet attrs, int defStyleAttr) {
        evaporateText = new EvaporateText();
        evaporateText.init(this, attrs, defStyleAttr);
        setMaxLines(1);
        setEllipsize(TextUtils.TruncateAt.END);
    }

    @Override
    public void setProgress(float progress) {
        evaporateText.setProgress(progress);
    }

    @Override
    public void animateText(CharSequence text, boolean animated) {
        evaporateText.animateText(text, animated);
    }

    @Override
    protected void onDraw(Canvas canvas) {
        // super.onDraw(canvas);
        evaporateText.onDraw(canvas);
    }
}
