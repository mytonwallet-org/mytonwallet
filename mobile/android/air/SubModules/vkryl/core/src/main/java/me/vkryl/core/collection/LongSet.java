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
 * File created on 15/01/2021
 */

package me.vkryl.core.collection;

import java.util.Collection;

public class LongSet extends RawSet<Long> {
  public LongSet () {
    super();
  }

  public LongSet (int initialCapacity) {
    super(initialCapacity);
  }

  public LongSet (Collection<Long> source) {
    super(source);
  }

  public LongSet (long[] source) {
    super(source.length);
    addAll(source);
  }

  public void addAll (long... items) {
    for (long item : items) {
      add(item);
    }
  }

  public void removeAll (long... items) {
    for (long item : items) {
      remove(item);
    }
  }

  public long min () {
    return minValue();
  }

  public long max () {
    return maxValue();
  }

  public long[] toArray () {
    return toLongArray();
  }

  public long[][] toArray (int limit) {
    return toLongArray(limit);
  }
}
