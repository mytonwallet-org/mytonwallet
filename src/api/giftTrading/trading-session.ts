import { IntentCoordinator } from './intent.js';
import type { ReviewedIntent, IntentCheck } from './intent.js';
import type { Context, Review, TradeAction } from './review.js';
import type { TransactionPlan } from './transaction.js';
import { PendingJournal } from './journal.js';
import { address, network, timestamp } from './protocol.js';
import { boundedRead } from './bounded.js';
import { requireProviderExecution } from './execution-capabilities.js';

export type TradingPorts = Readonly<{
  resolve: (action: TradeAction, context: Context, signal: AbortSignal) => Promise<{ review: Review; plan: TransactionPlan }>;
  verify: (intent: ReviewedIntent, signal: AbortSignal) => Promise<IntentCheck>;
  accountKind: () => 'software' | 'hardware' | 'watch-only' | 'unsupported';
  policyRevision: () => string;
  /** Optional asynchronous local review/unlock simulator. Must not sign or broadcast.
   * The immutable intent is reverified AFTER this wait, before durable reservation/capture. */
  beforeCapture?: (intent: ReviewedIntent, signal: AbortSignal) => Promise<undefined>;
  /** Optional authenticated local policy lease. Every guard must be synchronous and
   * fail after cancellation/expiry/release; it is checked at the actual capture. */
  withConfirmationPolicy?: (revision: string, signal: AbortSignal, work: (guard: () => void) => Promise<void>) => Promise<void>;
  /** A synchronous local confirmation interceptor. Production signing is NOT wired here. */
  capture: (intent: ReviewedIntent) => undefined;
}>;
/** Finite six-action UI/session controller. No signing/broadcasting capability exists in this class. */
export class TradingSession {
  #context: Context;
  #intent: IntentCoordinator;
  #generation = 0;
  #ready: ReviewedIntent | undefined;
  #revision: string | undefined;
  #accountKind: 'software' | 'hardware' | undefined;
  #abort = new AbortController();
  #ports: TradingPorts;
  constructor(context: Context, ports: TradingPorts, private readonly journal: PendingJournal, private readonly clock: () => number) {
    this.#context = Object.freeze({ account: address(context.account), chain: network(context.chain) });
    this.#intent = new IntentCoordinator(this.#context); this.#ports = Object.freeze({ ...ports });
  }
  cancel(): void { ++this.#generation; this.#ready = undefined; this.#revision = undefined; this.#accountKind = undefined; this.#abort.abort(); this.#abort = new AbortController(); this.#intent.cancel(); }
  switchAccount(context: Context): void { this.cancel(); this.#context = Object.freeze({ account: address(context.account), chain: network(context.chain) }); this.#intent.switchAccount(this.#context); }
  async prepare(action: TradeAction): Promise<ReviewedIntent> {
    this.cancel(); const generation = this.#generation, revision = this.#ports.policyRevision(), accountKind=this.#ports.accountKind();
    if (!revision || revision.length > 128 || (accountKind!=='software'&&accountKind!=='hardware')) throw Error('Account or policy cannot trade');
    const ready = await this.#intent.prepare(async(context,signal) => {
      const resolved = await this.#ports.resolve(action,context,signal);
      requireProviderExecution(resolved.review.provider,action);
      return resolved;
    },this.clock);
    if (generation !== this.#generation || revision !== this.#ports.policyRevision() || accountKind!==this.#ports.accountKind() || ready.review.action !== action) { this.cancel(); throw Error('Trade context changed'); }
    this.#ready = ready; this.#revision = revision; this.#accountKind=accountKind; return ready;
  }
  async confirm(ready: ReviewedIntent): Promise<void> {
    if (ready !== this.#ready) throw Error('Review has been consumed');
    this.#ready = undefined;
    const generation = this.#generation, revision = this.#revision, accountKind=this.#accountKind, signal = this.#abort.signal;
    const work = async (policyGuard: () => void) => {
    let checked: ReviewedIntent | undefined, verifiedAt: number | undefined;
    await this.#intent.confirm(ready,async (intent,signal) => {
      const contextGuard = () => {
        policyGuard();
        signal.throwIfAborted();
        if (generation !== this.#generation || revision !== this.#ports.policyRevision()
          || accountKind!==this.#ports.accountKind() || timestamp(this.clock()) >= ready.review.expiresAt) throw Error('Unlock context changed');
      };
      contextGuard();
      if (this.#ports.beforeCapture) {
        const result = await boundedRead(signal, scoped => this.#ports.beforeCapture!(intent,scoped));
        if (result !== undefined) throw Error('Unexpected unlock result');
        contextGuard();
      }
      const evidence = await this.#ports.verify(intent,signal);
      verifiedAt = evidence.observedAt; return evidence;
    },intent => { checked = intent; return undefined; },this.clock);
    const guard = () => {
      policyGuard();
      signal.throwIfAborted();
      const now = timestamp(this.clock());
      if (generation !== this.#generation || revision !== this.#ports.policyRevision() || accountKind!==this.#ports.accountKind()
        || now >= ready.review.expiresAt || verifiedAt === undefined || verifiedAt > now || now - verifiedAt > 15) throw Error('Confirmation context changed or verification expired');
    };
    guard(); if (checked !== ready) throw Error('Confirmation binding failed');
    // Durable claim is established before the boundary. If execution becomes uncertain, reconcile;
    // never infer failure from a timeout or retry automatically after restart.
    const preparing = this.journal.prepare(ready,this.clock());
    let reservation;
    try { reservation = await boundedRead(signal,() => preparing); }
    catch (error) {
      // Aborting the wait does not abort IndexedDB's durable commit. A late capability is
      // never executed; close it and release its own claim. Failed cleanup stays uncertain.
      void preparing.then(late => late.cancelBeforeHandoff()).catch(() => undefined);
      throw error;
    }
    try { reservation.capture(guard,() => this.#ports.capture(ready)); }
    catch (error) {
      // False after capture began: do not confuse a thrown/lost executor response with no send.
      try { await reservation.cancelBeforeHandoff(); } catch { /* Preserve claim for reconciliation. */ }
      throw error;
    }
    };
    if (this.#ports.withConfirmationPolicy) {
      if (revision === undefined) throw Error('No reviewed policy');
      await this.#ports.withConfirmationPolicy(revision,signal,work);
    } else { await work(() => undefined); }
  }
}
