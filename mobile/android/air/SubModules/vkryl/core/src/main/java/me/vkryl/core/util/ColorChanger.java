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
 * File created on 06/08/2015 at 16:36
 */

package me.vkryl.core.util;

import android.graphics.Color;

import androidx.annotation.ColorInt;

public class ColorChanger {
  private @ColorInt int fromColor, toColor;
  private int fromA, fromR, fromG, fromB;
  private int aDiff, rDiff, gDiff, bDiff;
  private boolean canOverflow;

  public ColorChanger () { }

  public ColorChanger (@ColorInt int fromColor, @ColorInt int toColor) {
    this.fromColor = fromColor;
    this.toColor = toColor;
    fromA = Color.alpha(fromColor);
    fromR = Color.red(fromColor);
    fromG = Color.green(fromColor);
    fromB = Color.blue(fromColor);
    aDiff = Color.alpha(toColor) - fromA;
    rDiff = Color.red(toColor) - fromR;
    gDiff = Color.green(toColor) - fromG;
    bDiff = Color.blue(toColor) - fromB;
  }

  public void setCanOverflow () {
    this.canOverflow = true;
  }

  public void setFromTo (@ColorInt int fromColor, @ColorInt int toColor) {
    this.fromColor = fromColor;
    this.toColor = toColor;
    fromA = Color.alpha(fromColor);
    fromR = Color.red(fromColor);
    fromG = Color.green(fromColor);
    fromB = Color.blue(fromColor);
    aDiff = Color.alpha(toColor) - fromA;
    rDiff = Color.red(toColor) - fromR;
    gDiff = Color.green(toColor) - fromG;
    bDiff = Color.blue(toColor) - fromB;
  }

  public void setFrom (@ColorInt int fromColor) {
    if (this.fromColor != fromColor) {
      this.fromColor = fromColor;
      fromA = Color.alpha(fromColor);
      fromR = Color.red(fromColor);
      fromG = Color.green(fromColor);
      fromB = Color.blue(fromColor);
      aDiff = Color.alpha(toColor) - fromA;
      rDiff = Color.red(toColor) - fromR;
      gDiff = Color.green(toColor) - fromG;
      bDiff = Color.blue(toColor) - fromB;
    }
  }

  public void setTo (@ColorInt int toColor) {
    if (this.toColor != toColor) {
      this.toColor = toColor;
      aDiff = Color.alpha(toColor) - fromA;
      rDiff = Color.red(toColor) - fromR;
      gDiff = Color.green(toColor) - fromG;
      bDiff = Color.blue(toColor) - fromB;
    }
  }

  public @ColorInt int getFrom () {
    return fromColor;
  }

  public @ColorInt int getTo () {
    return toColor;
  }

  public @ColorInt int getColor (float x) {
    return x <= 0f ? fromColor : x >= 1f && !canOverflow ? toColor : Color.argb(fromA + (int) (aDiff * x), fromR + (int) (rDiff * x), fromG + (int) (gDiff * x), fromB + (int) (bDiff * x));
  }
}
