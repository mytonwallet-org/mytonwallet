/*
 * This file is a part of X-Android
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

package me.vkryl.android.animator;

import androidx.annotation.NonNull;

import java.util.ArrayList;
import java.util.Iterator;
import java.util.List;

import me.vkryl.android.AnimatorUtils;
import me.vkryl.core.ObjectUtils;
import me.vkryl.core.StringUtils;

public class CounterAnimator <T extends CounterAnimator.TextDrawable> implements Iterable<ListAnimator.Entry<CounterAnimator.Part<T>>> {
  public interface TextDrawable {
    int getWidth ();
    int getHeight ();
    String getText ();
  }

  public interface Callback<T extends TextDrawable> extends ListAnimator.MetadataCallback {
    void onItemsChanged (CounterAnimator<?> animator);
    T onCreateTextDrawable (String text, int start);
  }

  public static class Part<T extends TextDrawable> implements ListAnimator.Measurable, Animatable {
    protected final int index;
    public final T text;

    protected final VariableFloat verticalPosition = new VariableFloat(POSITION_NORMAL); // 0f = center, -1f = top, 1f = bottom
    protected int position = POSITION_NORMAL;

    public static final int POSITION_UP = -1;
    public static final int POSITION_NORMAL = 0;
    public static final int POSITION_BOTTOM = 1;

    public Part (int index, @NonNull T text) {
      this.index = index;
      this.text = text;
    }

    public float getVerticalPosition () {
      return verticalPosition.get();
    }

    @Override
    public boolean equals (Object o) {
      if (this == o) return true;
      if (o == null || getClass() != o.getClass()) return false;
      Part<?> part = (Part<?>) o;
      return index == part.index && text.equals(part.text);
    }

    @Override
    public int hashCode () {
      return ObjectUtils.hashCode(index, text.getText());
    }

    @Override
    public int getWidth () {
      return text.getWidth();
    }

    @Override
    public int getHeight () {
      return text.getHeight();
    }

    @Override
    public void finishAnimation (boolean applyFutureState) {
      verticalPosition.finishAnimation(applyFutureState);
    }

    @Override
    public boolean applyAnimation (float factor) {
      return verticalPosition.applyAnimation(factor);
    }

    @Override
    public boolean hasChanges () {
      return verticalPosition.differs(position);
    }

    @Override
    public void prepareChanges () {
      verticalPosition.setTo(position);
    }

    @Override
    public void applyChanges () {
      verticalPosition.set(position);
    }
  }

  private final Callback<T> callback;
  private final ListAnimator<Part<T>> animator;

  private long count;
  private boolean hasCounter;

  public CounterAnimator (Callback<T> callback, long duration, boolean isReverse) {
    this.callback = callback;
    this.animator = new ListAnimator<>(new ListAnimator.Callback() {
      @Override
      public boolean hasChanges(ListAnimator<?> animator) {
        return callback.hasChanges(animator);
      }

      @Override
      public void onPrepareMetadataAnimation(ListAnimator<?> animator) {
        callback.onPrepareMetadataAnimation(animator);
      }

      @Override
      public void onForceApplyChanges(ListAnimator<?> animator) {
        callback.onForceApplyChanges(animator);
      }

      @Override
      public void onFinishMetadataAnimation(ListAnimator<?> animator, boolean applyFuture) {
        callback.onFinishMetadataAnimation(animator, applyFuture);
      }

      @Override
      public boolean onApplyMetadataAnimation(ListAnimator<?> animator, float factor) {
        return callback.onApplyMetadataAnimation(animator, factor);
      }

      @Override
      public void onItemsChanged(ListAnimator<?> animator) {
        callback.onItemsChanged(CounterAnimator.this);
      }

    }, AnimatorUtils.DECELERATE_INTERPOLATOR, duration, isReverse);
  }

  public float getWidth () {
    return animator.getMetadata().getTotalWidth();
  }

  public void setCounter (long count, String textRepresentation, boolean animated) {
    setCounterImpl(count, toParts(textRepresentation), animated);
  }

  public void hideCounter (boolean animated) {
    setCounterImpl(0, null, animated);
  }

  private List<Part<T>> toParts (String textRepresentation) {
    if (!StringUtils.isEmpty(textRepresentation)) {
      List<Part<T>> parts = new ArrayList<>(textRepresentation.length());
      for (int i = 0; i < textRepresentation.length(); ) {
        int codePoint = textRepresentation.codePointAt(i);
        int charCount = Character.charCount(codePoint);
        String part = textRepresentation.substring(i, i + charCount);
        parts.add(new Part<>(parts.size(), callback.onCreateTextDrawable(part, i)));
        i += charCount;
      }
      return parts;
    }
    return null;
  }

  private void setCounterImpl (long count, List<Part<T>> parts, boolean animated) {
    final boolean hasCounter = parts != null && !parts.isEmpty();
    if (this.count != count || this.hasCounter != hasCounter) {
      final long prevCount = this.count;
      this.count = count;
      this.hasCounter = hasCounter;
      if (hasCounter) {
        this.animator.reset(parts, animated, new ListAnimator.ResetCallback<Part<T>>() {
          @Override
          public void onItemAdded (Part<T> item, boolean isReturned) {
            if (prevCount != 0 && prevCount < count) {
              item.verticalPosition.setFrom(Part.POSITION_UP);
            } else if (prevCount > count) {
              item.verticalPosition.setFrom(Part.POSITION_BOTTOM);
            }
            item.position = Part.POSITION_NORMAL;
          }

          @Override
          public void onItemRemoved (Part<T> item) {
            if (count == 0) {
              item.position = Part.POSITION_NORMAL;
            } else if (prevCount < count) {
              item.position = Part.POSITION_BOTTOM;
            } else if (prevCount > count) {
              item.position = Part.POSITION_UP;
            }
          }
        });
      } else {
        this.animator.reset(null, animated);
      }
    }
  }

  @NonNull
  @Override
  public Iterator<ListAnimator.Entry<Part<T>>> iterator () {
    return animator.iterator();
  }
}
