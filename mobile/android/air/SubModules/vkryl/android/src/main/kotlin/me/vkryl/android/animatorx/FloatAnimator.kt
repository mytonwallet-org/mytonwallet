/*
 * This file is a part of X-Android
 * Copyright © Vyacheslav Krylov 2024
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
 */

package me.vkryl.android.animatorx

import android.animation.TimeInterpolator

class FloatAnimator : BaseAnimator<Float> {
  companion object {
    const val DEFAULT_INITIAL_VALUE = 0.0f
  }

  constructor(
    duration: Long,
    interpolator: TimeInterpolator,
    initialValue: Float = DEFAULT_INITIAL_VALUE,
    onAnimationsFinished: AnimatorFinishListener<Float>? = null,
    onApplyValue: AnimatorUpdateListener<Float>
  ) : super(duration, interpolator, initialValue, onAnimationsFinished, onApplyValue)

  @JvmOverloads constructor(
    duration: Long,
    interpolator: TimeInterpolator,
    initialValue: Float = DEFAULT_INITIAL_VALUE,
    listener: AnimatorListener<Float>
  ) : super(duration, interpolator, initialValue, listener)

  override fun interpolate(fromValue: Float, toValue: Float, fraction: Float) =
    fromValue + (toValue - fromValue) * fraction
}