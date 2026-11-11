import { getOpaqueBackgroundColor } from './streamingTextColor';

describe('getOpaqueBackgroundColor', () => {
  afterEach(() => {
    jest.restoreAllMocks();
  });

  it('composites a code block tinted with the accent by `color-mix()` over the bubble', () => {
    const bubble = document.createElement('div');
    const block = document.createElement('div');
    const code = document.createElement('code');
    block.appendChild(code);
    bubble.appendChild(block);
    document.body.appendChild(bubble);
    // `color-mix(in srgb, #2C92F0 12%, transparent)` as a browser computes it
    const backgroundColors = new Map<Element, string>([
      [bubble, 'rgb(241, 241, 243)'],
      [block, 'color(srgb 0.172549 0.572549 0.941176 / 0.12)'],
    ]);
    const getComputedStyle = window.getComputedStyle.bind(window);
    jest.spyOn(window, 'getComputedStyle').mockImplementation((element, pseudoElement) => {
      const style = getComputedStyle(element, pseudoElement);
      Object.defineProperty(style, 'backgroundColor', {
        configurable: true,
        value: backgroundColors.get(element) ?? 'rgba(0, 0, 0, 0)',
      });
      return style;
    });

    try {
      expect(getOpaqueBackgroundColor(code)).toBe('rgb(217, 230, 243)');
    } finally {
      bubble.remove();
    }
  });
});
