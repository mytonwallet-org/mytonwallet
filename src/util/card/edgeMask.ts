import { smooth } from './surfaceMotion';

const masks = new Map<string, { face: string; rim: string }>();

export function getCardEdgeMasks(width: number, height: number, radius: number, thickness: number, dpr: number) {
  const ratio = Math.max(1, dpr || 1);
  const key = [width, height, radius, thickness, ratio].join(':');
  const cached = masks.get(key);
  if (cached) return cached;

  // The mask is drawn pixel by pixel, because Safari blurs a filtered SVG mask once more
  // under the card's transform, even when the card is at rest
  const rasterize = (gutter: number, isRim: boolean) => {
    const canvas = document.createElement('canvas');
    canvas.width = Math.ceil((width + gutter * 2) * ratio);
    canvas.height = Math.ceil((height + gutter * 2) * ratio);

    const ctx = canvas.getContext('2d')!;
    const image = ctx.createImageData(canvas.width, canvas.height);
    image.data.set(createCardEdgeMaskPixels(width, height, radius, thickness, ratio, gutter, isRim));
    ctx.putImageData(image, 0, 0);

    return `url("${canvas.toDataURL()}")`;
  };
  const result = { face: rasterize(0, false), rim: rasterize(1, true) };

  if (masks.size >= 24) masks.delete(masks.keys().next().value!);

  masks.set(key, result);

  return result;
}

export function createCardEdgeMaskPixels(
  width: number,
  height: number,
  radius: number,
  thickness: number,
  ratio: number,
  gutter: number,
  isRim: boolean,
) {
  const canvasWidth = Math.ceil((width + gutter * 2) * ratio);
  const canvasHeight = Math.ceil((height + gutter * 2) * ratio);
  const pixels = new Uint8ClampedArray(canvasWidth * canvasHeight * 4);
  const scaleX = canvasWidth / (width + gutter * 2);
  const scaleY = canvasHeight / (height + gutter * 2);
  const r = Math.min(radius, width / 2, height / 2);
  const halfWidth = width / 2;
  const halfHeight = height / 2;

  // Safari draws a masked canvas as its own layer, and an opaque pixel on that layer's edge turns jagged on tilt.
  // So the edge is inset by 1.25px, half of the 1.5px soft edge plus half a pixel. The rim is inset the same way.
  const contourInset = 1.25 / ratio;
  const coverage = (distance: number) => smooth(0.5 - distance * ratio / 1.5);
  const put = (x: number, y: number, alpha: number) => {
    const offset = (y * canvasWidth + x) * 4;
    pixels[offset] = 255;
    pixels[offset + 1] = 255;
    pixels[offset + 2] = 255;
    pixels[offset + 3] = alpha;
  };

  // The rounded rectangle is symmetric about both axes, so one quadrant is computed and mirrored
  for (let y = 0; y < canvasHeight / 2; y++) {
    const qy = Math.abs((y + 0.5) / scaleY - gutter - halfHeight) - (halfHeight - r);

    for (let x = 0; x < canvasWidth / 2; x++) {
      const qx = Math.abs((x + 0.5) / scaleX - gutter - halfWidth) - (halfWidth - r);
      const outsideX = Math.max(qx, 0);
      const outsideY = Math.max(qy, 0);
      const distance = Math.sqrt(outsideX * outsideX + outsideY * outsideY) + Math.min(Math.max(qx, qy), 0) - r;
      const alpha = Math.round(
        (coverage(distance + contourInset) - (isRim ? coverage(distance + contourInset + thickness) : 0)) * 255,
      );
      const mirroredX = canvasWidth - 1 - x;
      const mirroredY = canvasHeight - 1 - y;
      put(x, y, alpha);
      put(mirroredX, y, alpha);
      put(x, mirroredY, alpha);
      put(mirroredX, mirroredY, alpha);
    }
  }

  return pixels;
}
