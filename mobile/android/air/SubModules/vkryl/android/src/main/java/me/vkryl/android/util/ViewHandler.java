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
 * File created on 03/10/18
 */

package me.vkryl.android.util;

import android.os.Handler;
import android.os.Looper;
import android.os.Message;
import android.view.View;

import androidx.annotation.NonNull;

public final class ViewHandler extends Handler {
  public ViewHandler () {
    super(Looper.getMainLooper());
  }

  private static final int ACTION_INVALIDATE = 0;

  public void invalidate (View view, long delay) {
    Message msg = Message.obtain(this, ACTION_INVALIDATE, view);
    if (delay > 0) {
      sendMessageDelayed(msg, delay);
    } else {
      sendMessage(msg);
    }
  }

  public void cancelInvalidate (View view) {
    removeMessages(ACTION_INVALIDATE, view);
  }

  private static final int ACTION_REQUEST_LAYOUT = 1;



  @Override
  public void handleMessage (@NonNull Message msg) {
    switch (msg.what) {
      case ACTION_INVALIDATE: {
        if (msg.obj instanceof View) {
          ((View) msg.obj).invalidate();
        } else if (msg.obj instanceof ViewProvider) {
          ((ViewProvider) msg.obj).invalidate();
        }
        break;
      }
    }
  }
}
