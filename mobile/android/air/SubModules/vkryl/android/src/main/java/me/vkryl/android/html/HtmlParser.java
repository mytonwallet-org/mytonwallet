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

import android.os.Build;
import android.text.Editable;
import android.text.Html;
import android.text.Spannable;
import android.text.Spanned;

import androidx.annotation.NonNull;
import androidx.annotation.Nullable;

import org.xml.sax.Attributes;
import org.xml.sax.SAXException;
import org.xml.sax.XMLReader;

import java.util.ArrayDeque;

public class HtmlParser {
  public interface TagHandler {
    boolean handleTag (boolean opening, String tag,
                       Editable output, XMLReader xmlReader,
                       Attributes attributes);
  }

  private static final String ROOT_TAG_NAME = "tg-unsupported";

  @SuppressWarnings("deprecation")
  public static CharSequence fromHtml (String htmlText, @Nullable Html.ImageGetter imageGetter, @Nullable TagHandler handler) {
    Html.TagHandler tagHandler;
    if (handler != null) {
      tagHandler = new HtmlTagHandler(ROOT_TAG_NAME, handler);
      // Wrap with unknown tag to force handleTag to be called
      htmlText = "<" + ROOT_TAG_NAME + ">" + htmlText + "</" + ROOT_TAG_NAME + ">";
    } else {
      tagHandler = null;
    }
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
      return Html.fromHtml(
        htmlText,
        Html.FROM_HTML_MODE_COMPACT,
        imageGetter,
        tagHandler
      );
    } else {
      return Html.fromHtml(
        htmlText,
        imageGetter,
        tagHandler
      );
    }
  }

  private static class HtmlTagHandler implements Html.TagHandler {
    private final String rootTagName;
    @NonNull
    private final TagHandler tagHandler;

    public HtmlTagHandler (String rootTagName, @NonNull TagHandler tagHandler) {
      this.rootTagName = rootTagName;
      this.tagHandler = tagHandler;
    }

    private ContentHandlerWrapper wrapped;

    @Override
    public void handleTag (boolean opening, String tag, Editable output, XMLReader xmlReader) {
      if (wrapped == null) {
        if (!tag.equalsIgnoreCase(rootTagName))
          throw new IllegalArgumentException(tag);
        ArrayDeque<Boolean> tagStatus = new ArrayDeque<>();
        wrapped = new ContentHandlerWrapper(xmlReader.getContentHandler()) {
          @Override
          public void startElement (String uri, String localName, String qName, Attributes attributes) throws SAXException {
            boolean isHandled = tagHandler.handleTag(true, localName, output, xmlReader, attributes);
            tagStatus.addLast(isHandled);
            if (!isHandled) {
              super.startElement(uri, localName, qName, attributes);
            }
          }

          @Override
          public void endElement (String uri, String localName, String qName) throws SAXException {
            if (!tagStatus.removeLast()) {
              super.endElement(uri, localName, qName);
            }
            if (!tagStatus.isEmpty()) { // empty when processing rootTagName
              tagHandler.handleTag(false, localName, output, xmlReader, null);
            } else if (!localName.equals(rootTagName)) {
              throw new IllegalArgumentException(localName);
            }
          }
        };
        xmlReader.setContentHandler(wrapped);
        tagStatus.addLast(Boolean.FALSE);
      }
    }
  }

  public interface Replacer<T> {
    void onReplaceSpanMark (Spannable text, int start, int end, T mark);
  }

  public static <T> void end (Editable text, Class<T> markKind, Replacer<T> replacer) {
    T mark = getLast(text, markKind);
    if (mark != null) {
      int where = text.getSpanStart(mark);
      text.removeSpan(mark);
      int len = text.length();
      if (where != len) {
        replacer.onReplaceSpanMark(text, where, len, mark);
      }
    }
  }

  // Copy of:
  // https://android.googlesource.com/platform/frameworks/base/+/f63f20af/core/java/android/text/Html.java#1074

  public static <T> void start (Editable text, T mark) {
    int len = text.length();
    text.setSpan(mark, len, len, Spannable.SPAN_INCLUSIVE_EXCLUSIVE);
  }

  private static <T> T getLast (Spanned text, Class<T> kind) {
    T[] objs = text.getSpans(0, text.length(), kind);
    if (objs == null || objs.length == 0) {
      return null;
    } else {
      return objs[objs.length - 1];
    }
  }
}
