package org.mytonwallet.app_air.uicomponents.widgets.htextview.base;

import android.content.Context;
import android.util.AttributeSet;

import androidx.appcompat.widget.AppCompatTextView;

/**
 * Base TextView
 * Created by hanks on 2017/3/13.
 */

public abstract class HTextView extends AppCompatTextView {
    public HTextView(Context context) {
        this(context, null);
    }

    public HTextView(Context context, AttributeSet attrs) {
        this(context, attrs, 0);
    }

    public HTextView(Context context, AttributeSet attrs, int defStyleAttr) {
        super(context, attrs, defStyleAttr);
    }

    public abstract void setAnimationListener(AnimationListener listener);

    public abstract void setProgress(float progress);

    public abstract void animateText(CharSequence text, boolean animated);
}
