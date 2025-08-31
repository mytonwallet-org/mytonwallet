/*
 * This file is a part of X-Core
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
 * File created on 15/05/15 at 22:49
 * Reworked to kotlin in 2020
 */

package me.vkryl.core.lambda

import android.os.Handler
import androidx.core.os.CancellationSignal

abstract class CancellableRunnable : Runnable {
  private val signal = CancellationSignal()
  private var attachedToHandler: Handler? = null
  private val lock = Any()

  fun cancel () {
    signal.cancel()
  }

  fun removeOnCancel (handler: Handler?): CancellableRunnable {
    synchronized(lock) { attachedToHandler = handler }
    if (handler != null) {
      signal.setOnCancelListener {
        synchronized(lock) { attachedToHandler?.removeCallbacks(this) }
      }
    } else {
      signal.setOnCancelListener(null)
    }
    return this
  }

  val isPending: Boolean
    get () = !signal.isCanceled

  abstract fun act ()

  final override fun run () {
    if (!signal.isCanceled) {
      act()
    }
  }
}