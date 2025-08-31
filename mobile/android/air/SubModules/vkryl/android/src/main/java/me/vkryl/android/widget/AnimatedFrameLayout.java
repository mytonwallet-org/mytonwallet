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
 * File created on 01/12/2016
 */

package me.vkryl.android.widget;

import android.content.Context;
import android.view.View;

import me.vkryl.android.animator.Animated;

public class AnimatedFrameLayout extends FrameLayoutFix implements Animated {
  public AnimatedFrameLayout (Context context) {
    super(context);
  }

  private Runnable pendingAction;

  @Override
  public void runOnceViewBecomesReady (View view, Runnable action) {
    this.pendingAction = action;
  }

  @Override
  protected void onLayout (boolean changed, int left, int top, int right, int bottom) {
    super.onLayout(changed, left, top, right, bottom);
    if (pendingAction != null) {
      pendingAction.run();
      pendingAction = null;
    }
  }
}
