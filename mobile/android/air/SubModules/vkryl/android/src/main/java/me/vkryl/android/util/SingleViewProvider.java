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
 * File created on 14/02/2017
 */

package me.vkryl.android.util;

import android.view.View;

import androidx.annotation.NonNull;
import androidx.annotation.Nullable;

import java.util.Collections;
import java.util.Iterator;

public class SingleViewProvider implements ViewProvider {
  private @Nullable View view;

  public SingleViewProvider (@Nullable View view) {
    this.view = view;
  }

  public void setView (@Nullable View view) {
    this.view = view;
  }

  @Override
  public boolean hasAnyTargetToInvalidate () {
    return findAnyTarget() != null;
  }

  @Override
  public boolean belongsToProvider (View view) {
    return findAnyTarget() == view;
  }

  @Override
  public @Nullable View findAnyTarget () {
    return view;
  }

  @NonNull
  @Override
  public Iterator<View> iterator () {
    View view = findAnyTarget();
    if (view != null) {
      return Collections.singleton(view).iterator();
    } else {
      return Collections.emptyIterator();
    }
  }
}
