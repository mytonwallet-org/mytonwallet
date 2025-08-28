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
 * File created on 11/09/2022, 23:00.
 */

package me.vkryl.core.util;

import androidx.annotation.Nullable;

import me.vkryl.core.StringUtils;

public class Transliterator {
  public static boolean hasCyrillicLetters (String str) {
    return hasCyrillicLetters(str, 0, str.length());
  }

  public static boolean hasCyrillicLetters (String str, int start, int end) {
    for (int i = start; i < end;) {
      int codePoint = str.codePointAt(i);
      if (isCyrillicLetter(codePoint))
        return true;
      i += Character.charCount(codePoint);
    }
    return false;
  }

  public static boolean hasLatinLetters (String str) {
    return hasLatinLetters(str, 0, str.length());
  }

  public static boolean hasLatinLetters (String str, int start, int end) {
    for (int i = start; i < end;) {
      int codePoint = str.codePointAt(i);
      if (isLatinLatter(codePoint))
        return true;
      i += Character.charCount(codePoint);
    }
    return false;
  }
  
  public static boolean isLatinLatter (int codePoint) {
    switch (codePoint) {
      case 'A': case 'a':
      case 'B': case 'b':
      case 'C': case 'c':
      case 'D': case 'd':
      case 'E': case 'e':
      case 'F': case 'f':
      case 'G': case 'g':
      case 'H': case 'h':
      case 'I': case 'i':
      case 'J': case 'j':
      case 'K': case 'k':
      case 'L': case 'l':
      case 'M': case 'm':
      case 'N': case 'n':
      case 'O': case 'o':
      case 'P': case 'p':
      case 'Q': case 'q':
      case 'R': case 'r':
      case 'S': case 's':
      case 'T': case 't':
      case 'U': case 'u':
      case 'V': case 'v':
      case 'W': case 'w':
      case 'X': case 'x':
      case 'Y': case 'y':
      case 'Z': case 'z':
        return true;
    }
    return false;
  }

  public static boolean isCyrillicLetter (int codePoint) {
    switch (codePoint) {
      case 'А': case 'а':
      case 'Б': case 'б':
      case 'В': case 'в':
      case 'Г': case 'г':
      case 'Д': case 'д':
      case 'Е': case 'е':
      case 'Ё': case 'ё':
      case 'Ж': case 'ж':
      case 'З': case 'з':
      case 'И': case 'и':
      case 'Й': case 'й':
      case 'К': case 'к':
      case 'Л': case 'л':
      case 'М': case 'м':
      case 'Н': case 'н':
      case 'О': case 'о':
      case 'П': case 'п':
      case 'Р': case 'р':
      case 'С': case 'с':
      case 'Т': case 'т':
      case 'У': case 'у':
      case 'Ф': case 'ф':
      case 'Х': case 'х':
      case 'Ц': case 'ц':
      case 'Ч': case 'ч':
      case 'Ш': case 'ш':
      case 'Щ': case 'щ':
      case 'Ъ': case 'ъ':
      case 'Ы': case 'ы':
      case 'Ь': case 'ь':
      case 'Э': case 'э':
      case 'Ю': case 'ю':
      case 'Я': case 'я': {
        return true;
      }
    }
    return false;
  }

