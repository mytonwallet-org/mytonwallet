import { address, coins, timestamp } from './protocol.js';
import type { TradeAction } from './review.js';

export type FeeEstimate = Readonly<{ stateHash: string; networkConfigHash: string; observedAt: number;
  attachedReserve: string; walletFeeReserve: string; storageReserve: string }>;
/** All fees are exact nanotons. No lab fixed gas values are promoted to production estimates. */
export function tradeEconomics(input: Readonly<{ action: TradeAction; price: string; fee: string; royalty: string;
  balance: string; maxDebit: string; estimate: FeeEstimate; stateHash: string; networkConfigHash: string;
  now: number; reservePayer: string; reserveRecipient: string; reservePolicy: 'same-payer' | 'pooled-laboratory' }>) {
  const e = input.estimate, price = coins(input.price, true), fee = coins(input.fee), royalty = coins(input.royalty);
  if (!['list','buy','cancel-sale','make-offer','accept-offer','cancel-offer'].includes(input.action)) throw Error('Unknown trade action');
  for (const h of [e.stateHash,e.networkConfigHash,input.stateHash,input.networkConfigHash]) if (!/^[a-f0-9]{64}$/.test(h)) throw Error('Invalid estimate binding');
  timestamp(e.observedAt); timestamp(input.now);
  if (e.stateHash !== input.stateHash || e.networkConfigHash !== input.networkConfigHash
    || e.observedAt > input.now || input.now - e.observedAt > 15 || fee + royalty >= price) throw Error('Stale or invalid economics');
  address(input.reservePayer); address(input.reserveRecipient);
  if (!['same-payer','pooled-laboratory'].includes(input.reservePolicy)) throw Error('Unknown reserve policy');
  if (input.reservePolicy === 'same-payer' && input.reservePayer !== input.reserveRecipient) throw Error('Reserve ownership changed');
  const reserve = coins(e.attachedReserve), wallet = coins(e.walletFeeReserve), storage = coins(e.storageReserve);
  // Storage reserve is part of the attached reserve, never charged twice.
  if (storage > reserve) throw Error('Storage reserve exceeds attached reserve');
  // Sale creation/deposit, accepting an already funded offer and cancellation do not
  // fund the price again. This helper estimates a single action, not an entire trade.
  const principal = input.action === 'buy' || input.action === 'make-offer' ? price : 0n;
  const total = principal + reserve + wallet; coins(total.toString());
  if (total > coins(input.balance) || total > coins(input.maxDebit)) throw Error('Debit cap or balance exceeded');
  return Object.freeze({ price: price.toString(), fee: fee.toString(), royalty: royalty.toString(),
    sellerProceeds: (price-fee-royalty).toString(), principalDebit: principal.toString(), maximumDebit: total.toString(),
    attachedReserve: reserve.toString(), walletFeeReserve: wallet.toString(), storageReserve: storage.toString(),
    reserveRecipient: input.reserveRecipient, productionEligible: false,
    reserveWarning: input.reservePolicy === 'pooled-laboratory'
      ? 'Experimental pooled reserve can benefit another participant; not approved for production'
      : 'Matching payer addresses do not prove contract reserve accounting; production policy is unverified' });
}
