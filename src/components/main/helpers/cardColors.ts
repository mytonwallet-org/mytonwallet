import type { UserToken } from '../../../global/types';
import type { RGBColor } from '../../../util/colors';

import { STAKED_TON_SLUG, TONCOIN, TRX } from '../../../config';
import { getTrustedUsdtSlugs } from '../../../util/chain';
import { deltaE, hex2rgb } from '../../../util/colors';

const TOKEN_CARD_COLORS: Record<string, RGBColor> = {
  green: [80, 135, 51],
  orange: [173, 84, 54],
  pink: [154, 60, 144],
  purple: [104, 48, 149],
  red: [156, 52, 75],
  sea: [43, 116, 123],
  tegro: [3, 93, 229],
  blue: [47, 108, 173],
};

export const TOKEN_EXCEPTION_COLORS: Record<string, string> = {
  [TONCOIN.slug]: 'blue',
  [TRX.slug]: 'red',
  [STAKED_TON_SLUG]: 'green',
};

const DISTANCE_THRESHOLD = 35;

export function calculateTokenCardColor(token?: UserToken): string {
  let closestColor = 'blue';
  let smallestDistance = Infinity;

  if (!token) return closestColor;

  if (getTrustedUsdtSlugs().has(token.slug)) {
    return 'sea';
  }

  if (TOKEN_EXCEPTION_COLORS[token.slug]) {
    return TOKEN_EXCEPTION_COLORS[token.slug];
  }

  if (!token.color) return closestColor;

  const tokenRgbColor = hex2rgb(token.color);

  Object.entries(TOKEN_CARD_COLORS).forEach(([colorName, colorValue]) => {
    const distance = deltaE(tokenRgbColor, colorValue);
    if (distance < smallestDistance) {
      smallestDistance = distance;
      closestColor = colorName;
    }
  });

  if (smallestDistance > DISTANCE_THRESHOLD) {
    return 'blue';
  }

  return closestColor;
}