  public static String latinToCyrillic (String latin) {
    StringBuilder b = new StringBuilder();
    for (int i = 0; i < latin.length(); ) {
      int codePoint = latin.codePointAt(i);
      int codePointSize = Character.charCount(codePoint);
      int nextCodePoint = i + codePointSize < latin.length() ? latin.codePointAt(i + codePointSize) : 0;
      int nextCodePointSize = nextCodePoint != 0 ? Character.charCount(nextCodePoint) : 0;

      int addSize = codePointSize;

      switch (codePoint) {
        case 'A': b.append('А'); break;
        case 'a': b.append('а'); break;
        case 'B': b.append('Б'); break;
        case 'b': b.append('б'); break;
        case 'D': b.append('Д'); break;
        case 'd': b.append('д'); break;
        case 'E': b.append('Е'); break;
        case 'e': b.append('е'); break;
        case 'F': b.append('Ф'); break;
        case 'f': b.append('ф'); break;
        case 'G': b.append('Г'); break;
        case 'g': b.append('г'); break;
        case 'H': b.append('Х'); break;
        case 'h': b.append('х'); break;
        case 'J': b.append("Дж"); break;
        case 'j': b.append("дж"); break;
        case 'K': b.append('K'); break;
        case 'k': b.append('к'); break;
        case 'L': b.append('Л'); break;
        case 'l': b.append('л'); break;
        case 'M': b.append('М'); break;
        case 'm': b.append('м'); break;
        case 'N': b.append('Н'); break;
        case 'n': b.append('н'); break;
        case 'O': b.append('О'); break;
        case 'o': b.append('о'); break;
        case 'R': b.append('Р'); break;
        case 'r': b.append('р'); break;
        case 'U': b.append('У'); break;
        case 'u': b.append('у'); break;
        case 'V': b.append('В'); break;
        case 'v': b.append('в'); break;
        case 'Q': b.append('К'); break;
        case 'q': b.append('к'); break;
        case 'X': b.append("Кс"); break;
        case 'x': b.append("кс"); break;
        case 'T': case 't': {
          // Th -> З, T -> Т
          boolean isUpperCase = codePoint == 'T';
          switch (nextCodePoint) {
            case 'H': case 'h': b.append(isUpperCase ? 'З' : 'з'); addSize += nextCodePointSize; break;
            default: b.append(isUpperCase ? 'Т' : 'т'); break;
          }
          break;
        }
        case 'P': case 'p': {
          // Ph -> Ф, else -> П
          boolean isUpperCase = codePoint == 'P';
          switch (nextCodePoint) {
            case 'H': case 'h': b.append(isUpperCase ? 'Ф' : 'ф'); addSize += nextCodePointSize; break;
            default: b.append(isUpperCase ? 'П' : 'п'); break;
          }
          break;
        }
        case 'Z': case 'z': {
          // Zh -> Ж, else -> З
          boolean isUpperCase = codePoint == 'Z';
          switch (nextCodePoint) {
            case 'H': case 'h': b.append(isUpperCase ? 'Ж' : 'ж'); addSize += nextCodePointSize; break;
            default: b.append(isUpperCase ? 'З' : 'з'); break;
          }
          break;
        }
        case 'W': case 'w': {
          // Wh, else -> В
          boolean isUpperCase = codePoint == 'W';
          if (nextCodePoint == 'H' || nextCodePoint == 'h') {
            addSize += nextCodePointSize;
          }
          b.append(isUpperCase ? 'В' : 'в');
          break;
        }
        case 'C': case 'c': {
          // Ch -> Ч, Ce -> Се, Сi -> Си, else -> К
          boolean isUpperCase = codePoint == 'C';
          switch (nextCodePoint) {
            case 'H': case 'h': b.append(isUpperCase ? 'Ч' : 'ч'); addSize += nextCodePointSize; break;
            case 'E': case 'e': b.append(isUpperCase ? "Се" : "се"); addSize += nextCodePointSize; break;
            case 'I': case 'o': b.append(isUpperCase ? "Си" : "си"); addSize += nextCodePointSize; break;
            default: b.append(isUpperCase ? 'К' : 'к'); break;
          }
          break;
        }
        case 'S': case 's': {
          // Sch -> Щ, Sh -> Ш, else -> С
          boolean isUpperCase = codePoint == 'S';
          switch (nextCodePoint) {
            case 'H': case 'h': b.append(isUpperCase ? 'Ш' : 'ш'); addSize += nextCodePointSize; break;
            case 'C': case 'c': {
              int afterNextCodePoint = i + codePointSize + nextCodePointSize < latin.length() ? latin.codePointAt(i + codePointSize + nextCodePointSize) : 0;
              if (afterNextCodePoint == 'H' || afterNextCodePoint == 'h') {
                b.append(isUpperCase ? 'Щ' : 'щ');
                addSize += nextCodePointSize + Character.charCount(afterNextCodePoint);
              } else {
                // default:
                b.append(isUpperCase ? 'С' : 'с');
              }
              break;
            }
            default: b.append(isUpperCase ? 'С' : 'с'); break;
          }
          break;
        }
        case 'Y': case 'y': {
          // Ya -> Я, Yo -> Ё, Yu -> Ю, else -> Й
          boolean isUpperCase = codePoint == 'Y';
          switch (nextCodePoint) {
            case 'A': case 'a': b.append(isUpperCase ? 'Я' : 'я'); addSize += nextCodePointSize; break;
            case 'O': case 'o': b.append(isUpperCase ? 'Ё' : 'ё'); addSize += nextCodePointSize; break;
            case 'U': case 'u': b.append(isUpperCase ? 'Ю' : 'ю'); addSize += nextCodePointSize; break;
            case 'Y': case 'y': b.append(isUpperCase ? "Ый" : "ый"); addSize += nextCodePointSize; break;
            default: {
              if (i + codePointSize + nextCodePointSize == latin.length()) {
                b.append(isUpperCase ? 'Й' : 'й');
              } else {
                b.append(isUpperCase ? 'Ы' : 'ы');
              }
              break;
            }
          }
          break;
        }
        case 'I': case 'i': {
          // Ight -> Айт, Ia -> Я, Iu -> Ю, Io -> Ё, else -> И
          boolean isUpperCase = codePoint == 'I';
          switch (nextCodePoint) {
            case 'A': case 'a': b.append(isUpperCase ? 'Я' : 'я'); addSize += nextCodePointSize; break;
            case 'O': case 'o': b.append(isUpperCase ? 'Ё' : 'ё'); addSize += nextCodePointSize; break;
            case 'U': case 'u': b.append(isUpperCase ? 'Ю' : 'ю'); addSize += nextCodePointSize; break;
            case 'Y': case 'y': b.append(isUpperCase ? "Ий" : "ий"); addSize += nextCodePointSize; break;
            case 'G': case 'g': {
              boolean processed = false;
              if (latin.length() - (i + codePointSize + nextCodePointSize) >= 2) {
                char c1 = latin.charAt(i + codePointSize + nextCodePointSize);
                char c2 = latin.charAt(i + codePointSize + nextCodePointSize + 1);
                if ((c1 == 'H' || c1 == 'h') && (c2 == 'T' || c2 == 't')) {
                  b.append(isUpperCase ? "Айт" : "айт");
                  addSize += nextCodePointSize + 2;
                  processed = true;
                }
              }
              if (!processed) {
                // default:
                if (i + codePointSize + nextCodePointSize == latin.length()) {
                  b.append(isUpperCase ? 'Й' : 'й');
                } else {
                  b.append(isUpperCase ? 'И' : 'и');
                }
              }
              break;
            }
            default:  {
              if (i + codePointSize + nextCodePointSize == latin.length()) {
                b.append(isUpperCase ? 'Й' : 'й');
              } else {
                b.append(isUpperCase ? 'И' : 'и');
              }
              break;
            }
          }
          break;
        }
        default: {
          b.appendCodePoint(codePoint);
          break;
        }
      }
      i += addSize;
    }
    return b.toString();
  }

