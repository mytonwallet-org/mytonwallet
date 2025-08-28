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
 *
 * File created on 11/09/2022, 12:41.
 */

package me.vkryl.android.html;

import android.text.SpannableStringBuilder;
import android.text.Spanned;
import android.view.inputmethod.BaseInputConnection;

import java.util.ArrayList;
import java.util.List;

import me.vkryl.core.StringUtils;

public class HtmlEncoder {
  public interface SpanHandler<T> {
    HtmlTag[] toHtmlTag (T span);
  }

  public static class EncodeResult {
    public final String htmlText;
    public final int tagCount;

    public EncodeResult (String htmlText, int tagCount) {
      this.htmlText = htmlText;
      this.tagCount = tagCount;
    }
  }

  public static <T> EncodeResult toHtml (CharSequence charSequence, Class<T> spanKind, SpanHandler<T> spanHandler) {
    return toHtml(charSequence, 0, charSequence.length(), spanKind, spanHandler);
  }

  public static <T> EncodeResult toHtml (CharSequence charSequence, int start, int end, Class<T> spanKind, SpanHandler<T> spanHandler) {
    if (!(charSequence instanceof Spanned)) {
      String text = (start != 0 || end != charSequence.length()) ?
        charSequence.subSequence(start, end).toString() :
        charSequence.toString();
      return new EncodeResult(text, 0);
    }
    SpannableStringBuilder text = new SpannableStringBuilder(charSequence);
    BaseInputConnection.removeComposingSpans(text);

    int tagCount = 0;
    StringBuilder out = new StringBuilder();
    int next;
    for (int i = start; i < end; i = next) {
      next = text.nextSpanTransition(i, end, spanKind);
      T[] spans = text.getSpans(i, next, spanKind);
      if (spans == null || spans.length == 0) {
        withinStyle(out, text, i, next);
        continue;
      }
      List<HtmlTag> tagsToClose = new ArrayList<>();
      for (T span : spans) {
        HtmlTag[] tags = spanHandler.toHtmlTag(span);
        if (tags != null) {
          for (HtmlTag tag : tags) {
            tagCount++;
            out.append(tag.openTag);
            if (!StringUtils.isEmpty(tag.closeTag)) {
              tagsToClose.add(tag);
            }
          }
        }
      }
      withinStyle(out, text, i, next);
      for (int tagIndex = tagsToClose.size() - 1; tagIndex >= 0; tagIndex--) {
        out.append(tagsToClose.get(tagIndex).closeTag);
      }
    }
    return new EncodeResult(out.toString(), tagCount);
  }

  // Copy of:
  // https://android.googlesource.com/platform/frameworks/base/+/f63f20af/core/java/android/text/Html.java#636
  private static void withinStyle (StringBuilder out, CharSequence text,
                                   int start, int end) {
    for (int i = start; i < end; i++) {
      char c = text.charAt(i);

      if (c == '\n') {
        // modified: treat all new lines as <br/> tag
        out.append("<br/>");
      } else if (c == '<') {
        out.append("&lt;");
      } else if (c == '>') {
        out.append("&gt;");
      } else if (c == '&') {
        out.append("&amp;");
      } else if (c >= 0xD800 && c <= 0xDFFF) {
        if (c < 0xDC00 && i + 1 < end) {
          char d = text.charAt(i + 1);
          if (d >= 0xDC00 && d <= 0xDFFF) {
            i++;
            int codepoint = 0x010000 | (int) c - 0xD800 << 10 | (int) d - 0xDC00;
            out.append("&#").append(codepoint).append(";");
          }
        }
      } else if (c > 0x7E || c < ' ') {
        out.append("&#").append((int) c).append(";");
      } else if (c == ' ') {
        while (i + 1 < end && text.charAt(i + 1) == ' ') {
          out.append("&nbsp;");
          i++;
        }

        out.append(' ');
      } else {
        out.append(c);
      }
    }
  }
}
