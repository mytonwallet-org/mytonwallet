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

import android.os.Handler;
import android.os.Looper;
import android.view.View;

import androidx.annotation.NonNull;
import androidx.annotation.Nullable;

import java.util.Iterator;

import me.vkryl.core.reference.ReferenceList;

public class MultipleViewProvider implements ViewProvider {

  private static final int ACTION_INVALIDATE_ALL = 0;
  private static final int ACTION_REQUEST_LAYOUT = 1;
  private final Handler handler;

  public MultipleViewProvider () {
    this.handler = new Handler(Looper.getMainLooper(), msg -> {
      switch (msg.what) {
        case ACTION_INVALIDATE_ALL:
          invalidate();
          break;
        case ACTION_REQUEST_LAYOUT:
          ((View) msg.obj).requestLayout();
          break;
      }
      return true;
    });
  }

  private @Nullable InvalidateContentProvider contentProvider;

  public MultipleViewProvider setContentProvider (@Nullable InvalidateContentProvider contentProvider) {
    this.contentProvider = contentProvider;
    return this;
  }

  private final ReferenceList<View> views = new ReferenceList<>(false, false, null);

  public @NonNull ReferenceList<View> getViewsList () {
    return views;
  }

  public final boolean attachToView (@Nullable View view) {
    return view != null && views.add(view);
  }

  public final boolean detachFromView (@Nullable View view) {
    return view != null && views.remove(view);
  }

  public final void detachFromAllViews () {
    views.clear();
  }

  @NonNull
  @Override
  public Iterator<View> iterator () {
    return views.iterator();
  }

  @Override
  public boolean hasAnyTargetToInvalidate () {
    return !views.isEmpty();
  }

  @Override
  public void postInvalidate () {
    handler.sendMessage(handler.obtainMessage(ACTION_INVALIDATE_ALL));
  }

  @Override
  public void requestLayout () {
    // FIXME: better thread safety
    final boolean isBackground = Looper.myLooper() != Looper.getMainLooper();
    for (View view : this) {
      if (isBackground) {
        handler.sendMessage(handler.obtainMessage(ACTION_REQUEST_LAYOUT, view));
      } else {
        view.requestLayout();
      }
    }
  }

  @Override
  public boolean invalidateContent (Object cause) {
    if (contentProvider != null) {
      return contentProvider.invalidateContent(cause);
    } else {
      boolean success = false;
      for (View view : this) {
        if (view instanceof InvalidateContentProvider && ((InvalidateContentProvider) view).invalidateContent(cause)) {
          success = true;
        }
      }
      return success;
    }
  }
}