  public static String cyrillicToLatin (String cyrillic) {
    StringBuilder b = new StringBuilder();
    for (int i = 0; i < cyrillic.length(); ) {
      int codePoint = cyrillic.codePointAt(i);
      int codePointSize = Character.charCount(codePoint);
      int nextCodePoint = i + codePointSize < cyrillic.length() ? cyrillic.codePointAt(i + codePointSize) : 0;
      int nextCodePointSize = nextCodePoint != 0 ? Character.charCount(nextCodePoint) : 0;

      int addSize = codePointSize;
      
      switch (codePoint) {
        case 'А': b.append('A'); break;
        case 'а': b.append('a'); break;
        case 'Б': b.append('B'); break;
        case 'б': b.append('b'); break;
        case 'В': b.append('V'); break;
        case 'в': b.append('v'); break;
        case 'Г': b.append('G'); break;
        case 'г': b.append('g'); break;
        case 'Е': b.append('E'); break;
        case 'е': b.append('e'); break;
        case 'Ё': b.append("Yo"); break;
        case 'ё': b.append("yo"); break;
        case 'Ж': b.append("Zh"); break;
        case 'ж': b.append("zh"); break;
        case 'З': b.append('Z'); break;
        case 'з': b.append('z'); break;
        case 'И': b.append('I'); break;
        case 'и': b.append('i'); break;
        case 'Й': b.append('Y'); break;
        case 'й': b.append('y'); break;
        case 'К': b.append('K'); break;
        case 'к': b.append('k'); break;
        case 'Л': b.append('L'); break;
        case 'л': b.append('l'); break;
        case 'М': b.append('M'); break;
        case 'м': b.append('m'); break;
        case 'Н': b.append('N'); break;
        case 'н': b.append('n'); break;
        case 'О': b.append('O'); break;
        case 'о': b.append('o'); break;
        case 'П': b.append('P'); break;
        case 'п': b.append('p'); break;
        case 'Р': b.append('R'); break;
        case 'р': b.append('r'); break;
        case 'С': b.append('S'); break;
        case 'с': b.append('s'); break;
        case 'Т': b.append('T'); break;
        case 'т': b.append('t'); break;
        case 'У': b.append('U'); break;
        case 'у': b.append('u'); break;
        case 'Ф': b.append('F'); break;
        case 'ф': b.append('f'); break;
        case 'Х': b.append('H'); break;
        case 'х': b.append('h'); break;
        case 'Ц': b.append("Ts"); break;
        case 'ц': b.append("ts"); break;
        case 'Ч': b.append("Ch"); break;
        case 'ч': b.append("ch"); break;
        case 'Ш': b.append("Sh"); break;
        case 'ш': b.append("sh"); break;
        case 'Щ': b.append("Sch"); break;
        case 'щ': b.append("sch"); break;
        case 'Ы': b.append("Y"); break;
        case 'ы': b.append("y"); break;
        case 'Э': b.append("E"); break;
        case 'э': b.append("e"); break;
        case 'Ю': b.append("Yu"); break;
        case 'ю': b.append("yu"); break;
        case 'Я': b.append("Ya"); break;
        case 'я': b.append("ya"); break;
        case 'Д': case 'д': {
          boolean isUpperCase = codePoint == 'Д';
          switch (nextCodePoint) {
            case 'Ж': case 'ж': b.append(isUpperCase ? 'J' : 'j'); addSize += nextCodePointSize; break;
            default: b.append('D'); break;
          }
          break;
        }
        case 'Ъ': case 'ъ':
        case 'Ь': case 'ь': break;
        default: {
          b.appendCodePoint(codePoint);
          break;
        }
      }
      
      i += addSize;
    }
    return b.toString();
  }

  public static class PrefixResult {
    public final int contentLength;
    public final int prefixLength;

    public PrefixResult (int contentLength, int prefixLength) {
      this.contentLength = contentLength;
      this.prefixLength = prefixLength;
    }
  }

  private static boolean isSeparatorCodePoint (int codePoint) {
    int codePointType = Character.getType(codePoint);
    switch (codePointType) {
      case Character.SPACE_SEPARATOR:
      case Character.LINE_SEPARATOR:
      case Character.CONTROL:
        return true;
    }
    return false;
  }

