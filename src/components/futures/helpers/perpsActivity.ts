import type { ApiPerpsAccountPosition, ApiPerpsFill, ApiPerpsMarketAsset } from '../../../api/types';
import type { PerpsOpenedActivity } from '../../../global/types';

import { Big } from '../../../lib/big.js';
import { getPerpsFillKey, isPerpsNumber } from '../../../global/helpers/perps';

export type PerpsActivityListItem = PerpsOpenedActivity & { key: string };

/**
 * The trades of the history, newest first. A trade in a market the loaded catalogue does not list cannot open its
 * market, so it is left out, as on iOS.
 */
export function buildPerpsActivityItems(
  fills: ApiPerpsFill[],
  assetsByName?: Record<string, ApiPerpsMarketAsset>,
): PerpsActivityListItem[] {
  return fills
    .filter(({ eventKind, coin }) => eventKind !== undefined && (!assetsByName || assetsByName[coin]))
    .map((fill) => ({ fill, key: getPerpsFillKey(fill) }));
}

/**
 * The trades of one market since its current position opened. The newest trade tells when the position opened only
 * when it left the position as it is now, so otherwise the list shows the recent trades of the market.
 */
export function buildPositionActivityItems(fills: ApiPerpsFill[], position?: ApiPerpsAccountPosition) {
  const newest = fills.reduce<ApiPerpsFill | undefined>((found, fill) => (
    !found || fill.time > found.time ? fill : found
  ), undefined);
  const openedAt = position && newest && isPositionSizeEqual(position.size, newest.positionSize)
    && newest.positionSide === position.side
    ? newest.positionOpenedAt
    : undefined;
  const items: PerpsActivityListItem[] = fills
    .filter(({ eventKind, positionOpenedAt }) => (
      eventKind !== undefined && (openedAt === undefined || positionOpenedAt === openedAt)
    ))
    .map((fill) => ({ fill, key: getPerpsFillKey(fill) }))
    .sort((a, b) => b.fill.time - a.fill.time);

  return { items, isSinceOpening: openedAt !== undefined };
}

// The history keeps the size as the backend writes it, and the SDK writes the size of the position on its own, so the
// same size may come as `0.20` and `0.2`
function isPositionSizeEqual(positionSize: string, fillSize?: string) {
  return isPerpsNumber(fillSize) && Big(fillSize).abs().eq(positionSize);
}
