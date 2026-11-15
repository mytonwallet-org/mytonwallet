import { address, coins, network, timestamp } from './protocol.js';
import type { Chain } from './protocol.js';

export type TradeMessage = Readonly<{ to: string; amount: string; payload: string | null; stateInit: string | null }>;
export type TransactionPlan = Readonly<{
  account: string; chain: Chain; expiresAt: number; messages: readonly TradeMessage[];
}>;
function boc(value: unknown): string | null {
  if (value === null) return null;
  if (typeof value !== 'string' || value.length > 65536 || value.length === 0
    || value.length % 4 !== 0 || !/^[A-Za-z0-9+/]+={0,2}$/.test(value)) throw Error('Invalid encoded cell');
  // Structural BOC decoding/code validation belongs to the independent, chain-specific builder.
  return value;
}
export function freezePlan(plan: TransactionPlan, now: number): TransactionPlan {
  address(plan.account); network(plan.chain);
  if (timestamp(plan.expiresAt) <= timestamp(now) || plan.expiresAt > now + 300) throw Error('Expired transaction plan');
  if (!Array.isArray(plan.messages) || plan.messages.length < 1 || plan.messages.length > 4) throw Error('Unexpected message count');
  const messages = plan.messages.map(m => Object.freeze({ to: address(m.to), amount: coins(m.amount, true).toString(), payload: boc(m.payload), stateInit: boc(m.stateInit) }));
  coins(messages.reduce((sum, m) => sum + BigInt(m.amount), 0n).toString(), true);
  return Object.freeze({ account: plan.account, chain: plan.chain, expiresAt: plan.expiresAt, messages: Object.freeze(messages) });
}

/** Compare against a locally constructed, independently verified plan, never another API response. */
export function verifyProviderMessages(incoming: readonly TradeMessage[], local: TransactionPlan, now: number): TransactionPlan {
  const expected = freezePlan(local, now);
  if (!Array.isArray(incoming) || incoming.length !== expected.messages.length) throw Error('Provider added or removed a message');
  for (let i = 0; i < incoming.length; i++) {
    const a = incoming[i]!, b = expected.messages[i]!;
    if (address(a.to) !== b.to || coins(a.amount, true).toString() !== b.amount
      || boc(a.payload) !== b.payload || boc(a.stateInit) !== b.stateInit) throw Error('Provider transaction differs from the reviewed local plan');
  }
  return expected;
}

export type EmulationEvidence = Readonly<{
  plan: TransactionPlan; stateHash: string; observedAt: number; allActionsSucceeded: boolean;
  verifiedRecipients: boolean; verifiedOwnership: boolean; feesWithinBudget: boolean;
}>;
/** No transaction is sent here. The wallet must still recheck account and fresh chain state at confirmation. */
export function validateEmulation(expected: TransactionPlan, evidence: EmulationEvidence, stateHash: string, now: number): void {
  freezePlan(expected, now);
  if (!/^[a-f0-9]{64}$/.test(stateHash) || evidence.stateHash !== stateHash) throw Error('Emulated the wrong chain state');
  if (evidence.plan.account !== expected.account || evidence.plan.chain !== expected.chain
    || evidence.plan.expiresAt !== expected.expiresAt) throw Error('Emulated the wrong account or intent');
  verifyProviderMessages(evidence.plan.messages, expected, now);
  if (timestamp(evidence.observedAt) > timestamp(now) || now - evidence.observedAt > 15) throw Error('Stale emulation');
  for (const flag of [evidence.allActionsSucceeded, evidence.verifiedRecipients, evidence.verifiedOwnership, evidence.feesWithinBudget]) {
    if (flag !== true) throw Error('Incomplete or failed emulation');
  }
}
