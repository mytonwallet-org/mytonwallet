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

import android.animation.TimeInterpolator

typealias BoolAnimatorUpdateListener = (state: BoolAnimator.State, animatedValue: Float, stateChanged: Boolean, prevState: BoolAnimator.State) -> Unit
typealias BoolAnimatorFinishListener = (finalState: BoolAnimator.State, byAnimationEnd: Boolean) -> Unit

interface BoolAnimatorListener {
  fun onAnimationUpdate(state: BoolAnimator.State, animatedValue: Float, stateChanged: Boolean, prevState: BoolAnimator.State)
  fun onAnimationFinish(finalState: BoolAnimator.State, byAnimationEnd: Boolean) { }
}

class BoolAnimator(
  val duration: Long,
  val interpolator: TimeInterpolator,
  initialValue: Boolean = DEFAULT_INITIAL_VALUE,
  onAnimationsFinished: BoolAnimatorFinishListener? = null,
  onApplyValue: BoolAnimatorUpdateListener) {
  companion object {
    const val DEFAULT_INITIAL_VALUE = false
  }

  @JvmOverloads constructor(
    duration: Long,
    interpolator: TimeInterpolator,
    initialValue: Boolean = DEFAULT_INITIAL_VALUE,
    listener: BoolAnimatorListener
  ) : this(duration, interpolator, initialValue,
    onAnimationsFinished = { finalState, byAnimationEnd ->
      listener.onAnimationFinish(finalState, byAnimationEnd)
    },
    onApplyValue = { state, animatedValue, stateChanged, prevState ->
      listener.onAnimationUpdate(state, animatedValue, stateChanged, prevState)
    }
  )

  enum class State {
    FALSE,
    TRUE,
    INTERMEDIATE;

    companion object {
      fun valueOf(float: Float) =
        when (float) {
          0.0f -> FALSE
          1.0f -> TRUE
          else -> INTERMEDIATE
        }
    }
  }

  private val animated = FloatAnimator(
    duration, interpolator,
    initialValue = if (initialValue) 1.0f else 0.0f,
    onAnimationsFinished = { floatValue, byAnimationEnd ->
      val state = State.valueOf(floatValue)
      onAnimationsFinished?.invoke(state, byAnimationEnd)
    },
    onApplyValue = { floatValue ->
      val state = State.valueOf(floatValue)
      val oldState = this.state
      this.state = state
      onApplyValue(state, floatValue, oldState != state, oldState)
    }
  )

  var state: State = if (initialValue) State.TRUE else State.FALSE
    private set

  var value: Boolean = initialValue
    private set
  var forcedValue: Boolean
    get() = value
    set(newValue) = changeValue(newValue, false)
  var animatedValue: Boolean
    get() = value
    set(newValue) = changeValue(newValue, true)

  val floatValue: Float
    get() = animated.value

  @JvmOverloads
  fun changeValue(newValue: Boolean, animated: Boolean = true) {
    if (this.value != newValue || !animated) {
      this.animated.stopAnimation()
      value = newValue
      val newFloatValue = if (newValue) 1.0f else 0.0f
      this.animated.changeValue(newFloatValue, animated)
    }
  }
}