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
 * File created on 11/09/2022, 12:45.
 */

package me.vkryl.android.html;

import org.xml.sax.Attributes;
import org.xml.sax.ContentHandler;
import org.xml.sax.Locator;
import org.xml.sax.SAXException;

/**
 * Wrapper for {@link org.xml.sax.ContentHandler} that allows overriding only desired methods
 */
public class ContentHandlerWrapper implements ContentHandler {
  private final ContentHandler wrapped;

  public ContentHandlerWrapper (ContentHandler wrapped) {
    this.wrapped = wrapped;
  }

  @Override
  public void setDocumentLocator (Locator locator) {
    wrapped.setDocumentLocator(locator);
  }

  @Override
  public void startDocument () throws SAXException {
    wrapped.startDocument();
  }

  @Override
  public void endDocument () throws SAXException {
    wrapped.endDocument();
  }

  @Override
  public void startPrefixMapping (String prefix, String uri) throws SAXException {
    wrapped.startPrefixMapping(prefix, uri);
  }

  @Override
  public void endPrefixMapping (String prefix) throws SAXException {
    wrapped.endPrefixMapping(prefix);
  }

  @Override
  public void startElement (String uri, String localName, String qName, Attributes atts) throws SAXException {
    wrapped.startElement(uri, localName, qName, atts);
  }

  @Override
  public void endElement (String uri, String localName, String qName) throws SAXException {
    wrapped.endElement(uri, localName, qName);
  }

  @Override
  public void characters (char[] ch, int start, int length) throws SAXException {
    wrapped.characters(ch, start, length);
  }

  @Override
  public void ignorableWhitespace (char[] ch, int start, int length) throws SAXException {
    wrapped.ignorableWhitespace(ch, start, length);
  }

  @Override
  public void processingInstruction (String target, String data) throws SAXException {
    wrapped.processingInstruction(target, data);
  }

  @Override
  public void skippedEntity (String name) throws SAXException {
    wrapped.skippedEntity(name);
  }
}
