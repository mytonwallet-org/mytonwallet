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
 */

@file:JvmName("ObjectUtils")
@file:Suppress("SuspiciousEqualsCombination")

package me.vkryl.core

fun <T> requireNonNull (value: T?): T {
  if (value == null) {
    error("value is null")
  }
  return value
}

fun <T> equals (a: T?, b: T?): Boolean = a === b || (a != null && a == b)

fun hash (vararg a: Int): Int = a.contentHashCode()
fun hashCode (vararg a: Any?): Int = a.contentHashCode()