import { captureProductionText, localPosition } from './textSnapshot';

function box(left: number, top: number, parent?: HTMLElement, border = 0) {
  const node = document.createElement('div');

  Object.defineProperties(node, {
    offsetLeft: { value: left }, offsetTop: { value: top },
    offsetParent: { value: parent },
    clientLeft: { value: border }, clientTop: { value: border },
  });

  return node;
}

it('locates particles when WebKit skips the transformed card in offsetParent', () => {
  const page = box(30, 20);
  const card = box(65, 76, page);
  const target = box(125, 140, page);
  expect(localPosition(target, card)).toEqual([60, 64]);
});

it('uses the same content origin for nested offset parents and borders', () => {
  const page = box(30, 20);
  const card = box(65, 76, page, 2);
  const content = box(12, 14, card, 1);
  const target = box(30, 40, content);
  expect(localPosition(target, card)).toEqual([43, 55]);
  expect(localPosition(target, content)).toEqual([30, 40]);
});

it('draws text from its first visible character, since flex items drop the whitespace at their edges', () => {
  const fillText = jest.fn();

  jest.spyOn(HTMLCanvasElement.prototype, 'getContext').mockReturnValue({
    scale: jest.fn(),
    save: jest.fn(),
    translate: jest.fn(),
    restore: jest.fn(),
    createRadialGradient: () => ({ addColorStop: jest.fn() }),
    fillText,
  } as unknown as CanvasRenderingContext2D);

  const { getBoundingClientRect } = Range.prototype;

  // The glyph position of each character is its offset times 10 px
  Range.prototype.getBoundingClientRect = function (this: Range) {
    return { left: this.startOffset * 10 } as DOMRect;
  };

  const target = document.createElement('span');
  target.textContent = ' · ';
  document.body.append(target);

  try {
    captureProductionText(target, { palette: ['#FFF', '#FFF'] });
    expect(fillText).toHaveBeenCalledWith('·', 10, expect.any(Number));
  } finally {
    Range.prototype.getBoundingClientRect = getBoundingClientRect;
    target.remove();
    jest.restoreAllMocks();
  }
});

it('measures the baseline of text that is a flex item of its own', () => {
  const fillText = jest.fn();

  jest.spyOn(HTMLCanvasElement.prototype, 'getContext').mockReturnValue({
    scale: jest.fn(),
    save: jest.fn(),
    translate: jest.fn(),
    restore: jest.fn(),
    createRadialGradient: () => ({ addColorStop: jest.fn() }),
    fillText,
  } as unknown as CanvasRenderingContext2D);

  const { getBoundingClientRect } = Range.prototype;
  Range.prototype.getBoundingClientRect = () => ({ left: 0 }) as DOMRect;

  // A baseline marker right after the text sits on its line; any other element is placed by `align-items`
  jest.spyOn(HTMLElement.prototype, 'getBoundingClientRect').mockImplementation(function (this: HTMLElement) {
    const top = this.previousSibling?.nodeType === Node.TEXT_NODE ? 13 : 0;

    return { top, left: 0, width: 100, height: 20 } as DOMRect;
  });

  const target = document.createElement('span');
  target.style.display = 'flex';
  target.append(' · ', Object.assign(document.createElement('span'), { textContent: '$5' }));
  document.body.append(target);

  try {
    captureProductionText(target, { palette: ['#FFF', '#FFF'] });
    expect(fillText).toHaveBeenCalledWith('·', 0, 13);
    expect(fillText).toHaveBeenCalledWith('$5', 0, 13);
  } finally {
    Range.prototype.getBoundingClientRect = getBoundingClientRect;
    target.remove();
    jest.restoreAllMocks();
  }
});
