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
 */

package me.vkryl.android.text;

import android.text.Spannable;
import android.text.Spanned;

final class TextUtils {
  private TextUtils () { }

  public static void copySpans (Spanned source, int start, int end,
                                Class<?> kind,
                                Spannable dest, int destoff) {
    if (kind == null) {
      kind = Object.class;
    }

    Object[] spans = source.getSpans(start, end, kind);

    if (spans == null || spans.length == 0)
      return;

    for (Object span : spans) {
      int st = source.getSpanStart(span);
      int en = source.getSpanEnd(span);
      int fl = source.getSpanFlags(span);

      if (st < start)
        st = start;
      if (en > end)
        en = end;
      try {
        dest.setSpan(span, st - start + destoff, en - start + destoff,
          fl);
      } catch (Throwable t) {
        t.printStackTrace();
      }
    }
  }
}
