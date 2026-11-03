import type { ApiPerpsRawActivityItem } from '../types/perps';
import type { ApiPerpsCashFlow } from '../types/perpsTrading';

import { Big } from '../../lib/big.js';

/** Interpret ledger amounts relative to this wallet's perpetuals accounts, never as trade P&L. */
export function normalizePerpsCashFlows(items: ApiPerpsRawActivityItem[], address: string): ApiPerpsCashFlow[] {
  const result = new Map<string, ApiPerpsCashFlow>();
  for (const item of items) {
    if (item.kind !== 'fundingPayment' && item.kind !== 'ledgerUpdate') continue;
    const delta = item.delta as Record<string, unknown> | undefined;
    if (!delta || typeof delta !== 'object' || !Number.isSafeInteger(item.time) || item.time < 0) {
      throw new Error('PerpsIncompleteData');
    }
    const flow = normalize(item, delta, address.toLowerCase());
    if (flow) result.set(flow.id, flow);
  }
  return [...result.values()].sort((a, b) => b.time - a.time || a.id.localeCompare(b.id));
}

function normalize(
  item: ApiPerpsRawActivityItem, delta: Record<string, unknown>, address: string,
): ApiPerpsCashFlow | undefined {
  let kind: ApiPerpsCashFlow['kind'];
  let direction: ApiPerpsCashFlow['direction'];
  let amount: string;
  let token = 'USDC';
  let sourceDex: string | undefined;
  let destinationDex: string | undefined;
  const sourceAddress = text(delta.user);
  const destinationAddress = text(delta.destination);
  const fromSelf = sourceAddress?.toLowerCase() === address;
  const toSelf = destinationAddress?.toLowerCase() === address;
  let coin: string | undefined;
  let positionSize: string | undefined;
  let positionSide: ApiPerpsCashFlow['positionSide'];
  let fundingRate: string | undefined;
  const fees: ApiPerpsCashFlow['fees'] = [];

  if (item.kind === 'fundingPayment') {
    if (delta.type !== 'funding') return undefined;
    kind = 'funding';
    coin = text(delta.coin);
    if (!coin) throw new Error('PerpsIncompleteData');
    const signedAmount = decimal(delta.usdc);
    direction = Big(signedAmount).lt(0) ? 'outgoing' : 'incoming';
    amount = Big(signedAmount).abs().toFixed();
    const size = decimal(delta.szi);
    positionSize = Big(size).abs().toFixed();
    positionSide = Big(size).eq(0) ? undefined : Big(size).lt(0) ? 'short' : 'long';
    fundingRate = decimal(delta.fundingRate);
  } else {
    switch (delta.type) {
      case 'deposit':
      case 'withdraw':
        kind = delta.type === 'deposit' ? 'deposit' : 'withdrawal';
        direction = kind === 'deposit' ? 'incoming' : 'outgoing';
        amount = unsigned(delta.usdc);
        break;
      case 'accountClassTransfer':
        if (typeof delta.toPerp !== 'boolean') throw new Error('PerpsIncompleteData');
        kind = 'transfer';
        direction = delta.toPerp ? 'incoming' : 'outgoing';
        sourceDex = delta.toPerp ? 'spot' : '';
        destinationDex = delta.toPerp ? '' : 'spot';
        amount = unsigned(delta.usdc);
        break;
      case 'internalTransfer':
      case 'subAccountTransfer':
      case 'send': {
        if (!fromSelf && !toSelf) return undefined;
        kind = 'transfer';
        sourceDex = delta.type === 'send' ? text(delta.sourceDex, true) : '';
        destinationDex = delta.type === 'send' ? text(delta.destinationDex, true) : '';
        if (sourceDex === undefined || destinationDex === undefined) throw new Error('PerpsIncompleteData');
        const debitsPerps = fromSelf && sourceDex !== 'spot';
        const creditsPerps = toSelf && destinationDex !== 'spot';
        if (!debitsPerps && !creditsPerps) return undefined;
        direction = debitsPerps && creditsPerps ? 'internal' : creditsPerps ? 'incoming' : 'outgoing';
        amount = unsigned(delta.type === 'send' ? delta.amount : delta.usdc);
        if (delta.type === 'send') {
          token = text(delta.token) ?? '';
          if (!token) throw new Error('PerpsIncompleteData');
        }
        break;
      }
      // Spot-only transfers, vault operations, rewards and liquidations are not Futures cash transfers.
      default: return undefined;
    }
    // Transfer fees belong to the sender. Do not charge the recipient or infer an absent fee currency.
    if ((direction !== 'incoming' || fromSelf) && (delta.fee ?? undefined) !== undefined) {
      const fee = unsigned(delta.fee);
      const feeToken = text(delta.feeToken) ?? (delta.type !== 'send' ? 'USDC' : undefined);
      if (Big(fee).gt(0) && feeToken) fees.push({ amount: fee, token: feeToken });
    }
    if (fromSelf && (delta.nativeTokenFee ?? undefined) !== undefined) {
      const fee = unsigned(delta.nativeTokenFee);
      if (Big(fee).gt(0)) fees.push({ amount: fee, token: 'HYPE' });
    }
  }
  // Funding hashes are often all-zero. Include market, routing and amount to keep distinct ledger rows.
  const hash = text(item.hash);
  const id = 'cashFlow/' + JSON.stringify([
    item.kind, item.time, item.dex, delta.type, hash ?? '', coin ?? '',
    sourceDex ?? '', destinationDex ?? '', sourceAddress?.toLowerCase() ?? '', destinationAddress?.toLowerCase() ?? '',
    direction, amount, token, fundingRate ?? '', positionSize ?? '', positionSide ?? '',
  ]);
  return {
    id, kind, direction, time: item.time, amount, token, coin, assetId: item.asset,
    positionSide, positionSize, fundingRate, sourceDex, destinationDex, sourceAddress, destinationAddress, fees,
    hash: hash && !/^0x0+$/i.test(hash) ? hash : undefined,
  };
}

function text(value: unknown, allowEmpty = false): string | undefined {
  return typeof value === 'string' && (allowEmpty || value.length > 0) ? value : undefined;
}

function decimal(value: unknown): string {
  if (typeof value !== 'string') throw new Error('PerpsIncompleteData');
  try {
    return Big(value.trim()).toFixed();
  } catch {
    throw new Error('PerpsIncompleteData');
  }
}

function unsigned(value: unknown): string {
  const amount = decimal(value);
  if (Big(amount).lt(0)) throw new Error('PerpsIncompleteData');
  return amount;
}
