/*
 * This file is a part of X-Android
 * Copyright © Vyacheslav Krylov 2014
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program. If not, see <https://www.gnu.org/licenses/>.
 *
 * File created on 13/08/2022, 23:42.
 */

package me.vkryl.android.text;

import android.text.InputFilter;
import android.text.Spanned;

public class CodePointCountFilter implements InputFilter {
  private final int maxCount;

  public CodePointCountFilter (int maxCount) {
    this.maxCount = maxCount;
  }

  public int getMaxCount () {
    return maxCount;
  }

  @Override
  public CharSequence filter (CharSequence source, int start, int end, Spanned dest, int dstart, int dend) {
    final int existingCodePointCount =
      Character.codePointCount(dest, 0, dstart) +
      Character.codePointCount(dest, dend, dest.length());
    final int addingCodePointCount =
      Character.codePointCount(source, start, end);
    if ((existingCodePointCount + addingCodePointCount) <= maxCount) {
      // source + dest are under the limit
      return null;
    }
    if (existingCodePointCount >= maxCount) {
      // dest is too big to fit any new characters
      return "";
    }
    // add as many code points as possible to fit inside of dest
    int keepCount = maxCount - existingCodePointCount;
    int newEnd = start;
    do {
      final int codePoint = Character.codePointAt(source, newEnd);
      newEnd += Character.charCount(codePoint);
      keepCount--;
    } while (keepCount > 0 && newEnd < dend);
    return source.subSequence(start, newEnd);
  }
}
