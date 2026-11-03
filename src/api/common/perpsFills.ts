import type { ApiPerpsRawActivityItem as ApiPerpsActivityItem } from '../types/perps';
import type { ApiPerpsRawFill as ApiPerpsFill } from '../types/perpsTrading';

import { Big } from '../../lib/big.js';

type PositionHistory = { size: string; entryPrice?: string; openedAt?: number };

/** The backend returns mixed raw activities; only executions belong in position history. */
export function normalizePerpsActivityFills(activities: ApiPerpsActivityItem[]): ApiPerpsFill[] {
  const fills = activities.filter((item) => item.kind === 'fill').map((item): ApiPerpsFill => {
    const textKeys = ['coin', 'side', 'dir', 'feeToken'] as const;
    const amountKeys = ['px', 'sz', 'startPosition', 'closedPnl', 'fee'] as const;
    if (textKeys.some((key) => typeof item[key] !== 'string' || !item[key])
      || amountKeys.some((key) => !isDecimal(item[key]))
      || ['tid', 'oid', 'time'].some((key) => !Number.isSafeInteger(item[key]) || Number(item[key]) < 0)
      || ((item.builderFee ?? undefined) !== undefined && !isDecimal(item.builderFee))) {
      throw new Error('PerpsIncompleteData');
    }
    let liquidation: ApiPerpsFill['liquidation'];
    if ((item.liquidation ?? undefined) !== undefined) {
      const raw = item.liquidation as Record<string, unknown>;
      if (typeof raw !== 'object' || !isDecimal(String(raw.markPx)) || typeof raw.method !== 'string') {
        throw new Error('PerpsIncompleteData');
      }
      liquidation = {
        markPx: String(raw.markPx), method: raw.method,
        liquidatedUser: typeof raw.liquidatedUser === 'string' ? raw.liquidatedUser : undefined,
      };
    }
    return {
      coin: item.coin as string, tid: item.tid as number, oid: item.oid as number, time: item.time,
      px: item.px as string, sz: item.sz as string, side: item.side as string, dir: item.dir as string,
      startPosition: item.startPosition as string, closedPnl: item.closedPnl as string,
      fee: item.fee as string, feeToken: item.feeToken as string,
      builderFee: item.builderFee as string | undefined ?? undefined,
      hash: typeof item.hash === 'string' ? item.hash : undefined,
      liquidation,
    };
  });
  return normalizePerpsFills(fills);
}

function isDecimal(value: unknown): value is string {
  if (typeof value !== 'string') return false;
  try {
    Big(value);
    return true;
  } catch {
    return false;
  }
}

/** Fill history does not contain leverage, margin, or wallet withdrawal amounts. */
export function normalizePerpsFills(fills: ApiPerpsFill[]): ApiPerpsFill[] {
  const history = new Map<string, PositionHistory>();
  const result: ApiPerpsFill[] = [];
  const latestByCoin = new Map<string, number>();
  const unique = [...new Map(fills
    .filter((fill) => !fill.coin.startsWith('@') && !fill.coin.includes('/'))
    .map((fill) => [`${fill.time}/${fill.coin}/${fill.tid}`, fill])).values()]
    .sort((a, b) => a.time - b.time);
  const blocks = new Map<string, ApiPerpsFill[]>();
  for (const fill of unique) {
    const key = `${fill.time}/${fill.coin}`;
    blocks.set(key, [...(blocks.get(key) ?? []), fill]);
  }

  for (const block of blocks.values()) {
    // Trade IDs are hashes. Same-block execution order must follow start/end quantities instead.
    const ordered = orderBlockFills(block, history.get(block[0].coin)?.size);
    if (!ordered) {
      history.delete(block[0].coin);
      latestByCoin.delete(block[0].coin);
    }
    for (const raw of ordered ?? block) {
      const fill = normalizeFill(raw, history.get(raw.coin));
      if (ordered) {
        history.set(fill.coin, {
          size: fill.endPosition ?? '',
          entryPrice: fill.entryPrice,
          openedAt: fill.positionOpenedAt,
        });
      } else fill.positionOpenedAt = undefined;
      const previousIndex = latestByCoin.get(fill.coin);
      const previous = previousIndex === undefined ? undefined : result[previousIndex];
      if (ordered && previous && canCombine(previous, fill)) {
        const size = Big(previous.sz).plus(fill.sz);
        const notional = Big(previous.notional!).plus(fill.notional!);
        const price = notional.div(size);
        result[previousIndex!] = {
          ...previous,
          time: fill.time,
          sz: size.toFixed(),
          px: price.toFixed(),
          notional: notional.toFixed(),
          fee: Big(previous.fee).plus(fill.fee).toFixed(),
          builderFee: previous.builderFee !== undefined && fill.builderFee !== undefined
            ? Big(previous.builderFee).plus(fill.builderFee).toFixed() : undefined,
          closedPnl: Big(previous.closedPnl).plus(fill.closedPnl).toFixed(),
          netPnl: previous.netPnl !== undefined && fill.netPnl !== undefined
            ? Big(previous.netPnl).plus(fill.netPnl).toFixed() : undefined,
          eventKind: previous.eventKind === 'opened' ? 'opened' : fill.eventKind,
          entryPrice: fill.entryPrice,
          endPosition: fill.endPosition,
          positionSize: fill.positionSize,
          previousNotional: Big(previous.previousSize!).mul(price).toFixed(),
          positionNotional: Big(fill.positionSize!).mul(price).toFixed(),
          hash: previous.hash === fill.hash ? previous.hash : undefined,
          fillIds: [...previous.fillIds!, ...fill.fillIds!],
        };
      } else {
        if (ordered) latestByCoin.set(fill.coin, result.length);
        result.push(fill);
      }
    }
  }
  return result.reverse().sort((a, b) => b.time - a.time);
}

