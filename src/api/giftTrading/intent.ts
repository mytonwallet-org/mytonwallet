import { address, encodeReference, network, timestamp } from './protocol.js';
import { validateReview } from './review.js';
import type { Context, Review } from './review.js';
import { freezePlan, validateEmulation } from './transaction.js';
import type { TransactionPlan, EmulationEvidence } from './transaction.js';
import { boundedRead } from './bounded.js';

export type ReviewedIntent = Readonly<{ id: string; review: Review; plan: TransactionPlan }>;
export type IntentCheck = Readonly<{
  intentId: string; canonicalBlockRoot: string; observedAt: number; emulation: EmulationEvidence;
}>;
export function freezeReview(value: Review, context: Context, now: number): Review {
  const copy: Review = Object.freeze({
    action: value.action, context: Object.freeze({ account: value.context.account, chain: value.context.chain }),
    reference: Object.freeze({ version: value.reference.version, chain: value.reference.chain,
      kind: value.reference.kind, nft: value.reference.nft, contract: value.reference.contract }),
    counterparty: value.counterparty, amount: value.amount, fee: value.fee, royalty: value.royalty,
    gasBudget: value.gasBudget, expiresAt: value.expiresAt, feeRecipient: value.feeRecipient,
    royaltyRecipient: value.royaltyRecipient, chainStateHash: value.chainStateHash,
    authority: value.authority, provider: value.provider,
  });
  validateReview(copy, context, now); return copy;
}
/** Deterministic field order, exact message order and bytes. No provider JSON hashing. */
export async function bindIntent(review: Review, plan: TransactionPlan, context: Context, now: number): Promise<ReviewedIntent> {
  const frozenReview = freezeReview(review, context, now), frozenPlan = freezePlan(plan, now);
  if (frozenPlan.account !== context.account || frozenPlan.chain !== context.chain
    || frozenPlan.expiresAt !== frozenReview.expiresAt) throw Error('Plan and review scope differ');
  encodeReference(frozenReview.reference);
  const r = frozenReview, p = frozenPlan;
  const fields = ['wallet-gift-intent-v2', r.action, r.context.account, r.context.chain, encodeReference(r.reference),
    r.counterparty, r.amount, r.fee, r.royalty, r.gasBudget, String(r.expiresAt), r.feeRecipient, r.royaltyRecipient,
    r.chainStateHash, r.authority, r.provider, p.account, p.chain, String(p.expiresAt), String(p.messages.length),
    ...p.messages.flatMap(m => [m.to, m.amount, m.payload ?? '-', m.stateInit ?? '-'])];
  // All validated wire fields are ASCII. Length-prefixing avoids ambiguous concatenation and is shared with native clients.
  if (fields.some(f => /[^\x20-\x7e]/.test(f))) throw Error('Non-canonical intent field');
  const encoded = new TextEncoder().encode(fields.map(f => `${f.length}:${f}`).join(''));
  const digest = await globalThis.crypto.subtle.digest('SHA-256', encoded);
  const id = Array.from(new Uint8Array(digest), b => b.toString(16).padStart(2, '0')).join('');
  return Object.freeze({ id, review: frozenReview, plan: frozenPlan });
}

/** Foundation only: a trusted local decoder/emulator must establish economic semantics and chain proofs.
 * The callbacks are trust boundaries, NOT cryptographic proof producers supplied by a marketplace.
 * No signer, broadcaster or live transaction transport is implemented here.
 */
export class IntentCoordinator {
  #context: Context;
  #generation = 0;
  #controller: AbortController | undefined;
  #current: ReviewedIntent | undefined;
  constructor(context: Context) { this.#context = Object.freeze({ account: address(context.account), chain: network(context.chain) }); }
  cancel(): void { ++this.#generation; this.#controller?.abort(); this.#controller = undefined; this.#current = undefined; }
  switchAccount(context: Context): void {
    this.cancel(); this.#context = Object.freeze({ account: address(context.account), chain: network(context.chain) });
  }
  async prepare(resolve: (context: Context, signal: AbortSignal) => Promise<{ review: Review; plan: TransactionPlan }>, now: () => number): Promise<ReviewedIntent> {
    this.cancel();
    const generation = this.#generation, context = this.#context, controller = new AbortController();
    this.#controller = controller;
    const incoming = await boundedRead(controller.signal, signal => resolve(context, signal));
    controller.signal.throwIfAborted();
    const intent = await bindIntent(incoming.review, incoming.plan, context, now());
    controller.signal.throwIfAborted();
    if (generation !== this.#generation) throw Error('Superseded intent');
    validateReview(intent.review, context, now()); this.#current = intent; return intent;
  }
  async confirm(intent: ReviewedIntent,
    verify: (intent: ReviewedIntent, signal: AbortSignal) => Promise<IntentCheck>,
    handoff: (intent: ReviewedIntent) => undefined, now: () => number): Promise<void> {
    if (intent !== this.#current || !this.#controller) throw Error('Intent is not current');
    // Consume before the first await, including failures and a second concurrent confirmation.
    this.#current = undefined;
    const generation = this.#generation, controller = this.#controller;
    validateReview(intent.review, this.#context, now());
    const checked = await boundedRead(controller.signal, signal => verify(intent, signal));
    controller.signal.throwIfAborted();
    if (generation !== this.#generation) throw Error('Account or intent changed');
    const clock = timestamp(now());
    validateReview(intent.review, this.#context, clock);
    if (checked.intentId !== intent.id || !/^[a-f0-9]{64}$/.test(checked.canonicalBlockRoot)
      || timestamp(checked.observedAt) > clock || clock - checked.observedAt > 15) throw Error('Unrelated or stale verification');
    validateEmulation(intent.plan, checked.emulation, intent.review.chainStateHash, clock);
    // Synchronous final boundary: the wallet must accept only THIS immutable intent.
    // A hardware/unlock/signing UI integration must separately invalidate its session on account change.
    handoff(intent);
  }
}
