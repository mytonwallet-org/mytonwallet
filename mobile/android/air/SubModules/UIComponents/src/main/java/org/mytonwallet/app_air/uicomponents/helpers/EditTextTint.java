package org.mytonwallet.app_air.uicomponents.helpers;

import android.graphics.PorterDuff;
import android.graphics.drawable.BitmapDrawable;
import android.graphics.drawable.Drawable;
import android.graphics.drawable.InsetDrawable;
import android.os.Build;
import android.widget.EditText;
import android.widget.TextView;

import androidx.annotation.ColorInt;
import androidx.annotation.NonNull;
import androidx.core.content.ContextCompat;

import java.lang.reflect.Field;

/**
 * Tint the cursor and select handles of an {@link EditText} programmatically.
 */
public class EditTextTint {

    private final EditText editText;
    private final Integer cursorColor;
    private final Integer selectHandleLeftColor;
    private final Integer selectHandleRightColor;
    private final Integer selectHandleMiddleColor;

    private EditTextTint(Builder builder) {
        editText = builder.editText;
        cursorColor = builder.cursorColor;
        selectHandleLeftColor = builder.selectHandleLeftColor;
        selectHandleRightColor = builder.selectHandleRightColor;
        selectHandleMiddleColor = builder.selectHandleMiddleColor;
    }

    /**
     * Set the cursor and handle colors for an {@link EditText} programmatically.
     *
     * @param editText The {@link EditText} to tint
     * @param color    The color to apply for the cursor and select handles
     * @throws EditTextTintError If an error occured while attempting to tint the view.
     */
    public static void applyColor(@NonNull EditText editText, @ColorInt int color) throws EditTextTintError {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            if (editText.getTextCursorDrawable() instanceof InsetDrawable) {
                InsetDrawable insetDrawable = (InsetDrawable) editText.getTextCursorDrawable();
                insetDrawable.setColorFilter(color, PorterDuff.Mode.SRC_ATOP);
                editText.setTextCursorDrawable(insetDrawable);
            }

            if (editText.getTextSelectHandle() instanceof BitmapDrawable) {
                BitmapDrawable insetDrawable = (BitmapDrawable) editText.getTextSelectHandle();
                insetDrawable.setColorFilter(color, PorterDuff.Mode.SRC_ATOP);
                editText.setTextSelectHandle(insetDrawable);
            }

            if (editText.getTextSelectHandleRight() instanceof BitmapDrawable) {
                BitmapDrawable insetDrawable = (BitmapDrawable) editText.getTextSelectHandleRight();
                insetDrawable.setColorFilter(color, PorterDuff.Mode.SRC_ATOP);
                editText.setTextSelectHandleRight(insetDrawable);
            }

            if (editText.getTextSelectHandleLeft() instanceof BitmapDrawable) {
                BitmapDrawable insetDrawable = (BitmapDrawable) editText.getTextSelectHandleLeft();
                insetDrawable.setColorFilter(color, PorterDuff.Mode.SRC_ATOP);
                editText.setTextSelectHandleLeft(insetDrawable);
            }
        } else {
            EditTextTint editTextTint = new Builder(editText)
                .setCursorColor(color)
                .setSelectHandleLeftColor(color)
                .setSelectHandleRightColor(color)
                .setSelectHandleMiddleColor(color)
                .build();
            editTextTint.apply();
        }
    }

    /**
     * Sets the color for the cursor and handles on the {@link EditText editText}.
     *
     * @throws EditTextTintError if an error occurs while tinting the view.
     */
    public void apply() throws EditTextTintError {
        try {
            // Get the editor
            Field field = TextView.class.getDeclaredField("mEditor");
            field.setAccessible(true);
            Object editor = field.get(editText);

            if (cursorColor != null) {
                // Get the cursor drawable, tint it, and set it on the TextView Editor
                field = TextView.class.getDeclaredField("mCursorDrawableRes");
                field.setAccessible(true);
                int cursorDrawableRes = field.getInt(editText);
                Drawable cursorDrawable = ContextCompat.getDrawable(editText.getContext(), cursorDrawableRes);
                if (cursorDrawable != null) {
                    cursorDrawable = cursorDrawable.mutate();
                    cursorDrawable.setColorFilter(cursorColor, PorterDuff.Mode.SRC_IN);
                    Drawable[] drawables = {cursorDrawable, cursorDrawable};
                    field = editor.getClass().getDeclaredField("mCursorDrawable");
                    field.setAccessible(true);
                    field.set(editor, drawables);
                }
            }

            String[] resFieldNames = {"mTextSelectHandleLeftRes", "mTextSelectHandleRightRes", "mTextSelectHandleRes"};
            String[] drawableFieldNames = {"mSelectHandleLeft", "mSelectHandleRight", "mSelectHandleCenter"};
            Integer[] colors = {selectHandleLeftColor, selectHandleRightColor, selectHandleMiddleColor};

            for (int i = 0; i < resFieldNames.length; i++) {
                Integer color = colors[i];
                if (color == null) {
                    continue;
                }

                String resFieldName = resFieldNames[i];
                String drawableFieldName = drawableFieldNames[i];

                field = TextView.class.getDeclaredField(resFieldName);
                field.setAccessible(true);
                int selectHandleRes = field.getInt(editText);

                Drawable selectHandleDrawable = ContextCompat.getDrawable(editText.getContext(), selectHandleRes);
                if (selectHandleDrawable != null) {
                    selectHandleDrawable = selectHandleDrawable.mutate();
                    selectHandleDrawable.setColorFilter(color, PorterDuff.Mode.SRC_IN);

                    field = editor.getClass().getDeclaredField(drawableFieldName);
                    field.setAccessible(true);
                    field.set(editor, selectHandleDrawable);
                }
            }
        } catch (Exception e) {
            e.printStackTrace();
        }
    }

    public static class Builder {

        final EditText editText;
        Integer cursorColor;
        Integer selectHandleLeftColor;
        Integer selectHandleRightColor;
        Integer selectHandleMiddleColor;

        public Builder(@NonNull EditText editText) {
            this.editText = editText;
        }

        public Builder setCursorColor(@ColorInt int cursorColor) {
            this.cursorColor = cursorColor;
            return this;
        }

        public Builder setSelectHandleLeftColor(@ColorInt int selectHandleLeftColor) {
            this.selectHandleLeftColor = selectHandleLeftColor;
            return this;
        }

        public Builder setSelectHandleRightColor(@ColorInt int selectHandleRightColor) {
            this.selectHandleRightColor = selectHandleRightColor;
            return this;
        }

        public Builder setSelectHandleMiddleColor(@ColorInt int selectHandleMiddleColor) {
            this.selectHandleMiddleColor = selectHandleMiddleColor;
            return this;
        }

        public EditTextTint build() {
            return new EditTextTint(this);
        }

    }

    public static class EditTextTintError extends Exception {

        public EditTextTintError(String message, Throwable cause) {
            super(message, cause);
        }
    }

}
