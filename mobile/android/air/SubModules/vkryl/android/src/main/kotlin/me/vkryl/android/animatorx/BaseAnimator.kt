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

@file:Suppress("MemberVisibilityCanBePrivate")

package me.vkryl.android.animatorx

import android.animation.Animator
import android.animation.TimeInterpolator
import android.animation.ValueAnimator
import android.os.Build
import androidx.annotation.CallSuper

internal typealias AnimatorUpdateListener<T> = (newValue: T) -> Unit
internal typealias AnimatorFinishListener<T> = (finalValue: T, byAnimationEnd: Boolean) -> Unit

interface AnimatorListener<T> {
  fun onAnimationUpdate(newValue: T)
  fun onAnimationFinish(finalValue: T, byAnimationEnd: Boolean) { }
}

abstract class BaseAnimator<T>(
  val duration: Long,
  val interpolator: TimeInterpolator,
  initialValue: T,
  private val onAnimationsFinished: AnimatorFinishListener<T>? = null,
  private val onValueChange: AnimatorUpdateListener<T>) {

  constructor(
    duration: Long,
    interpolator: TimeInterpolator,
    initialValue: T,
    listener: AnimatorListener<T>
  ) : this(
      duration, interpolator, initialValue,
      onAnimationsFinished = { finalValue, byAnimationEnd ->
        listener.onAnimationFinish(finalValue, byAnimationEnd)
      },
      onValueChange = { newValue ->
        listener.onAnimationUpdate(newValue)
      }
    )

  var value: T = initialValue
    private set(value) {
      if (field != value) {
        field = value
        handleValueChange(value)
      }
    }
  val finalValue: T
    get() = if (isAnimating) {
      animatingToValue
    } else {
      value
    }
  var forcedValue: T
    get() = value
    set(newValue) = changeValue(newValue, false)
  var animatedValue: T
    get() = value
    set(newValue) = changeValue(newValue, true)

  val isAnimating: Boolean
    get() = animator != null
  private var animator: ValueAnimator? = null
  private var animatingToValue: T = initialValue

  fun stopAnimation(): Boolean {
    return animator?.let {
      it.cancel()
      animator = null
      true
    } ?: false
  }

  abstract fun interpolate(fromValue: T, toValue: T, fraction: Float): T

  @CallSuper
  open fun handleValueChange(newValue: T) {
    onValueChange(newValue)
  }

  @CallSuper
  open fun handleValueChangeFinished(finalValue: T, byAnimationEnd: Boolean) {
    onAnimationsFinished?.invoke(finalValue, byAnimationEnd)
  }

  @JvmOverloads
  fun changeValue(newValue: T, animated: Boolean = true) {
    if (animated && isAnimating && animatingToValue == newValue)
      return
    stopAnimation()
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
      if (!ValueAnimator.areAnimatorsEnabled()) {
        value = newValue
        onAnimationsFinished?.invoke(animatedValue, false)
        return
      }
    }
    if (animated) {
      animatingToValue = newValue
      val animator = ValueAnimator.ofFloat(0f, 1f)
      animator.duration = duration
      animator.interpolator = interpolator
      val fromValue = this.value
      animator.addUpdateListener {
        if (this.animator == it) {
          val fraction = it.animatedFraction
          value = interpolate(fromValue, newValue, fraction)
        }
      }
      animator.addListener(object : Animator.AnimatorListener {
        override fun onAnimationStart(animation: Animator) { }
        override fun onAnimationRepeat(animation: Animator) { }
        override fun onAnimationCancel(animation: Animator) { }

        override fun onAnimationEnd(animator: Animator) {
          if (this@BaseAnimator.animator == animator && stopAnimation()) {
            handleValueChangeFinished(animatedValue, true)
          }
        }
      })
      this.animator = animator
      animator.start()
    } else {
      value = newValue
      handleValueChangeFinished(animatedValue, false)
    }
  }
}