/*
 * This file is a part of X-Android
 * Copyright © Vyacheslav Krylov 2014
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 *
 * File created on 13/02/2017
 */

package me.vkryl.android.util;

import android.graphics.Rect;
import android.os.Build;
import android.view.View;
import android.view.ViewParent;

import androidx.annotation.NonNull;
import androidx.annotation.Nullable;

import me.vkryl.android.ViewUtils;
import me.vkryl.core.lambda.RunnableData;

public interface ViewProvider extends InvalidateDelegate, LayoutDelegate, InvalidateContentProvider, Iterable<View> {
  boolean hasAnyTargetToInvalidate ();

  @Nullable
  default View findAnyTarget () {
    for (View view : this) {
      if (view != null) {
        return view;
      }
    }
    return null;
  }

  default void performWithViews (@NonNull RunnableData<View> callback) {
    for (View view : this) {
      if (view != null) {
        callback.runWithData(view);
      }
    }
  }

  default boolean belongsToProvider (View childView) {
    for (View view : this) {
      if (view == childView)
        return true;
    }
    return false;
  }

  default int getMeasuredWidth () {
    View view = findAnyTarget();
    return view != null ? view.getMeasuredWidth() : 0;
  }
  default int getMeasuredHeight () {
    View view = findAnyTarget();
    return view != null ? view.getMeasuredHeight() : 0;
  }

  default void requestLayout () {
    performWithViews(View::requestLayout);
  }

  default void postInvalidate () {
    performWithViews(View::postInvalidate);
  }

  default void invalidate () {
    performWithViews(View::invalidate);
  }

  @SuppressWarnings("deprecation")
  default void invalidate (int left, int top, int right, int bottom) {
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
      invalidate();
    } else {
      performWithViews(view -> view.invalidate(left, top, right, bottom));
    }
  }

  @SuppressWarnings("deprecation")
  default void invalidate (Rect dirty) {
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
      performWithViews(view -> view.invalidate(dirty));
    } else {
      invalidate();
    }
  }

  default void invalidateOutline (boolean invalidate) {
    performWithViews(view -> {
      if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
        view.invalidateOutline();
      }
      if (invalidate) {
        view.invalidate();
      }
    });
  }

  default void invalidateParent () {
    performWithViews(view -> {
      ViewParent parent = view.getParent();
      if (parent instanceof View) {
        ((View) parent).invalidate();
      }
    });
  }

  @SuppressWarnings("deprecation")
  default void invalidateParent (int left, int top, int right, int bottom) {
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
      invalidateParent();
    } else {
      performWithViews(view -> {
        ViewParent parent = view.getParent();
        if (parent instanceof View) {
          ((View) parent).invalidate(left, top, right, bottom);
        }
      });
    }
  }

  default void performClickSoundFeedback () {
    ViewUtils.onClick(findAnyTarget());
  }

  @Override
  default boolean invalidateContent (Object cause) {
    int successCount = 0;
    for (View view : this) {
      if (view instanceof InvalidateContentProvider && ((InvalidateContentProvider) view).invalidateContent(cause)) {
        successCount++;
      }
    }
    return successCount > 0;
  }
}
