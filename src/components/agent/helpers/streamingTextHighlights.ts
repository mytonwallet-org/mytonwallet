import { getStreamedCharacterColors } from './streamingTextAppearance';

// The highlights that colour streamed text in place, one for each colour of the text and each sample of its settling
const HIGHLIGHT_NAME_PREFIX = 'agent-streamed-text';

const namesByKey = new Map<string, string[] | undefined>();
let styleSheet: CSSStyleSheet | undefined;

/**
 * The names of the highlights that colour streamed text of `textColor`, a computed CSS colour, at each sample of its
 * settling (`getStreamedCharacterColors`). They are registered with their styles as a colour is first asked for. A
 * colour that cannot be read, or a browser without the CSS Custom Highlight API, has none.
 */
export function getStreamedTextHighlightNames(textColor: string, isDark: boolean) {
  const key = `${isDark ? 'dark' : 'light'}:${textColor}`;
  if (!namesByKey.has(key)) {
    const colors = getIsTextHighlightSupported() ? getStreamedCharacterColors(textColor, isDark) : undefined;
    namesByKey.set(key, colors && registerHighlights(colors, namesByKey.size));
  }

  return namesByKey.get(key);
}

export function addHighlightRange(name: string, range: Range) {
  CSS.highlights.get(name)?.add(range);
}

export function deleteHighlightRange(name: string, range: Range) {
  CSS.highlights.get(name)?.delete(range);
}

/** Whether the browser lets streamed text take its colours where it stands, through the CSS Custom Highlight API */
export function getIsTextHighlightSupported() {
  return typeof CSS !== 'undefined' && 'highlights' in CSS && typeof Highlight === 'function'
    && typeof CSSStyleSheet === 'function' && 'adoptedStyleSheets' in document;
}

function registerHighlights(colors: string[], colorIndex: number) {
  if (!styleSheet) {
    styleSheet = new CSSStyleSheet();
    document.adoptedStyleSheets = [...document.adoptedStyleSheets, styleSheet];
  }
  const sheet = styleSheet;

  return colors.map((color, sampleIndex) => {
    const name = `${HIGHLIGHT_NAME_PREFIX}-${colorIndex}-${sampleIndex}`;
    sheet.insertRule(`::highlight(${name}) { color: ${color}; }`, sheet.cssRules.length);
    CSS.highlights.set(name, new Highlight());
    return name;
  });
}
