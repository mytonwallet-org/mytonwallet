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
 * File created on 07/01/2019
 */

package me.vkryl.core.util;

import androidx.annotation.NonNull;
import androidx.annotation.Nullable;

import java.util.Iterator;

import me.vkryl.core.lambda.Filter;

public class FilteredIterator<T> implements Iterator<T>, Iterable<T> {
  @Nullable
  private final Iterator<T> itr;

  @NonNull
  private final Filter<T> filter;

  public FilteredIterator (@Nullable Iterator<T> itr, @NonNull Filter<T> filter) {
    this.itr = itr;
    this.filter = filter;
  }

  public FilteredIterator (@Nullable Iterable<T> itr, @NonNull Filter<T> filter) {
    this(itr != null ? itr.iterator() : null, filter);
  }

  @NonNull
  @Override
  public Iterator<T> iterator () {
    return this;
  }

  private T next;

  @Override
  public boolean hasNext () {
    if (itr == null)
      return false;
    this.next = null;
    do {
      boolean hasNext = itr.hasNext();
      if (!hasNext)
        return false;
      T next = itr.next();
      if (!filter.accept(next))
        continue;
      this.next = next;
      return true;
    } while (true);
  }

  @Override
  public T next () {
    return this.next;
  }
}
