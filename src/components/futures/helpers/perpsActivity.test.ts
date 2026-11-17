import type { ApiPerpsAccountPosition, ApiPerpsFill, ApiPerpsMarketAsset } from '../../../api/types';

import { buildPerpsActivityItems, buildPositionActivityItems } from './perpsActivity';

function buildFill(fill: Partial<ApiPerpsFill>) {
  return {
    coin: 'BTC', time: 1, eventKind: 'increased', positionSide: 'long', feeToken: 'USDC', ...fill,
  } as ApiPerpsFill;
}

const position = { size: '0.2', side: 'long' } as ApiPerpsAccountPosition;

describe('buildPositionActivityItems', () => {
  it('lists the trades of the current position when the newest trade left it as it is', () => {
    const fills = [
      buildFill({ activityId: 'old', time: 1, positionOpenedAt: 1 }),
      buildFill({ activityId: 'opened', time: 5, positionOpenedAt: 5 }),
      buildFill({ activityId: 'newest', time: 9, positionOpenedAt: 5, positionSize: '0.2' }),
    ];

    const { items, isSinceOpening } = buildPositionActivityItems(fills, position);

    expect(isSinceOpening).toBe(true);
    expect(items.map(({ key }) => key)).toEqual(['newest', 'opened']);
  });

  it('compares the sizes as numbers', () => {
    const fills = [buildFill({ activityId: 'newest', time: 9, positionOpenedAt: 5, positionSize: '0.20' })];

    expect(buildPositionActivityItems(fills, position).isSinceOpening).toBe(true);
  });

  it('lists the recent trades of the market when the history lags behind the position', () => {
    const fills = [buildFill({ activityId: 'newest', time: 9, positionOpenedAt: 5, positionSize: '0.1' })];

    expect(buildPositionActivityItems(fills, position).isSinceOpening).toBe(false);
  });
});

describe('buildPerpsActivityItems', () => {
  it('leaves out trades in markets the loaded catalogue does not list', () => {
    const fills = [buildFill({ activityId: 'btc' }), buildFill({ activityId: 'old', coin: 'OLD' })];
    const assetsByName = { BTC: {} as ApiPerpsMarketAsset };

    expect(buildPerpsActivityItems(fills, assetsByName).map(({ key }) => key)).toEqual(['btc']);
    expect(buildPerpsActivityItems(fills)).toHaveLength(2);
  });
});
