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
 * File created on 26/02/2018
 */

package me.vkryl.core.reference;

// TODO maybe something more efficient?
public class ReferenceIntMap<T> extends ReferenceMap<Integer, T> {
  public ReferenceIntMap () {
    super(false);
  }

  public ReferenceIntMap (boolean isThreadSafe) {
    super(isThreadSafe);
  }

  public ReferenceIntMap (boolean isThreadSafe, ReferenceMap.FullnessListener<Integer, T> fullnessListener) {
    super(isThreadSafe, true, fullnessListener);
  }
}
