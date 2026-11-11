import type { ApiPerpsActivitiesSnapshot } from '../types/perps';
import type { ApiPerpsActivityHistory, ApiPerpsFill } from '../types/perpsTrading';

import { Big } from '../../lib/big.js';
import { getPerpsCoinFromAssetId } from './perps';

const eventKinds = { open: 'opened', increase: 'increased', reduce: 'reduced', close: 'closed',
  liquidation: 'liquidated' } as const;

/**
 * Preserve backend order IDs and event IDs. Unreported position sizes stay unknown.
 * `hasActivity` also counts trades without a catalogue asset, so an unrendered trade still proves account history.
 */
export function normalizePerpsActivityPage(
  snapshot: ApiPerpsActivitiesSnapshot, address: string,
): ApiPerpsActivityHistory {
  if (!snapshot || snapshot.address?.toLowerCase() !== address.toLowerCase() || !Array.isArray(snapshot.activities)) {
    throw new Error('PerpsIncompleteData');
  }
  const fills: ApiPerpsFill[] = [];
  for (const trade of snapshot.activities) {
    if (!(trade.kind in eventKinds) || !trade.id || !Number.isSafeInteger(trade.timestamp)
      || !['long', 'short'].includes(trade.side)) throw new Error('PerpsIncompleteData');
    if (!trade.assetId) continue;
    for (const amount of [trade.size, trade.entryPrice, trade.exitPrice, trade.notional, trade.realizedPnl,
      trade.collateralBefore, trade.collateralAfter, trade.positionSizeBefore, trade.positionSizeAfter,
      trade.fees?.trading, trade.fees?.builder, trade.fees?.bridge]) {
      if (amount !== undefined) Big(amount);
    }
    const coin = getPerpsCoinFromAssetId(trade.assetId);
    const price = trade.exitPrice ?? trade.entryPrice;
    const positionValue = (size?: string) => (
      size === undefined || price === undefined ? undefined : Big(size).mul(price).toFixed()
    );
    fills.push({
      activityId: trade.id, assetId: trade.assetId, coin, oid: trade.orderId,
      time: trade.timestamp, eventKind: eventKinds[trade.kind], positionSide: trade.side,
      px: price, sz: trade.size, notional: trade.notional,
      entryPrice: trade.entryPrice, positionOpenedAt: trade.positionOpenedAt, leverage: trade.leverage,
      collateralBefore: trade.collateralBefore, collateralAfter: trade.collateralAfter,
      previousSize: trade.positionSizeBefore, positionSize: trade.positionSizeAfter,
      previousNotional: positionValue(trade.positionSizeBefore),
      positionNotional: positionValue(trade.positionSizeAfter),
      closedPnl: trade.realizedPnl, fee: trade.fees?.trading,
      receiptFees: trade.fees?.trading === undefined ? undefined : {
        trading: trade.fees.trading, service: trade.fees.builder, bridge: trade.fees.bridge,
        exchange: trade.fees.builder === undefined ? undefined
          : Big(trade.fees.trading).minus(trade.fees.builder).toFixed(),
        total: Big(trade.fees.trading).plus(trade.fees.bridge ?? 0).toFixed(),
      },
      bridgeFee: trade.fees?.bridge, feeToken: 'USDC',
      netPnl: trade.realizedPnl !== undefined && trade.fees?.trading !== undefined
        ? Big(trade.realizedPnl).minus(trade.fees.trading).toFixed() : undefined,
      deposit: trade.deposit, withdrawal: trade.withdrawal,
    });
  }
  return {
    fills: fills.sort((a, b) => b.time - a.time),
    nextCursor: snapshot.nextCursor,
    hasActivity: snapshot.activities.length > 0 || Boolean(snapshot.nextCursor),
  };
}
