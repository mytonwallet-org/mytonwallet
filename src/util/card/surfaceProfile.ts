import type { ApiNft } from '../../api/types';
import type { CardSurfaceProfile } from './surfaceRenderer';

import attributes from './surfaceAttributes.json';

const PALETTES: Record<string, [string, string]> = {
  silver: ['#272727', '#989898'],
  gold: ['#4C3403', '#B07D1D'],
  platinum: ['#FFFFFF', '#77777F'],
  black: ['#CECECF', '#444546'],
};

const MATERIAL_INTENSITIES: Record<string, number> = {
  black: 0.22,
  platinum: 0.22,
  gold: 0.48,
};
const NFT_MATERIAL_INTENSITY = 0.62;
const DEFAULT_MATERIAL_INTENSITY = 0.28;

// Border gradients go from the first value to the second one, keyed by card type or by the radioactive shine
const BORDER_COLORS: Record<string, [string, string]> = {
  radioactive: ['#5CE850', '#5CE850'],
  black: ['#FFFFFF', '#FFFFFF'],
  platinum: ['#77777F', '#FFFFFF'],
  gold: PALETTES.gold,
  silver: PALETTES.silver,
};
const DEFAULT_BORDER_COLORS: [string, string] = ['#8C94B0', '#BABCC2'];
const BORDER_ALPHAS: Record<string, [number, number]> = {
  radioactive: [0.95, 0.95],
  standard: [0.5, 0.85],
};
const BLACK_BORDER_ALPHAS: [number, number] = [0.06, 0.12];
const BLACK_BORDER_ALPHAS_LIGHT: [number, number] = [0.12, 0.24];
const DEFAULT_BORDER_ALPHAS: [number, number] = [0.4, 0.4];

const BORDER_ANGLES: Partial<Record<string, number>> = {
  up: -80,
  down: 70,
  left: -190,
  right: 10,
  radioactive: -45,
};

export function getCardTextPalette(nft?: ApiNft): [string, string] {
  return PALETTES[nft?.metadata.mtwCardType ?? ''] ?? ['#FFFFFF', '#FFFFFF'];
}

export function getNativeCardMotionSeed(nft: ApiNft) {
  const traits = new Map(
    nft.metadata.attributes?.map((trait) => [trait.trait_type, String(trait.value)]),
  );
  const indices = attributes.map(
    (attribute) => attribute.options.indexOf(traits.get(attribute.name) ?? '') + 1,
  );

  return getCardMotionSeed(indices.every((index) => index > 0) ? indices.join('-') : nft.address);
}

export function getCardSurfaceProfile(
  nft: ApiNft | undefined,
  isGram: boolean,
): CardSurfaceProfile {
  const type = nft?.metadata.mtwCardType ?? (nft ? 'standard' : undefined);
  const isGramSurface = !nft && isGram;

  return {
    isCustom: Boolean(nft),
    isGram: isGramSurface,
    // On the home screen only the Gram card shines; the shine sweep of other cards is off
    shineOpacity: isGramSurface ? 0.33 : 0,
    gramWidth: 120,
    gramBlur: 18,
    material: type === 'black' ? 2 : type && type !== 'standard' ? 1 : 0,
    intensity: isGramSurface ? 0
      : !type ? DEFAULT_MATERIAL_INTENSITY
        : MATERIAL_INTENSITIES[type] ?? NFT_MATERIAL_INTENSITY,
    seed: nft ? getNativeCardMotionSeed(nft) : 0,
  };
}

export function getCardBorder(nft: ApiNft, isDark: boolean) {
  const type = nft.metadata.mtwCardType;
  const kind = nft.metadata.mtwCardBorderShineType === 'radioactive' ? 'radioactive' : type ?? '';
  const colors = BORDER_COLORS[kind] ?? DEFAULT_BORDER_COLORS;
  const alphas = kind === 'black'
    ? (isDark ? BLACK_BORDER_ALPHAS : BLACK_BORDER_ALPHAS_LIGHT)
    : BORDER_ALPHAS[kind] ?? DEFAULT_BORDER_ALPHAS;
  const rgb = colors.map((c) => [1, 3, 5].map((i) => parseInt(c.slice(i, i + 2), 16)));
  const stops = Array.from(
    {
      length: 65,
    },
    (_, i) => {
      const t = i / 64;
      const alpha = alphas[0] * (1 - t) + alphas[1] * t;
      const color = rgb[0].map((v, j) =>
        Math.round((v * alphas[0] * (1 - t) + rgb[1][j] * alphas[1] * t) / alpha),
      );

      return `<stop offset="${t}" stop-color="rgb(${color.join(',')})" stop-opacity="${alpha}"/>`;
    },
  ).join('');

  // A stretched SVG background still keeps its content proportions and leaves empty bands.
  // The gradient is built for the actual size, so it fills the whole border at any aspect ratio.
  const backgroundForSize = (width: number, height: number, gutter = 0) => {
    const dx = -0.2 * width * width;
    const dy = 0.15 * height * height;
    const length = 0.04 * width * width + 0.0225 * height * height;
    const divisor = dx * dx + dy * dy;
    const endX = 0.65 + (dx * length) / divisor;
    const endY = 0.1 + (dy * length) / divisor;
    const svg
      = `<svg xmlns="http://www.w3.org/2000/svg" viewBox="${-gutter} ${-gutter} `
        + `${width + 2 * gutter} ${height + 2 * gutter}" preserveAspectRatio="none"><defs>`
        + `<linearGradient id="g" gradientUnits="userSpaceOnUse" x1="${0.65 * width}" y1="${0.1 * height}"`
        + ` x2="${endX * width}" y2="${endY * height}">${stops}</linearGradient></defs>`
        + `<rect x="${-gutter}" y="${-gutter}" width="${width + 2 * gutter}" height="${height + 2 * gutter}"`
        + ' fill="url(#g)"/></svg>';

    return `url("data:image/svg+xml,${encodeURIComponent(svg)}")`;
  };

  return {
    backgroundForSize,
    angle: type === 'standard' ? BORDER_ANGLES[nft.metadata.mtwCardBorderShineType!] : -45,
  };
}

function getCardMotionSeed(key: string) {
  let hash = 2166136261;

  for (let i = 0; i < key.length; i++) {
    hash ^= key.charCodeAt(i);
    hash = Math.imul(hash, 16777619);
  }

  return (hash >>> 0) % 65536 / 65536;
}
