const SIZE = 512;
const AREA = 0.4;
const BLUR = 24;
const cache = new Map<number, { canvas: HTMLCanvasElement; extent: number }>();

/** Glow size in CSS pixels. Screen density changes only the canvas resolution, not the glow radius or blur. */
export function getCardTouchGlowExtent(width: number) {
  return width * 1.18 * Math.sqrt(AREA) + 6 * BLUR;
}

/** Finger glow of iOS `CardShineTexture.touchSpot`, built once per card width so moving the finger costs nothing */
export function getCardTouchGlowTexture(width: number) {
  const cached = cache.get(width);

  if (cached) {
    cache.delete(width);
    cache.set(width, cached);

    return cached;
  }

  const extent = getCardTouchGlowExtent(width);
  const pixels = createCardTouchGlowPixels(width);
  const canvas = document.createElement('canvas');
  canvas.width = SIZE;
  canvas.height = SIZE;

  const context = canvas.getContext('2d');
  if (!context) return undefined;

  const image = context.createImageData(SIZE, SIZE);
  image.data.set(pixels);
  context.putImageData(image, 0, 0);

  const result = { canvas, extent };

  if (cache.size >= 4) cache.delete(cache.keys().next().value!);

  cache.set(width, result);

  return result;
}

/** Computes the blur by hand, since Safari's canvas has no `filter` on the versions we support */
export function createCardTouchGlowPixels(width: number) {
  const extent = getCardTouchGlowExtent(width);
  const radius = width * 1.18 * Math.sqrt(AREA) / 2;
  const alpha = new Float32Array(SIZE * SIZE);
  const stops = [[0, 0.27], [0.28, 0.1425], [0.58, 0.0525], [1, 0]];

  for (let y = 0; y < SIZE / 2; y++) {
    for (let x = 0; x < SIZE / 2; x++) {
      const distance = Math.hypot(x + 0.5 - SIZE / 2, y + 0.5 - SIZE / 2) * extent / SIZE;
      if (distance > radius) continue;

      const position = distance / (radius * Math.SQRT2);
      const index = position <= 0.28 ? 1 : position <= 0.58 ? 2 : 3;
      const lower = stops[Math.max(0, index - 1)];
      const upper = stops[index];
      const fraction = (position - lower[0]) / Math.max(1e-12, upper[0] - lower[0]);
      const opacity = lower[1] + (upper[1] - lower[1]) * fraction;
      const sample = Math.round(255 * opacity);
      alpha[y * SIZE + x] = sample;
      alpha[y * SIZE + SIZE - 1 - x] = sample;
      alpha[(SIZE - 1 - y) * SIZE + x] = sample;
      alpha[(SIZE - 1 - y) * SIZE + SIZE - 1 - x] = sample;
    }
  }

  const sigma = BLUR * SIZE / extent;
  const reach = Math.ceil(3 * sigma);
  const weights = new Float64Array(2 * reach + 1);
  let total = 0;

  for (let i = 0; i < weights.length; i++) {
    weights[i] = Math.exp(-0.5 * ((i - reach) / sigma) ** 2);
    total += weights[i];
  }

  for (let i = 0; i < weights.length; i++) weights[i] /= total;

  const stride = SIZE + 2 * reach;
  const padded = new Float32Array(stride * SIZE);
  const horizontal = new Float32Array(SIZE * SIZE);
  for (let y = 0; y < SIZE; y++) padded.set(alpha.subarray(y * SIZE, (y + 1) * SIZE), y * stride + reach);

  // The circle is centered, so each blur pass computes one quarter and mirrors it
  for (let y = 0; y < SIZE / 2; y++) {
    for (let x = 0; x < SIZE / 2; x++) {
      const base = y * stride + x;
      let sum = 0;
      for (let k = 0; k < weights.length; k++) sum += weights[k] * padded[base + k];
      horizontal[y * SIZE + x] = sum;
      horizontal[y * SIZE + SIZE - 1 - x] = sum;
      horizontal[(SIZE - 1 - y) * SIZE + x] = sum;
      horizontal[(SIZE - 1 - y) * SIZE + SIZE - 1 - x] = sum;
    }
  }

  // Rows and columns are swapped, so the second blur pass also reads memory in order
  padded.fill(0);

  for (let x = 0; x < SIZE; x++) {
    for (let y = 0; y < SIZE; y++) padded[x * stride + reach + y] = horizontal[y * SIZE + x];
  }

  const pixels = new Uint8ClampedArray(SIZE * SIZE * 4);
  pixels.fill(255);

  function put(x: number, y: number, opacity: number) {
    pixels[(y * SIZE + x) * 4 + 3] = opacity;
  }

  // The result is also symmetric across the diagonals, so only one eighth is computed
  for (let x = 0; x < SIZE / 2; x++) {
    for (let y = 0; y <= x; y++) {
      const base = x * stride + y;
      let sum = 0;
      for (let k = 0; k < weights.length; k++) sum += weights[k] * padded[base + k];

      const opacity = Math.round(sum);
      const mx = SIZE - 1 - x;
      const my = SIZE - 1 - y;
      put(x, y, opacity);
      put(mx, y, opacity);
      put(x, my, opacity);
      put(mx, my, opacity);
      put(y, x, opacity);
      put(my, x, opacity);
      put(y, mx, opacity);
      put(my, mx, opacity);
    }
  }

  return pixels;
}
