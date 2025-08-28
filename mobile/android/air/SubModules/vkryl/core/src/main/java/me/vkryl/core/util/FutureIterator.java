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
 * File created on 12/09/2022, 17:17.
 */

package me.vkryl.core.util;

import java.util.Iterator;

import me.vkryl.core.lambda.Future;

public class FutureIterator<T> implements Iterator<T> {
  private final Iterator<? extends Future<T>> iterator;

  public FutureIterator (Iterable<? extends Future<T>> iterator) {
    this.iterator = iterator.iterator();
  }

  @Override
  public boolean hasNext () {
    return iterator.hasNext();
  }

  @Override
  public T next () {
    return iterator.next().getValue();
  }
}
