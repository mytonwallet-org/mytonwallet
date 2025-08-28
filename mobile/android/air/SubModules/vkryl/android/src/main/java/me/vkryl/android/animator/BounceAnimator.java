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
 * File created on 10/04/2019
 */

package me.vkryl.android.animator;

import me.vkryl.android.AnimatorUtils;
import me.vkryl.android.util.ViewProvider;

public final class BounceAnimator {
  private final BoolAnimator animator;

  public BounceAnimator (ViewProvider provider) {
    this.animator = new BoolAnimator(0, new FactorAnimator.Target() {
      @Override
      public void onFactorChanged (int id, float factor, float fraction, FactorAnimator callee) {
        provider.invalidate();
      }

      @Override
      public void onFactorChangeFinished (int id, float finalFactor, FactorAnimator callee) {
        provider.invalidate();
      }
    }, AnimatorUtils.OVERSHOOT_INTERPOLATOR, 210l);
  }

  public BounceAnimator (FactorAnimator.Target target) {
    this.animator = new BoolAnimator(0, target, AnimatorUtils.OVERSHOOT_INTERPOLATOR, 210l);
  }

  public void setValue (boolean value, boolean animated) {
    if (animated) {
      if (value && animator.getFloatValue() == 0f) {
        animator.setInterpolator(AnimatorUtils.OVERSHOOT_INTERPOLATOR);
        animator.setDuration(210l);
      } else {
        animator.setInterpolator(AnimatorUtils.DECELERATE_INTERPOLATOR);
        animator.setDuration(100l);
      }
    }
    animator.setValue(value, animated);
  }

  public float getFloatValue () {
    return animator.getFloatValue();
  }

  public boolean getValue () {
    return animator.getValue();
  }
}
