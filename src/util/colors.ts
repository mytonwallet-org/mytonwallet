export type RGBColor = [number, number, number];

export interface RgbaColor {
  red: number;
  green: number;
  blue: number;
  alpha: number;
}

export function hex2rgb(param: string): RGBColor {
  const hex = param.replace('#', '');
  return [
    parseInt(hex.substring(0, 2), 16),
    parseInt(hex.substring(2, 4), 16),
    parseInt(hex.substring(4, 6), 16),
  ];
}

export default function rgbToHex(rgb: [number, number, number]) {
  return `#${rgb.map((x) => {
    const hex = x.toString(16);
    return hex.length === 1 ? `0${hex}` : hex;
  }).join('')}`;
}

export function labEuclideanDistance(color1: RGBColor, color2: RGBColor): number {
  const [l1, a1, b1] = rgbToLab(color1);
  const [l2, a2, b2] = rgbToLab(color2);

  return Math.sqrt((l1 - l2) ** 2 + (a1 - a2) ** 2 + (b1 - b2) ** 2);
}

function rgbToLab(rgb: RGBColor): RGBColor {
  let [r, g, b] = rgb.map((value) => value / 255);
  [r, g, b] = [r, g, b].map((value) => (value > 0.04045 ? ((value + 0.055) / 1.055) ** 2.4 : value / 12.92));

  let x = r * 0.4124 + g * 0.3576 + b * 0.1805;
  let y = r * 0.2126 + g * 0.7152 + b * 0.0722;
  let z = r * 0.0193 + g * 0.1192 + b * 0.9505;

  [x, y, z] = [x / 0.95047, y, z / 1.08883].map(
    (value) => (value > 0.008856 ? value ** (1 / 3) : (7.787 * value) + 16 / 116),
  );

  return [(116 * y) - 16, 500 * (x - y), 200 * (y - z)];
}

/**
 * Calculates the perceptual difference between two RGB colors.
 *
 * Delta E is a metric for understanding how the human eye perceives color difference.
 * The following table provides a general guideline:
 *
 * Delta E  |  Perception
 * ---------|-------------------------------------------
 * <= 1.0   | Not perceptible by human eyes.
 * 1 - 2    | Perceptible through close observation.
 * 2 - 10   | Perceptible at a glance.
 * 11 - 49  | Colors are more similar than opposite.
 * 100      | Colors are exact opposite.
 *
 * @param rgbA The first color as an RGB array.
 * @param rgbB The second color as an RGB array.
 * @returns The Delta E value representing the color difference.
 */
export function deltaE(rgbA: RGBColor, rgbB: RGBColor): number {
  const [l1, a1, b1] = rgbToLab(rgbA);
  const [l2, a2, b2] = rgbToLab(rgbB);

  const c1 = Math.sqrt(a1 * a1 + b1 * b1);
  const c2 = Math.sqrt(a2 * a2 + b2 * b2);
  const deltaC = c1 - c2;

  const deltaL = l1 - l2;
  const deltaA = a1 - a2;
  const deltaB = b1 - b2;

  const deltaH = Math.sqrt(deltaA * deltaA + deltaB * deltaB - deltaC * deltaC);

  const sl = 1.0;
  const sc = 1.0 + 0.045 * c1;
  const sh = 1.0 + 0.015 * c1;

  const deltaLKlsl = deltaL / sl;
  const deltaCkcsc = deltaC / sc;
  const deltaHkhsh = deltaH / sh;

  return Math.sqrt(deltaLKlsl * deltaLKlsl + deltaCkcsc * deltaCkcsc + deltaHkhsh * deltaHkhsh);
}

/** Parses the CSS color notations produced by `getComputedStyle`: hex, `rgb()` and `rgba()` */
export function parseCssColor(color: string): RgbaColor | undefined {
  const normalizedColor = color.trim().toLowerCase();
  if (normalizedColor === 'transparent') {
    return {
      red: 0, green: 0, blue: 0, alpha: 0,
    };
  }

  const hexadecimalMatch = normalizedColor.match(/^#([\da-f]{3,8})$/i);
  if (hexadecimalMatch) {
    const hexadecimal = hexadecimalMatch[1];
    if (![3, 4, 6, 8].includes(hexadecimal.length)) return undefined;

    const isShort = hexadecimal.length <= 4;
    const alphaOffset = isShort ? 3 : 6;

    return {
      red: parseHexadecimalColorChannel(hexadecimal, isShort, 0),
      green: parseHexadecimalColorChannel(hexadecimal, isShort, isShort ? 1 : 2),
      blue: parseHexadecimalColorChannel(hexadecimal, isShort, isShort ? 2 : 4),
      alpha: hexadecimal.length === 4 || hexadecimal.length === 8
        ? parseHexadecimalColorChannel(hexadecimal, isShort, alphaOffset) / 255
        : 1,
    };
  }

  const rgbMatch = normalizedColor.match(/^rgba?\((.*)\)$/i);
  if (!rgbMatch) return undefined;

  const slashSeparatedComponents = rgbMatch[1].trim().split(/\s*\/\s*/);
  if (slashSeparatedComponents.length > 2) return undefined;

  const components = slashSeparatedComponents[0].includes(',')
    ? slashSeparatedComponents[0].split(/\s*,\s*/)
    : slashSeparatedComponents[0].split(/\s+/);
  const legacyAlpha = components.length === 4 ? components.pop() : undefined;
  if (components.length !== 3) return undefined;

  const red = parseCssColorChannel(components[0]);
  const green = parseCssColorChannel(components[1]);
  const blue = parseCssColorChannel(components[2]);
  const alphaComponent = slashSeparatedComponents[1] ?? legacyAlpha;
  const alpha = alphaComponent === undefined ? 1 : parseCssAlpha(alphaComponent);
  if ([red, green, blue, alpha].some((component) => component === undefined)) return undefined;

  return {
    red: red!, green: green!, blue: blue!, alpha: alpha!,
  };
}

/** Flattens translucent layers over an opaque base into a single `rgb()` color, topmost layer last */
export function compositeCssColors(opaqueBase: RgbaColor, translucentLayers: RgbaColor[]) {
  const compositedColor = translucentLayers.reduceRight((background, foreground) => ({
    red: foreground.red * foreground.alpha + background.red * (1 - foreground.alpha),
    green: foreground.green * foreground.alpha + background.green * (1 - foreground.alpha),
    blue: foreground.blue * foreground.alpha + background.blue * (1 - foreground.alpha),
    alpha: 1,
  }), opaqueBase);

  return `rgb(${Math.round(compositedColor.red)}, ${Math.round(compositedColor.green)}, ${
    Math.round(compositedColor.blue)
  })`;
}

function parseHexadecimalColorChannel(hexadecimal: string, isShort: boolean, offset: number) {
  return parseInt(
    isShort
      ? `${hexadecimal[offset]}${hexadecimal[offset]}`
      : hexadecimal.slice(offset, offset + 2),
    16,
  );
}

function parseCssColorChannel(component: string) {
  const value = parseFloat(component);
  if (!Number.isFinite(value)) return undefined;

  return Math.min(255, Math.max(0, component.endsWith('%') ? value * 2.55 : value));
}

function parseCssAlpha(component: string) {
  const value = parseFloat(component);
  if (!Number.isFinite(value)) return undefined;

  return Math.min(1, Math.max(0, component.endsWith('%') ? value / 100 : value));
}
