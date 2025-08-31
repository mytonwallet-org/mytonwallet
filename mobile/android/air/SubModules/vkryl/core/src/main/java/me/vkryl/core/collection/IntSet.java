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

public class IntSet extends RawSet<Integer> {
  public IntSet () {
    super();
  }

  public IntSet (int initialCapacity) {
    super(initialCapacity);
  }

  public IntSet (Collection<Integer> source) {
    super(source);
  }

  public IntSet (int[] source) {
    super(source.length);
    addAll(source);
  }

  public void addAll (int... items) {
    for (int item : items) {
      add(item);
    }
  }

  public void removeAll (int... items) {
    for (int item : items) {
      remove(item);
    }
  }

  public int min () {
    return minValue();
  }

  public int max () {
    return maxValue();
  }

  public int[] toArray () {
    return toIntArray();
  }

  public int[][] toArray (int limit) {
    return toIntArray(limit);
  }
}
