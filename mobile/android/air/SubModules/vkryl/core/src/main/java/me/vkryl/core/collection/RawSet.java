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
 * File created on 27/08/2022, 01:33.
 */

package me.vkryl.core.collection;

import androidx.annotation.NonNull;

import java.util.Collection;
import java.util.Iterator;
import java.util.TreeSet;

public abstract class RawSet <T extends Number & Comparable<T>> implements Iterable<T> {
  protected final TreeSet<T> set;

  public RawSet () {
    this.set = new TreeSet<>();
  }

  public RawSet (int initialCapacity) {
    this();
    // keeping in case underlying data set type changes
  }

  public RawSet (Collection<T> source) {
    this.set = new TreeSet<>(source);
  }

  public void ensureCapacity (int minCapacity) {
    // keeping in case underlying data set type changes
  }

  public void addAll (Collection<T> items) {
    ensureCapacity(size() + items.size());
    this.set.addAll(items);
  }

  public void addAll (RawSet<T> items) {
    ensureCapacity(size() + items.size());
    this.set.addAll(items.set);
  }

  public void removeAll (Collection<T> items) {
    this.set.removeAll(items);
  }

  public void removeAll (RawSet<T> items) {
    this.set.removeAll(items.set);
  }

  public boolean add (T item) {
    return this.set.add(item);
  }

  public boolean remove (T item) {
    return this.set.remove(item);
  }

  public boolean has (T item) {
    return this.set.contains(item);
  }

  public boolean replace (T item, T withItem) {
    if (remove(item)) {
      add(withItem);
      return true;
    }
    return false;
  }

  public void clear () {
    this.set.clear();
  }

  public int size () {
    return this.set.size();
  }

  public boolean isEmpty () {
    return this.set.isEmpty();
  }

  @NonNull
  @Override
  public Iterator<T> iterator () {
    return this.set.iterator();
  }

  public final T minValue () {
    return set.first();
  }

  protected final T maxValue () {
    return set.last();
  }

  protected final int[] toIntArray () {
    final int[] result = new int[size()];
    int index = 0;
    for (T item : this) {
      result[index] = item.intValue();
      index++;
    }
    return result;
  }

  protected final int[][] toIntArray (int limit) {
    final int size = size();
    if (size == 0) {
      return new int[0][];
    }
    if (size <= limit) {
      return new int[][] {toIntArray()};
    }
    final int arrayCount = (int) Math.ceil((double) size / (double) limit);
    int[][] result = new int[arrayCount][];
    int index = 0;
    for (T item : this) {
      int arrayIndex = index / limit;
      int itemIndex = index - limit * arrayIndex;
      if (itemIndex == 0) {
        result[arrayIndex] = new int[Math.min(limit, size - index)];
      }
      result[arrayIndex][itemIndex] = item.intValue();
      index++;
    }
    return result;
  }

  protected final long[] toLongArray () {
    final long[] result = new long[size()];
    int index = 0;
    for (T item : this) {
      result[index] = item.longValue();
      index++;
    }
    return result;
  }

  protected final long[][] toLongArray (int limit) {
    final int size = size();
    if (size == 0) {
      return new long[0][];
    }
    if (size <= limit) {
      return new long[][] {toLongArray()};
    }
    final int arrayCount = (int) Math.ceil((double) size / (double) limit);
    long[][] result = new long[arrayCount][];
    int index = 0;
    for (T item : this) {
      int arrayIndex = index / limit;
      int itemIndex = index - limit * arrayIndex;
      if (itemIndex == 0) {
        result[arrayIndex] = new long[Math.min(limit, size - index)];
      }
      result[arrayIndex][itemIndex] = item.longValue();
      index++;
    }
    return result;
  }
}