function orderBlockFills(fills: ApiPerpsFill[], previousSize?: string): ApiPerpsFill[] | undefined {
  if (fills.length === 1) return fills;
  try {
    const remaining = fills.map((fill) => {
      if (!['A', 'B'].includes(fill.side) || Big(fill.sz).lte(0)) throw new Error('Invalid fill');
      const start = Big(fill.startPosition);
      return { fill, start: start.toFixed(), end: start.plus(Big(fill.sz).mul(fill.side === 'B' ? 1 : -1)).toFixed() };
    });
    const matchingPrevious = remaining.filter((fill) => fill.start === previousSize);
    const heads = matchingPrevious.length ? matchingPrevious
      : remaining.filter((fill) => !remaining.some((other) => other.end === fill.start));
    if (heads.length !== 1) return undefined;
    let size = heads[0].start;
    const result: ApiPerpsFill[] = [];
    while (remaining.length) {
      const candidates = remaining.filter((fill) => fill.start === size);
      if (candidates.length !== 1) return undefined;
      const next = candidates[0];
      result.push(next.fill);
      remaining.splice(remaining.indexOf(next), 1);
      size = next.end;
    }
    return result;
  } catch {
    return undefined;
  }
}

function normalizeFill(raw: ApiPerpsFill, history?: PositionHistory): ApiPerpsFill {
  const fill: ApiPerpsFill = {
    ...raw,
    // Hyperliquid omits this included component when it is zero.
    builderFee: raw.builderFee ?? '0',
    liquidation: raw.liquidation ? { ...raw.liquidation, markPx: String(raw.liquidation.markPx) } : undefined,
    eventKind: undefined,
    positionSide: undefined,
    netPnl: undefined,
    notional: undefined,
    previousSize: undefined,
    positionSize: undefined,
    previousNotional: undefined,
    positionNotional: undefined,
    endPosition: undefined,
    entryPrice: undefined,
    positionOpenedAt: undefined,
    fillIds: [raw.tid],
  };
  try {
    const start = Big(raw.startPosition);
    const size = Big(raw.sz);
    const price = Big(raw.px);
    if (size.lte(0) || price.lte(0) || !['A', 'B'].includes(raw.side)) return fill;
    const end = start.plus(size.mul(raw.side === 'B' ? 1 : -1));
    const side = raw.dir.endsWith('Short') ? 'short' : 'long';
    const closing = raw.dir.startsWith('Close');
    const expectedBuy = closing ? side === 'short' : side === 'long';
    const sameDirection = side === 'long' ? start.gte(0) && end.gte(0) : start.lte(0) && end.lte(0);
    const recognized = /^(Open|Close) (Long|Short)$/.test(raw.dir)
      && expectedBuy === (raw.side === 'B') && sameDirection && (!closing || !start.eq(0));
    fill.endPosition = end.toFixed();
    fill.notional = size.mul(price).toFixed();
    fill.previousSize = start.abs().toFixed();
    fill.positionSize = end.abs().toFixed();
    fill.previousNotional = start.abs().mul(price).toFixed();
    fill.positionNotional = end.abs().mul(price).toFixed();
    if (!recognized) return fill;

    const continuous = history?.size === start.toFixed();
    const entry = closing
      ? continuous ? history.entryPrice : undefined
      : start.eq(0)
        ? price.toFixed()
        : continuous && history.entryPrice !== undefined
          ? Big(history.entryPrice).mul(start.abs()).plus(price.mul(size)).div(end.abs()).toFixed()
          : undefined;
    return {
      ...fill,
      eventKind: raw.liquidation && closing ? 'liquidated'
        : closing ? end.eq(0) ? 'closed' : 'reduced' : start.eq(0) ? 'opened' : 'increased',
      positionSide: side,
      netPnl: raw.feeToken === 'USDC' ? Big(raw.closedPnl).minus(raw.fee).toFixed() : undefined,
      entryPrice: entry,
      positionOpenedAt: !closing && start.eq(0) ? raw.time : continuous ? history.openedAt : undefined,
    };
  } catch {
    // Preserve the raw execution, without exposing a malformed row as a valid financial event.
    return fill;
  }
}

function canCombine(previous: ApiPerpsFill, fill: ApiPerpsFill): boolean {
  return previous.eventKind !== undefined && fill.eventKind !== undefined
    && previous.oid === fill.oid && previous.oid > 0
    && previous.dir === fill.dir && previous.side === fill.side && previous.feeToken === fill.feeToken
    && previous.endPosition === Big(fill.startPosition).toFixed()
    && JSON.stringify(previous.liquidation) === JSON.stringify(fill.liquidation);
}