  @Nullable
  public static PrefixResult findPrefix (String content, int start, int end,
                                         String prefix, int prefixStart, int prefixEnd) {
    int prefixLength = 0;
    int contentLength = 0;

    int prefixSeparatorLength = 0;
    int contentSeparatorLength = 0;

    while (start + contentLength < end && prefixStart + prefixLength < prefixEnd) {
      int contentCodePoint = content.codePointAt(start + contentLength);
      int contentCodePointSize = Character.charCount(contentCodePoint);
      boolean contentCodePointIsSeparator = isSeparatorCodePoint(contentCodePoint);

      int prefixCodePoint = prefix.codePointAt(prefixStart + prefixLength);
      int prefixCodePointSize = Character.charCount(prefixCodePoint);
      boolean prefixCodePointIsSeparator = isSeparatorCodePoint(prefixCodePoint);

      if (contentCodePoint == prefixCodePoint || (contentCodePointIsSeparator && prefixCodePointIsSeparator) || StringUtils.normalizeCodePoint(contentCodePoint) == StringUtils.normalizeCodePoint(prefixCodePoint)) {
        contentLength += contentCodePointSize;
        prefixLength += prefixCodePointSize;
        if (contentCodePointIsSeparator && prefixCodePointIsSeparator) {
          contentSeparatorLength += contentCodePointSize;
          prefixSeparatorLength += prefixCodePointSize;
        }
        continue;
      }

      int nextContentCodePointIndex = (start + contentLength + contentCodePointSize);
      int nextContentCodePoint = nextContentCodePointIndex < end ? content.codePointAt(nextContentCodePointIndex) : 0;
      int nextContentCodePointSize = Character.charCount(nextContentCodePoint);

      int nextPrefixCodePointIndex = (prefixStart + prefixLength + prefixCodePointSize);
      int nextPrefixCodePoint = nextPrefixCodePointIndex < prefixEnd ? prefix.codePointAt(nextPrefixCodePointIndex) : 0;
      int nextPrefixCodePointSize = nextPrefixCodePoint != 0 ? Character.charCount(nextPrefixCodePoint) : 0;

      int addContentSize = 0;
      int addPrefixSize = 0;
      boolean ok = false;

      if (isLatinLatter(prefixCodePoint) && isCyrillicLetter(contentCodePoint)) {
        switch (prefixCodePoint) {
          case 'D': case 'd':
            ok = contentCodePoint == 'Д' || contentCodePoint == 'д';
            break;
          case 'B': case 'b':
            ok = contentCodePoint == 'Б' || contentCodePoint == 'б';
            break;
          case 'F': case 'f':
            ok = contentCodePoint == 'Ф' || contentCodePoint == 'ф';
            break;
          case 'H': case 'h':
            ok = contentCodePoint == 'Х' || contentCodePoint == 'х';
            break;
          case 'K': case 'k':
            ok = contentCodePoint == 'К' || contentCodePoint == 'к';
            break;
          case 'L': case 'l':
            ok = contentCodePoint == 'Л' || contentCodePoint == 'л';
            break;
          case 'M': case 'm':
            ok = contentCodePoint == 'М' || contentCodePoint == 'м';
            break;
          case 'N': case 'n':
            ok = contentCodePoint == 'Н' || contentCodePoint == 'н';
            break;
          case 'R': case 'r':
            ok = contentCodePoint == 'Р' || contentCodePoint == 'р';
            break;
          case 'V': case 'v':
            ok = contentCodePoint == 'В' || contentCodePoint == 'в';
            break;
          case 'W': case 'w':
            switch (contentCodePoint) {
              case 'В': case 'в':
                ok = true;
                break;
              case 'У': case 'у':
                if (nextContentCodePoint == 'А' || nextContentCodePoint == 'а') {
                  addPrefixSize = prefixCodePointSize;
                  addContentSize = contentCodePointSize + nextContentCodePointSize;
                }
                break;
            }
            break;
          case 'U': case 'u':
            switch (contentCodePoint) {
              case 'У': case 'у':
              case 'А': case 'а':
              case 'Ю': case 'ю':
                ok = true;
                break;
            }
            break;
          case 'T': case 't': {
            // T -> Т, Th -> З
            switch (contentCodePoint) {
              case 'Т': case 'т':
                addPrefixSize = prefixCodePointSize;
                addContentSize = contentCodePointSize;
                break;
              case 'З': case 'з':
                if (nextPrefixCodePoint == 'H' || nextPrefixCodePoint == 'h') {
                  addPrefixSize = prefixCodePointSize + nextPrefixCodePointSize;
                  addContentSize = contentCodePointSize;
                }
                break;
            }
          }
          case 'P': case 'p': {
            // P -> П, Ph -> Ф
            switch (contentCodePoint) {
              case 'П': case 'п':
                addPrefixSize = prefixCodePointSize;
                addContentSize = contentCodePointSize;
                break;
              case 'Ф': case 'ф':
                if (nextPrefixCodePoint == 'H' || nextPrefixCodePoint == 'h') {
                  addPrefixSize = prefixCodePointSize + nextPrefixCodePointSize;
                  addContentSize = contentCodePointSize;
                }
                break;
            }
          }
          case 'G': case 'g': {
            switch (contentCodePoint) {
              case 'Г': case 'г':
                addPrefixSize = prefixCodePointSize;
                addContentSize = contentCodePointSize;
                break;
              case 'Д': case 'д':
                if (nextContentCodePoint == 'Ж' || nextContentCodePoint == 'ж') {
                  addPrefixSize = prefixCodePointSize;
                  addContentSize = contentCodePointSize + nextContentCodePointSize;
                }
                break;
            }
            break;
          }
          case 'J': case 'j': {
            switch (contentCodePoint) {
              case 'Ж': case 'ж':
                addPrefixSize = prefixCodePointSize;
                addContentSize = contentCodePointSize;
                break;
              case 'Д': case 'д':
                if (nextContentCodePoint == 'Ж' || nextContentCodePoint == 'ж') {
                  addPrefixSize = prefixCodePointSize;
                  addContentSize = contentCodePointSize + nextContentCodePointSize;
                }
                break;
            }
          }
          case 'Z': case 'z': {
            // Z -> З, Zh -> Ж
            switch (contentCodePoint) {
              case 'З': case 'з':
                addPrefixSize = prefixCodePointSize;
                addContentSize = contentCodePointSize;
                break;
              case 'Ж': case 'ж':
                if (nextPrefixCodePoint == 'H' || nextPrefixCodePoint == 'h') {
                  addPrefixSize = prefixCodePointSize + nextPrefixCodePointSize;
                  addContentSize = contentCodePointSize;
                }
                break;
            }
            break;
          }
          case 'S': case 's': {
            // S -> С, Sh -> Ш, Sch -> Щ
            switch (contentCodePoint) {
              case 'С': case 'с':
                addPrefixSize = prefixCodePointSize;
                addContentSize = contentCodePointSize;
                break;
              case 'Ш': case 'ш':
              case 'Щ': case 'щ':
                if (nextPrefixCodePoint == 'H' || nextPrefixCodePoint == 'h') {
                  addPrefixSize = prefixCodePointSize + nextPrefixCodePointSize;
                  addContentSize = contentCodePointSize;
                } else if ((contentCodePoint == 'Щ' || contentCodePoint == 'щ') &&
                  (nextPrefixCodePoint == 'C' || nextPrefixCodePoint == 'c')) {
                  int afterNextPrefixCodePointIndex = nextPrefixCodePointIndex + nextPrefixCodePointSize;
                  int afterNextPrefixCodePoint = afterNextPrefixCodePointIndex < prefixEnd ? prefix.codePointAt(afterNextPrefixCodePointIndex) : 0;
                  if (afterNextPrefixCodePoint == 'H' || afterNextPrefixCodePoint == 'h') {
                    addPrefixSize = prefixCodePointSize + nextPrefixCodePointSize + Character.charCount(afterNextPrefixCodePoint);
                    addContentSize = contentCodePointSize;
                  }
                }
                break;
            }
            break;
          }
          case 'C': case 'c': {
            // C -> К, С, Ц, Ch -> Ч, Ck -> К
            switch (contentCodePoint) {
              case 'С': case 'c':
              case 'Ц': case 'ц':
                addPrefixSize = prefixCodePointSize;
                addContentSize = contentCodePointSize;
                break;
              case 'К': case 'к':
                addPrefixSize = prefixCodePointSize;
                addContentSize = contentCodePointSize;
                if ((nextPrefixCodePoint == 'K' || nextPrefixCodePoint == 'k') && !(nextContentCodePoint == 'К' || nextContentCodePoint == 'к')) {
                  addPrefixSize += nextPrefixCodePointSize;
                }
                break;
              case 'Ч': case 'ч':
                if (nextPrefixCodePoint == 'H' || nextPrefixCodePoint == 'h') {
                  addPrefixSize = prefixCodePointSize + nextPrefixCodePointSize;
                  addContentSize = contentCodePointSize;
                }
                break;
            }
          }
          case 'A': case 'a': {
            // A -> А, Э, Эй
            switch (contentCodePoint) {
              case 'А': case 'а':
                addPrefixSize = prefixCodePointSize;
                addContentSize = contentCodePointSize;
                break;
              case 'Э': case 'э':
                addPrefixSize = prefixCodePointSize;
                addContentSize = contentCodePointSize;
                if (nextContentCodePoint == 'Й' || nextContentCodePoint == 'й') {
                  addContentSize += nextContentCodePointSize;
                  if (nextPrefixCodePoint == 'I' || nextPrefixCodePoint == 'i' ||
                    nextPrefixCodePoint == 'Y' || nextPrefixCodePointSize == 'y') {
                    addPrefixSize += nextPrefixCodePointSize;
                  }
                }
                break;
            }
            break;
          }
          case 'O': case 'o': {
            // O -> О, Оу
            // Oo -> У
            switch (contentCodePoint) {
              case 'О': case 'о':
                addPrefixSize = prefixCodePointSize;
                addContentSize = contentCodePointSize;
                if ((nextContentCodePoint == 'У' || nextContentCodePoint == 'у') &&
                   !(nextPrefixCodePoint == 'U' || nextPrefixCodePoint == 'u')) {
                  addContentSize += nextContentCodePointSize;
                }
                break;
              case 'У': case 'у':
                if (nextPrefixCodePoint == 'O' || nextPrefixCodePoint == 'o') {
                  addPrefixSize = prefixCodePointSize + nextPrefixCodePointSize;
                  addContentSize = contentCodePointSize;
                }
                break;
            }
            break;
          }
          case 'X': case 'x': {
            // X -> Кс, Икс
            switch (contentCodePoint) {
              case 'К': case 'к':
                if (nextContentCodePoint == 'С' || nextContentCodePoint == 'с') {
                  addPrefixSize = prefixCodePointSize;
                  addContentSize = contentCodePointSize + nextContentCodePointSize;
                }
                break;
              case 'И': case 'и': {
                if (nextContentCodePoint == 'К' || nextContentCodePoint == 'к') {
                  int afterNextContentCodePointIndex = nextContentCodePointIndex + nextContentCodePointSize;
                  int afterNextContentCodePoint = afterNextContentCodePointIndex < end ? content.codePointAt(afterNextContentCodePointIndex) : 0;
                  if (afterNextContentCodePoint == 'С' || afterNextContentCodePoint == 'с') {
                    addPrefixSize = prefixCodePointSize;
                    addContentSize = contentCodePointSize + nextContentCodePointSize + Character.charCount(afterNextContentCodePoint);
                  }
                }
                break;
              }
            }
            break;
          }
          case 'E': case 'e': {
            switch (contentCodePoint) {
              case 'Е': case 'е':
              case 'Э': case 'э':
                addPrefixSize = prefixCodePointSize;
                addContentSize = contentCodePointSize;
                break;
              case 'И': case 'и':
                addPrefixSize = prefixCodePointSize;
                addContentSize = contentCodePointSize;
                if ((nextPrefixCodePoint == 'E' || nextPrefixCodePoint == 'e') && !(
                  nextContentCodePoint == 'Е' || nextContentCodePoint == 'е' ||
                  nextContentCodePoint == 'Э' || nextContentCodePoint == 'э' ||
                  nextContentCodePoint == 'И' || nextContentCodePoint == 'и'
                  )) {
                  addPrefixSize += nextPrefixCodePointSize;
                }
                break;
            }
          }

          case 'Y': case 'y':
            switch (contentCodePoint) {
              case 'Й': case 'й':
              case 'Ь': case 'ь':
              case 'Ъ': case 'ъ':
              case 'Ы': case 'ы':
                ok = true;
                break;
              case 'Я': case 'я':
                if (nextPrefixCodePoint == 'A' || nextPrefixCodePoint == 'a') {
                  addPrefixSize = prefixCodePointSize + nextPrefixCodePointSize;
                  addContentSize = contentCodePointSize;
                }
                break;
              case 'Ю': case 'ю':
                if (nextPrefixCodePoint == 'U' || nextPrefixCodePoint == 'u') {
                  addPrefixSize = prefixCodePointSize + nextPrefixCodePointSize;
                  addContentSize = contentCodePointSize;
                }
                break;
              case 'Е': case 'е':
                if (nextPrefixCodePoint == 'E' || nextPrefixCodePoint == 'e') {
                  addPrefixSize = prefixCodePointSize + nextPrefixCodePointSize;
                  addContentSize = contentCodePointSize;
                }
                break;
            }
            break;
          case 'I': case 'i':
            switch (contentCodePoint) {
              case 'И': case 'и':
                ok = true;
                break;
              case 'А': case 'а':
                if (nextContentCodePoint == 'Й' || nextContentCodePoint == 'й') {
                  addPrefixSize = prefixCodePointSize;
                  addContentSize = contentCodePointSize + nextContentCodePointSize;
                }
                break;
              case 'Я': case 'я':
                if (nextPrefixCodePoint == 'A' || nextPrefixCodePoint == 'a') {
                  addPrefixSize = prefixCodePointSize + nextPrefixCodePointSize;
                  addContentSize = contentCodePointSize;
                }
                break;
              case 'Ю': case 'ю':
                if (nextPrefixCodePoint == 'U' || nextPrefixCodePoint == 'u') {
                  addPrefixSize = prefixCodePointSize + nextPrefixCodePointSize;
                  addContentSize = contentCodePointSize;
                }
                break;
              case 'Е': case 'е':
                if (nextPrefixCodePoint == 'E' || nextPrefixCodePoint == 'e') {
                  addPrefixSize = prefixCodePointSize + nextPrefixCodePointSize;
                  addContentSize = contentCodePointSize;
                }
                break;
            }
            break;
          case 'Q': case 'q':
            switch (contentCodePoint) {
              case 'К': case 'к':
                addPrefixSize = prefixCodePointSize;
                addContentSize = contentCodePointSize;
                if ((nextContentCodePoint == 'Ь' || nextContentCodePoint == 'ь') && !(
                  nextPrefixCodePoint == 'Y' || nextPrefixCodePoint == 'y'
                )) {
                  addContentSize += nextContentCodePointSize;
                }
                break;
            }
            break;
        }
      } else if (isCyrillicLetter(prefixCodePoint) && isLatinLatter(contentCodePoint)) {
        switch (prefixCodePoint) {
          case 'Б': case 'б':
            ok = contentCodePoint == 'B' || contentCodePoint == 'b';
            break;
          case 'Г': case 'г':
            ok = contentCodePoint == 'G' || contentCodePoint == 'g';
            break;
          case 'Д': case 'д':
            ok = contentCodePoint == 'D' || contentCodePoint == 'd';
            break;
          case 'З': case 'з':
            ok = contentCodePoint == 'Z' || contentCodePoint == 'z';
            break;
          case 'Л': case 'л':
            ok = contentCodePoint == 'L' || contentCodePoint == 'l';
            break;
          case 'М': case 'м':
            ok = contentCodePoint == 'M' || contentCodePoint == 'm';
            break;
          case 'Н': case 'н':
            ok = contentCodePoint == 'N' || contentCodePoint == 'n';
            break;
          case 'О': case 'о':
            ok = contentCodePoint == 'O' || contentCodePoint == 'o';
            break;
          case 'П': case 'п':
            ok = contentCodePoint == 'P' || contentCodePoint == 'p';
            break;
          case 'Р': case 'р':
            ok = contentCodePoint == 'R' || contentCodePoint == 'r';
            break;
          case 'Т': case 'т':
            ok = contentCodePoint == 'T' || contentCodePoint == 't';
            break;
          case 'Х': case 'х':
            ok = contentCodePoint == 'H' || contentCodePoint == 'h';
            break;
          case 'Э': case 'э':
            ok = contentCodePoint == 'E' || contentCodePoint == 'e';
            break;
          case 'У': case 'у':
            ok = contentCodePoint == 'U' || contentCodePoint == 'u';
            break;
          case 'К': case 'к':
            switch (contentCodePoint) {
              case 'K': case 'k':
                ok = true;
                break;
              case 'C': case 'c':
                if ((nextContentCodePoint == 'K' || nextContentCodePoint == 'k') && (nextPrefixCodePoint != 'К' && nextPrefixCodePoint != 'к')) {
                  // К <-> Ck
                  addPrefixSize = prefixCodePointSize;
                  addContentSize = contentCodePointSize + nextContentCodePointSize;
                } else {
                  ok = true;
                }
                break;
              case 'X':
                if (nextPrefixCodePoint == 'С' || nextPrefixCodePoint == 'c') {
                  addPrefixSize = prefixCodePointSize + nextPrefixCodePointSize;
                  addContentSize = contentCodePointSize;
                }
                break;
            }
            break;
          case 'А': case 'а':
            // A, U
            switch (contentCodePoint) {
              case 'A': case 'a':
              case 'U': case 'u':
                ok = true;
                break;
            }
            break;
          case 'В': case 'в':
            // V, W
            switch (contentCodePoint) {
              case 'V': case 'v':
              case 'W': case 'w':
                ok = true;
                break;
            }
            break;
          case 'Е': case 'е':
            // E, Ye, Ie
            switch (contentCodePoint) {
              case 'E': case 'e':
                ok = true;
                break;
              case 'Y': case 'y':
              case 'I': case 'i':
                if (nextContentCodePoint == 'E' || nextContentCodePoint == 'e') {
                  addPrefixSize = prefixCodePointSize;
                  addContentSize = contentCodePointSize + nextContentCodePointSize;
                }
                break;
            }
            break;
          case 'Ё': case 'ё':
            // Yo, Io
            switch (contentCodePoint) {
              case 'Y': case 'y':
              case 'I': case 'i':
                if (nextContentCodePoint == 'O' || nextContentCodePoint == 'o') {
                  addPrefixSize = prefixCodePointSize;
                  addContentSize = contentCodePointSize + nextContentCodePointSize;
                }
                break;
            }
            break;
          case 'Ю': case 'ю':
            // Yu, Iu
            switch (contentCodePoint) {
              case 'Y': case 'y':
              case 'I': case 'i':
                if (nextContentCodePoint == 'U' || nextContentCodePoint == 'u') {
                  addPrefixSize = prefixCodePointSize;
                  addContentSize = contentCodePointSize + nextContentCodePointSize;
                }
                break;
            }
            break;
          case 'Я': case 'я':
            // Ya, Ia
            switch (contentCodePoint) {
              case 'Y': case 'y':
              case 'I': case 'i':
                if (nextContentCodePoint == 'A' || nextContentCodePoint == 'a') {
                  addPrefixSize = prefixCodePointSize;
                  addContentSize = contentCodePointSize + nextContentCodePointSize;
                }
                break;
            }
            break;
          case 'Ж': case 'ж':
            // Zh, J
            switch (contentCodePoint) {
              case 'J': case 'j':
                ok = true;
                break;
              case 'Z': case 'z':
                if (nextContentCodePoint == 'H' || nextContentCodePoint == 'h') {
                  addPrefixSize = prefixCodePointSize;
                  addContentSize = contentCodePointSize + nextContentCodePointSize;
                }
                break;
            }
            break;
          case 'И': case 'и':
            // I, E, Ee, X
            switch (contentCodePoint) {
              case 'I': case 'i':
                ok = true;
                break;
              case 'E': case 'e':
                addPrefixSize = prefixCodePointSize;
                addContentSize = contentCodePointSize;
                if ((nextContentCodePoint == 'E' || nextContentCodePoint == 'e') && !(
                  nextPrefixCodePoint == 'И' || nextPrefixCodePoint == 'и'
                )) {
                  addContentSize += nextContentCodePointSize;
                }
                break;
              case 'X':
                if (nextPrefixCodePoint == 'К' || nextPrefixCodePoint == 'к') {
                  int afterNextPrefixCodePointIndex = nextPrefixCodePointIndex + nextPrefixCodePointSize;
                  int afterNextPrefixCodePoint = afterNextPrefixCodePointIndex < prefixEnd ? prefix.codePointAt(afterNextPrefixCodePointIndex) : 0;
                  if (afterNextPrefixCodePoint == 'С' || afterNextPrefixCodePoint == 'с') {
                    addPrefixSize = prefixCodePointSize + nextPrefixCodePointSize + Character.charCount(afterNextPrefixCodePoint);
                    addContentSize = contentCodePointSize;
                  }
                }
                break;
            }
            break;
          case 'Й': case 'й':
            // Y, I
            switch (contentCodePoint) {
              case 'Y': case 'y':
              case 'I': case 'i':
                ok = true;
                break;
            }
            break;
          case 'С': case 'с':
            // S, C
            switch (contentCodePoint) {
              case 'S': case 's':
              case 'C': case 'c':
                ok = true;
                break;
            }
            break;
          case 'Ф': case 'ф':
            // F, Ph
            switch (contentCodePoint) {
              case 'F': case 'f':
                ok = true;
                break;
              case 'P': case 'p':
                if (nextContentCodePoint == 'H' || nextContentCodePoint == 'h') {
                  addPrefixSize = prefixCodePointSize;
                  addContentSize = contentCodePointSize + nextContentCodePointSize;
                }
                break;
            }
            break;
          case 'Ц': case 'ц':
            // Ts, C
            switch (contentCodePoint) {
              case 'C': case 'c':
                ok = true;
                break;
              case 'T': case 't':
                if (nextContentCodePoint == 'S' || nextContentCodePoint == 's') {
                  addPrefixSize = prefixCodePointSize;
                  addContentSize = contentCodePointSize + nextContentCodePointSize;
                }
                break;
            }
            break;
          case 'Ч': case 'ч':
            // Ch
            if ((contentCodePoint == 'C' || contentCodePoint == 'c') && (nextContentCodePoint == 'H' || nextContentCodePoint == 'h')) {
              addPrefixSize = prefixCodePointSize;
              addContentSize = contentCodePointSize + nextContentCodePointSize;
            }
            break;
          case 'Ш': case 'ш':
            // Sh
            if ((contentCodePoint == 'S' || contentCodePoint == 's') && (nextContentCodePoint == 'H' || nextContentCodePoint == 'h')) {
              addPrefixSize = prefixCodePointSize;
              addContentSize = contentCodePointSize + nextContentCodePointSize;
            }
            break;
          case 'Щ': case 'щ':
            // Sh, Sch
            if ((contentCodePoint == 'S' || contentCodePoint == 's')) {
              if (nextContentCodePoint == 'H' || nextContentCodePoint == 'h') {
                addPrefixSize = prefixCodePointSize;
                addContentSize = contentCodePointSize + nextContentCodePointSize;
              } else if (nextContentCodePoint == 'C' || nextContentCodePoint == 'c') {
                int afterNextContentCodePointIndex = nextContentCodePointIndex + nextContentCodePointSize;
                int afterNextContentCodePoint = afterNextContentCodePointIndex < end ? content.codePointAt(afterNextContentCodePointIndex) : 0;
                if (afterNextContentCodePoint == 'H' || afterNextContentCodePoint == 'h') {
                  addPrefixSize = prefixCodePointSize;
                  addContentSize = contentCodePointSize + nextContentCodePointSize + Character.charCount(afterNextContentCodePoint);
                }
              }
            }
            break;
          case 'Ъ': case 'ъ':
          case 'Ы': case 'ы':
          case 'Ь': case 'ь':
            ok = contentCodePoint == 'Y' || contentCodePoint == 'y';
            break;
        }
      }

      if (addContentSize == 0 && addPrefixSize == 0) {
        if (ok) {
          addPrefixSize = prefixCodePointSize;
          addContentSize = contentCodePointSize;
        } else {
          break;
        }
      }

      prefixLength += addPrefixSize;
      contentLength += addContentSize;
    }

    // Force ignore lookup result if only separators were found
    if (contentLength - contentSeparatorLength > 0 && prefixLength - prefixSeparatorLength > 0) {
      return new PrefixResult(contentLength, prefixLength);
    }
    return null;
  }
}
