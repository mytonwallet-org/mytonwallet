import { createCardEdgeMaskPixels } from './edgeMask';

function alphaAt(pixels: Uint8ClampedArray, width: number, x: number, y: number) {
  return pixels[(y * width + x) * 4 + 3];
}

it('covers the face, clears its corners and mirrors one quadrant exactly', () => {
  const [width, height, ratio] = [100, 60, 2];
  const pixels = createCardEdgeMaskPixels(width, height, 12, 1.333, ratio, 0, false);
  const [canvasWidth, canvasHeight] = [width * ratio, height * ratio];
  expect(alphaAt(pixels, canvasWidth, canvasWidth / 2, canvasHeight / 2)).toBe(255);
  expect(alphaAt(pixels, canvasWidth, 0, 0)).toBe(0);

  for (const [x, y] of [[3, 17], [10, 2], [57, 1]]) {
    const alpha = alphaAt(pixels, canvasWidth, x, y);
    expect(alphaAt(pixels, canvasWidth, canvasWidth - 1 - x, y)).toBe(alpha);
    expect(alphaAt(pixels, canvasWidth, x, canvasHeight - 1 - y)).toBe(alpha);
    expect(alphaAt(pixels, canvasWidth, canvasWidth - 1 - x, canvasHeight - 1 - y)).toBe(alpha);
  }
});

it('keeps only a thin ring for the rim', () => {
  const [width, height, ratio, gutter] = [100, 60, 2, 1];
  const pixels = createCardEdgeMaskPixels(width, height, 12, 1.333, ratio, gutter, true);
  const canvasWidth = (width + gutter * 2) * ratio;
  const middleY = ((height + gutter * 2) * ratio) / 2;
  const row = Array.from({ length: canvasWidth }, (_, x) => alphaAt(pixels, canvasWidth, x, middleY));
  expect(row[canvasWidth / 2]).toBe(0);
  expect(Math.max(...row.slice(0, 12))).toBeGreaterThan(200);
  expect(row.filter(Boolean).length).toBeLessThan(16);
});
