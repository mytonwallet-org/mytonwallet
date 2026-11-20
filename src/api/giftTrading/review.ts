import { address, coins, decodeReference, network, timestamp } from './protocol.js';
import type { Chain, MarketReference } from './protocol.js';

export type TradeAction = 'list' | 'buy' | 'cancel-sale' | 'make-offer' | 'accept-offer' | 'cancel-offer';
export type Context = Readonly<{ account: string; chain: Chain }>;
export type Review = Readonly<{
  action: TradeAction; context: Context; reference: MarketReference; counterparty: string;
  amount: string; fee: string; royalty: string; gasBudget: string; expiresAt: number;
  feeRecipient: string; royaltyRecipient: string;
  chainStateHash: string; authority: string; provider: string;
}>;
export function validateReview(review: Review, context: Context, now: number): void {
  if (!['list','buy','cancel-sale','make-offer','accept-offer','cancel-offer'].includes(review.action)) throw new Error('Unsupported action');
  if (address(review.context.account) !== address(context.account) || network(review.context.chain) !== network(context.chain)) throw new Error('Account changed');
  if (review.reference.chain !== context.chain || review.reference.version !== 1) throw new Error('Network changed');
  address(review.reference.nft); address(review.reference.contract); address(review.counterparty); address(review.authority);
  address(review.feeRecipient); address(review.royaltyRecipient);
  if (['list','buy','cancel-sale'].includes(review.action) ? review.reference.kind !== 'sale' : review.reference.kind !== 'offer') throw new Error('Wrong contract kind');
  coins(review.amount, !review.action.startsWith('cancel')); coins(review.fee); coins(review.royalty); coins(review.gasBudget);
  if (!review.action.startsWith('cancel') && coins(review.fee) + coins(review.royalty) >= coins(review.amount)) throw new Error('Invalid fees');
  if (!/^[a-f0-9]{64}$/.test(review.chainStateHash) || !/^[a-z][a-z0-9-]{0,31}$/.test(review.provider)) throw new Error('Missing verification context');
  if (timestamp(review.expiresAt) <= timestamp(now) || review.expiresAt > now + 300) throw new Error('Stale or overlong review');
}

