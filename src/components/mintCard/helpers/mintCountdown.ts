import type { ApiCardInfo } from '../../../api/types';

import { toNativeDigits } from '../../../util/nativeDigits';

/**
 * Returns when the mint starts, or `undefined` if there should be no countdown.
 * Only a card with nothing left to mint gets one - if some cards are left, they are on sale already.
 */
export function getMintStartsAt({ notMinted, startsAt }: ApiCardInfo) {
  if (notMinted !== 0 || !startsAt) return undefined;

  const timestamp = Date.parse(startsAt);

  return Number.isNaN(timestamp) ? undefined : timestamp;
}

export function formatMintCountdown(seconds: number) {
  const hours = Math.floor(seconds / 3600);
  const minutes = Math.floor(seconds / 60) % 60;

  return toNativeDigits(`${padTimeUnit(hours)}:${padTimeUnit(minutes)}:${padTimeUnit(seconds % 60)}`);
}

function padTimeUnit(value: number) {
  return String(value).padStart(2, '0');
}
