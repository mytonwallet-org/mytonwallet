import { getStreamedCharacterColors } from './streamingTextAppearance';

type HighlightsModule = typeof import('./streamingTextHighlights');

const GLOBAL_KEYS = ['CSS', 'Highlight', 'CSSStyleSheet'] as const;

describe('streamed text highlights', () => {
  const originalGlobals = GLOBAL_KEYS.map((key) => Object.getOwnPropertyDescriptor(globalThis, key));
  let highlights: Map<string, Set<Range>>;
  let rules: string[];
  let adoptedStyleSheets: object[];

  beforeEach(() => {
    highlights = new Map();
    rules = [];
    adoptedStyleSheets = [];
    Object.defineProperty(globalThis, 'CSS', { configurable: true, value: { highlights } });
    Object.defineProperty(globalThis, 'Highlight', { configurable: true, value: class extends Set {} });
    Object.defineProperty(globalThis, 'CSSStyleSheet', {
      configurable: true,
      value: class {
        cssRules = rules;

        insertRule(rule: string, index: number) {
          rules.splice(index, 0, rule);
          return index;
        }
      },
    });
    Object.defineProperty(document, 'adoptedStyleSheets', {
      configurable: true,
      get: () => adoptedStyleSheets,
      set: (sheets: object[]) => {
        adoptedStyleSheets = sheets;
      },
    });
  });

  afterEach(() => {
    GLOBAL_KEYS.forEach((key, index) => {
      const descriptor = originalGlobals[index];
      if (descriptor) {
        Object.defineProperty(globalThis, key, descriptor);
      } else {
        Reflect.deleteProperty(globalThis, key);
      }
    });
    Reflect.deleteProperty(document, 'adoptedStyleSheets');
  });

  it('registers a highlight for each sample of a colour\'s settling, styled in its colour, once', () => {
    const { getStreamedTextHighlightNames } = loadHighlights();
    const names = getStreamedTextHighlightNames('rgb(0, 0, 0)', false)!;
    const colors = getStreamedCharacterColors('rgb(0, 0, 0)', false)!;

    expect(names).toHaveLength(colors.length);
    expect(Array.from(highlights.keys())).toEqual(names);
    expect(rules[0]).toBe(`::highlight(${names[0]}) { color: ${colors[0]}; }`);
    expect(rules.at(-1)).toBe(`::highlight(${names.at(-1)}) { color: ${colors.at(-1)}; }`);
    expect(adoptedStyleSheets).toHaveLength(1);

    // The same colour takes the same highlights, and another colour highlights of its own in the same sheet
    expect(getStreamedTextHighlightNames('rgb(0, 0, 0)', false)).toBe(names);
    const darkNames = getStreamedTextHighlightNames('rgb(0, 0, 0)', true)!;
    expect(darkNames.some((name) => names.includes(name))).toBe(false);
    expect(rules).toHaveLength(colors.length * 2);
    expect(adoptedStyleSheets).toHaveLength(1);
  });

  it('adds a range to a highlight and takes it out', () => {
    const { addHighlightRange, deleteHighlightRange, getStreamedTextHighlightNames } = loadHighlights();
    const [name] = getStreamedTextHighlightNames('rgb(0, 0, 0)', false)!;
    const range = {} as Range;

    addHighlightRange(name, range);
    expect(highlights.get(name)!.has(range)).toBe(true);
    deleteHighlightRange(name, range);
    expect(highlights.get(name)!.has(range)).toBe(false);
  });

  it('has no highlights for a colour that cannot be read or without the CSS Custom Highlight API', () => {
    expect(loadHighlights().getStreamedTextHighlightNames('', false)).toBeUndefined();

    Reflect.deleteProperty(globalThis, 'CSS');
    expect(loadHighlights().getStreamedTextHighlightNames('rgb(0, 0, 0)', false)).toBeUndefined();
    expect(rules).toHaveLength(0);
  });
});

// A fresh copy of the module, which keeps its highlights and their sheet for the page's lifetime
function loadHighlights() {
  let module: HighlightsModule | undefined;
  jest.isolateModules(() => {
    module = jest.requireActual<HighlightsModule>('./streamingTextHighlights');
  });
  return module!;
}
