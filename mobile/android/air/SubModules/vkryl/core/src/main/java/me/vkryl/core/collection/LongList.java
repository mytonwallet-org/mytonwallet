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
 * File created on 28/11/2016
 */

package me.vkryl.core.collection;

import androidx.annotation.NonNull;

import me.vkryl.core.ArrayUtils;

public class LongList {
  private long[] data;
  private int size;

  public LongList (int initialCapacity) {
    data = new long[initialCapacity];
  }

  public LongList (long[] source) {
    this.data = source;
    this.size = source.length;
  }

  public void ensureCapacity (int x, int increaseCount) {
    if (data.length < x) {
      long[] dest = new long[Math.max(x, data.length + increaseCount)];
      System.arraycopy(data, 0, dest, 0, data.length);
      data = dest;
    }
  }

  private void trim () {
    if (size < data.length) {
      long[] dest = new long[size];
      System.arraycopy(data, 0, dest, 0, size);
      data = dest;
    }
  }

  public void clear () {
    size = 0;
  }

  public void append (long x) {
    ensureCapacity(size + 1, 10);
    data[size++] = x;
  }

  public boolean contains (long x) {
    int i = 0;
    for (long cx : data) {
      if (i++ == size) {
        break;
      }
      if (cx == x) {
        return true;
      }
    }
    return false;
  }

  public void appendAll (long[] x) {
    if (x.length > 0) {
      ensureCapacity(size + x.length, 10);
      System.arraycopy(x, 0, data, size, x.length);
      size += x.length;
    }
  }

  public void appendAll (LongList list) {
    if (list.size > 0) {
      ensureCapacity(size + list.size, 0);
      System.arraycopy(list.data, 0, data, size, list.size);
      size += list.size;
    }
  }

  public long[] get () {
    trim();
    return data;
  }

  public int size () {
    return size;
  }

  public long get (int i) {
    return data[i];
  }

  public long last () {
    return data[size - 1];
  }

  public boolean isEmpty () {
    return size == 0;
  }

  public void removeAt (int i) {
    if (i < 0 || i >= size) {
      throw new IndexOutOfBoundsException();
    }
    if (i + 1 < size) {
      System.arraycopy(data, i + 1, data, i, size - i - 1);
    }
    this.size--;
  }

  public boolean remove (long value) {
    int i = indexOf(value);
    if (i == -1) {
      return false;
    }
    removeAt(i);
    return true;
  }

  public int indexOf (long value) {
    for (int i = 0; i < size; i++) {
      if (data[i] == value) {
        return i;
      }
    }
    return -1;
  }

  public void toStringBuilder (StringBuilder b) {
    boolean first = true;
    int i = 0;
    while (i++ < size) {
      if (first) {
        first = false;
      } else {
        b.append(',');
      }
      b.append(data[i]);
    }
  }

  @Override
  @NonNull
  public String toString () {
    return ArrayUtils.toString(data, size);
  }
}