/** Coordinates review only. There is deliberately no sign/send method in this experimental module. */
export class ReviewCoordinator {
  #generation = 0;
  #context: Context;
  #controller: AbortController | undefined;
  #review: Review | undefined;
  #claiming = false;
  constructor(context: Context) { this.#context = Object.freeze({ account: address(context.account), chain: network(context.chain) }); }
  cancel(): void { ++this.#generation; this.#controller?.abort(); this.#controller = undefined; this.#review = undefined; this.#claiming = false; }
  switchAccount(context: Context): void {
    this.cancel(); this.#context = Object.freeze({ account: address(context.account), chain: network(context.chain) });
  }
  async prepare(resolve: (context: Context, signal: AbortSignal) => Promise<Review>, now: () => number): Promise<Review> {
    this.cancel();
    const generation = this.#generation, context = this.#context, controller = new AbortController();
    this.#controller = controller;
    const incoming = await resolve(context,controller.signal);
    controller.signal.throwIfAborted();
    if (generation !== this.#generation) throw new Error('Superseded review');
    // Copy nested values before exposing them to UI; caller-owned objects must not change confirmation intent.
    const result = Object.freeze({ ...incoming, context: Object.freeze({ ...incoming.context }), reference: Object.freeze({ ...incoming.reference }) });
    validateReview(result,context,now()); this.#review = result; return result;
  }
  async recheck(review: Review, verify: (review: Review, signal: AbortSignal) => Promise<void>, now: () => number): Promise<void> {
    if (this.#claiming || review !== this.#review || !this.#controller) throw new Error('Review is not current');
    this.#claiming = true; this.#review = undefined;
    const generation = this.#generation, controller = this.#controller;
    try {
      validateReview(review,this.#context,now());
      await verify(review,controller.signal);
      controller.signal.throwIfAborted();
      if (generation !== this.#generation) throw new Error('Account or intent changed');
      validateReview(review,this.#context,now());
      // Recheck is consumed even on failure. A fresh review is required before a retry.
    } finally { if (generation === this.#generation) this.#claiming = false; }
  }
}

export type SaleSnapshot = Readonly<{
  chain: Chain; contract: string; codeHash: string; stateHash: string; nft: string;
  seller: string; authority: string; feeAddress: string; royaltyAddress: string;
  fullPrice: string; feeFactor: number; royaltyFactor: number; isComplete: boolean;
  nftOwner: string; nftCodeHash: string; collection: string; collectionVerified: boolean; observedAt: number;
}>;
export type ContractPolicy = Readonly<{ saleCodeHashes: readonly string[]; nftCodeHashes: readonly string[];
  giftCollections: readonly string[]; authorities: readonly string[]; maxFeeFactor: number; maxAgeSeconds: number }>;
export function assertSaleFreshness(observedAt: number, now: number, lifetime: number): void {
  if (timestamp(observedAt) > timestamp(now) || now - observedAt > lifetime) throw Error('Stale chain state');
}

/** Input must come from an independent chain reader, never solely from a marketplace's getter JSON. */
export function resolveSale(referenceText: string, context: Context, sale: SaleSnapshot, policy: ContractPolicy, now: number,
  purpose: 'buy' | 'browse' = 'buy'): Omit<Review,'gasBudget'> & { gasBudget: null } {
  const ref = decodeReference(referenceText,context.chain);
  const lifetime = policy.maxAgeSeconds;
  if (!Number.isSafeInteger(lifetime) || lifetime < 1 || lifetime > 60 || !Number.isSafeInteger(policy.maxFeeFactor) || policy.maxFeeFactor < 0 || policy.maxFeeFactor >= 100000) throw new Error('Invalid verification policy');
  if (ref.kind !== 'sale' || ref.chain !== network(sale.chain) || ref.contract !== address(sale.contract) || ref.nft !== address(sale.nft)) throw new Error('Listing mismatch');
  if (!policy.saleCodeHashes.includes(sale.codeHash) || !/^[a-f0-9]{64}$/.test(sale.codeHash)) throw new Error('Unknown contract code');
  if (!/^[a-f0-9]{64}$/.test(sale.nftCodeHash) || !policy.nftCodeHashes.includes(sale.nftCodeHash)
    || sale.collectionVerified !== true || !policy.giftCollections.includes(address(sale.collection))) throw Error('Unsupported or unverified gift');
  if (!policy.authorities.includes(address(sale.authority))) throw new Error('Unknown cancellation authority');
  if (sale.isComplete !== false || address(sale.nftOwner) !== sale.contract) throw new Error('NFT not held by active sale');
  assertSaleFreshness(sale.observedAt,now,lifetime);
  const seller = address(sale.seller); address(sale.feeAddress); address(sale.royaltyAddress);
  if (seller === address(context.account) && purpose !== 'browse') throw new Error('Cannot buy own listing');
  for (const factor of [sale.feeFactor,sale.royaltyFactor]) if (!Number.isSafeInteger(factor) || factor < 0 || factor >= 100000) throw new Error('Invalid fee factor');
  if (sale.feeFactor > policy.maxFeeFactor || sale.feeFactor + sale.royaltyFactor >= 100000) throw new Error('Excessive fees');
  const price = coins(sale.fullPrice,true);
  if (!/^[a-f0-9]{64}$/.test(sale.stateHash)) throw new Error('Invalid chain state hash');
  const result = {
    action:'buy' as const, context:{...context}, reference:ref, counterparty:seller, amount:price.toString(),
    fee:(price * BigInt(sale.feeFactor) / 100000n).toString(), royalty:(price * BigInt(sale.royaltyFactor) / 100000n).toString(),
    feeRecipient:sale.feeAddress, royaltyRecipient:sale.royaltyAddress,
    // This resolver is incomplete until emulation supplies gas. It cannot authorize signing.
    gasBudget:null, expiresAt:Math.min(now+60,sale.observedAt+lifetime), chainStateHash:sale.stateHash,
    authority:sale.authority, provider:'wallet-market'
  };
  return result;
}

/** Fail closed: shipping this foundation never enables a new financial operation in an existing wallet. */
export const PRODUCTION_TRADING_ENABLED = false as const;
