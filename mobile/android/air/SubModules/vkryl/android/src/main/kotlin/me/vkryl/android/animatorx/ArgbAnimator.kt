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
import android.graphics.Color
import androidx.annotation.ColorInt
import me.vkryl.core.fromToArgb

class ArgbAnimator : BaseAnimator<Int> {
  companion object {
    const val DEFAULT_INITIAL_VALUE = Color.BLACK
  }

  constructor(
    duration: Long,
    interpolator: TimeInterpolator,
    @ColorInt initialValue: Int = DEFAULT_INITIAL_VALUE,
    onAnimationsFinished: AnimatorFinishListener<Int>? = null,
    onApplyValue: AnimatorUpdateListener<Int>
  ) : super(duration, interpolator, initialValue, onAnimationsFinished, onApplyValue)

  @JvmOverloads constructor(
    duration: Long,
    interpolator: TimeInterpolator,
    @ColorInt initialValue: Int = DEFAULT_INITIAL_VALUE,
    listener: AnimatorListener<Int>
  ) : super(duration, interpolator, initialValue, listener)

  override fun interpolate(fromValue: Int, toValue: Int, fraction: Float): Int =
    fromToArgb(fromValue, toValue, fraction)
}