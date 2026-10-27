import native from '../../../tests/fixtures/cardTouchGlowTexture.json';
import { createCardTouchGlowPixels, getCardTouchGlowExtent } from './touchGlowTexture';

// Alpha values sampled from the PNG that iOS Core Image renders for `CardShineTexture.touchSpot` (PR #13087)
it.each(native)('matches CoreImage alpha within one 8-bit level at width $width', ({ width, samples }) => {
  const pixels = createCardTouchGlowPixels(width);

  for (const [x, y, alpha] of samples) {
    expect(Math.abs(pixels[(y * 512 + x) * 4 + 3] - alpha)).toBeLessThanOrEqual(1);
  }

  expect(pixels[(256 * 512 + 256) * 4 + 3]).toBeGreaterThan(40);
  expect(getCardTouchGlowExtent(width)).toBeCloseTo(width * 1.18 * Math.sqrt(0.4) + 144, 12);
});
