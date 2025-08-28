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
 * File created on 19/12/2017
 */

package me.vkryl.core.util;

import android.os.Looper;

import java.util.HashMap;

public class LocalVar<T> {
  private T mainVar;
  private HashMap<Looper, T> looperMap;
  private HashMap<Thread, T> threadMap;

  public LocalVar () { }

  public T getMain () {
    return mainVar;
  }

  public void setMain (T var) {
    this.mainVar = var;
  }

  public T get () {
    Looper looper = Looper.myLooper();
    if (looper == Looper.getMainLooper()) {
      return mainVar;
    } else if (looper != null) {
      T result;
      synchronized (this) {
        result = looperMap != null ? looperMap.get(looper) : null;
      }
      return result;
    } else {
      Thread thread = Thread.currentThread();
      T result;
      synchronized (this) {
        result = threadMap != null ? threadMap.get(thread) : null;
      }
      return result;
    }
  }

  public void set (T value) {
    Looper looper = Looper.myLooper();
    if (looper == Looper.getMainLooper()) {
      mainVar = value;
    } else if (value == null) {
      if (looper != null) {
        synchronized (this) {
          if (looperMap != null) {
            looperMap.remove(looper);
          }
        }
      } else {
        Thread thread = Thread.currentThread();
        synchronized (this) {
          if (threadMap != null) {
            threadMap.remove(thread);
          }
        }
      }
    } else {
      if (looper != null) {
        synchronized (this) {
          if (looperMap == null) {
            looperMap = new HashMap<>();
          }
          looperMap.put(looper, value);
        }
      } else {
        Thread thread = Thread.currentThread();
        synchronized (this) {
          if (threadMap == null) {
            threadMap = new HashMap<>();
          }
          threadMap.put(thread, value);
        }
      }
    }
  }

  public void clear () {
    synchronized (this) {
      mainVar = null;
      if (looperMap != null) {
        looperMap.clear();
      }
      if (threadMap != null) {
        threadMap.clear();
      }
    }
  }
}
