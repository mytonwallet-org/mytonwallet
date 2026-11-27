import { address, coins, network } from './protocol.js';
import type { Chain } from './protocol.js';

export type Payout = Readonly<{ recipient: string; amount: string; kind: 'seller' | 'royalty' | 'fee' }>;
export type TradeExpectation = Readonly<{
  chain: Chain; nft: string; contract: string; buyer: string; rootMessageHash: string;
  queryId: string; payouts: readonly Payout[];
  contractCodeHash?: string;
}>;
export type TraceMessage = Readonly<{ hash: string; recipient: string; value: string;
  kind: 'seller' | 'royalty' | 'fee' | 'other'; queryId: string }>;
export type TraceReceipt = Readonly<{
  hash: string; parent: string | null; inputMessageHash: string; account: string;
  /** Value declared by the inbound message, retained for existing trace producers. */
  creditedValue: string; success: boolean; messages: readonly TraceMessage[];
  /** Independently decoded from the recipient transaction, never inferred from inbound value. */
  credit?: Readonly<{ amount: string; status: 'confirmed' | 'uncertain' }>;
  transfer: Readonly<{ previousOwner: string; newOwner: string; queryId: string }> | null;
  /** Decoded from authenticated account transactions, never supplied by a marketplace. */
  lineage?: Readonly<{ previousTransactionHash: string; codeHash: string;
    beforeDataHash: string; afterDataHash: string; beforePhase: number; afterPhase: number;
    beforeQuery: string; afterQuery: string }>;
}>;
/** Must be derived by an independent chain-proof reader plus a pinned-code decoder.
 * These DTO checks cannot authenticate RPC replies and must never be fed marketplace JSON as proof.
 */
export type Settlement = Readonly<{
  chain: Chain; rootMessageHash: string; canonical: boolean; traceComplete: boolean;
  receipts: readonly TraceReceipt[];
}>;
const hash = (v: string): string => { if (!/^[a-f0-9]{64}$/.test(v)) throw Error('Invalid trace hash'); return v; };
function query(v: string): string {
  if (typeof v !== 'string' || !/^(0|[1-9][0-9]{0,19})$/.test(v) || BigInt(v) >= 1n << 64n) throw Error('Invalid operation id');
  return v;
}
/** Proves a causal transition at settlement time, NOT current ownership after a subsequent transfer. */
export function settlementStatus(expected: TradeExpectation, trace: Settlement): 'settled' | 'pending' | 'needs-recovery' {
  address(expected.nft); address(expected.contract); address(expected.buyer); query(expected.queryId);
  if (network(expected.chain) !== network(trace.chain) || hash(expected.rootMessageHash) !== hash(trace.rootMessageHash)) throw Error('Unrelated settlement trace');
  if (typeof trace.canonical !== 'boolean' || typeof trace.traceComplete !== 'boolean') throw Error('Missing finality');
  if (!Array.isArray(trace.receipts) || trace.receipts.length > 128) throw Error('Trace budget exceeded');
  if (!Array.isArray(expected.payouts) || expected.payouts.length < 1 || expected.payouts.length > 3) throw Error('Invalid expected payouts');
  const kinds = new Set<string>();
  for (const p of expected.payouts) {
    address(p.recipient); coins(p.amount, true);
    if (!['seller', 'royalty', 'fee'].includes(p.kind) || kinds.has(p.kind)) throw Error('Invalid payout roles');
    kinds.add(p.kind);
  }
  if (!kinds.has('seller')) throw Error('Missing seller proceeds');
  const receipts = new Map<string, TraceReceipt>(), inputs = new Set<string>();
  const messages = new Map<string, { owner: TraceReceipt; message: TraceMessage }>();
  for (const receipt of trace.receipts) {
    hash(receipt.hash); hash(receipt.inputMessageHash); address(receipt.account); coins(receipt.creditedValue);
    if (receipt.credit !== undefined) {
      if (!receipt.credit || !['confirmed', 'uncertain'].includes(receipt.credit.status)) throw Error('Invalid credit evidence');
      coins(receipt.credit.amount);
    }
    if (receipt.parent !== null) hash(receipt.parent);
    if (typeof receipt.success !== 'boolean' || receipts.has(receipt.hash) || inputs.has(receipt.inputMessageHash)) throw Error('Duplicate or invalid receipt');
    receipts.set(receipt.hash, receipt); inputs.add(receipt.inputMessageHash);
    if (!Array.isArray(receipt.messages) || receipt.messages.length > 16) throw Error('Message budget exceeded');
    for (const m of receipt.messages) {
      hash(m.hash); address(m.recipient); coins(m.value); query(m.queryId);
      if (!['seller','royalty','fee','other'].includes(m.kind) || messages.has(m.hash)) throw Error('Duplicate or invalid message');
      messages.set(m.hash, { owner: receipt, message: m });
    }
    if (receipt.transfer !== null) { address(receipt.transfer.previousOwner); address(receipt.transfer.newOwner); query(receipt.transfer.queryId); }
  }
  if (!trace.canonical) return 'pending';
  if (receipts.size === 0) return trace.traceComplete ? 'needs-recovery' : 'pending';
  const roots = trace.receipts.filter(r => r.parent === null);
  const origins = roots.filter(r => r.inputMessageHash === expected.rootMessageHash);
  if (origins.length !== 1) throw Error('Unrelated trace root');
  const root = origins[0]!;
  const parents = new Map<string, string | null>();
  // A resumed payment is a new message tree. Only a contiguous, pinned market account
  // history in PAY may join it to the original delivery. No balance/owner heuristics.
  for (const r of trace.receipts) {
    parents.set(r.hash, r.parent);
    if (r.lineage) {
      const l = r.lineage;
      [l.previousTransactionHash, l.codeHash, l.beforeDataHash, l.afterDataHash].forEach(hash);
      query(l.beforeQuery); query(l.afterQuery);
      if (![l.beforePhase,l.afterPhase].every(v => Number.isInteger(v) && v >= 0 && v <= 11)) throw Error('Invalid account phase');
    }
    if (r.parent !== null || r === root) continue;
    const l = r.lineage, previous = l && receipts.get(l.previousTransactionHash), p = previous?.lineage;
    if (!expected.contractCodeHash || !l || !previous || !p || r.account !== expected.contract
      || previous.account !== expected.contract || l.codeHash !== hash(expected.contractCodeHash)
      || p.codeHash !== l.codeHash || l.beforeDataHash !== p.afterDataHash
      || p.afterPhase !== 5 || l.beforePhase !== 5 || ![5,9].includes(l.afterPhase)
      || l.beforeQuery !== expected.queryId || l.afterQuery !== expected.queryId || p.afterQuery !== expected.queryId) {
      throw Error('Unverified resumed payment lineage');
    }
    parents.set(r.hash, previous.hash);
  }
  for (const receipt of trace.receipts) {
    const seen = new Set<string>(); let current = receipt;
    while (parents.get(current.hash) !== null) {
      if (seen.has(current.hash)) throw Error('Cyclic trace'); seen.add(current.hash);
      const parent = receipts.get(parents.get(current.hash)!), edge = messages.get(current.inputMessageHash);
      if (!parent || (current.parent !== null && (!edge || edge.owner !== parent || edge.message.recipient !== current.account
        || edge.message.value !== current.creditedValue))) throw Error('Unrelated or altered trace edge');
      current = parent;
    }
    if (current !== root) throw Error('Disconnected trace');
  }
  if (!trace.traceComplete) return 'pending';
  const delivered = trace.receipts.filter(r => r.success && r.account === expected.nft
    && r.transfer?.previousOwner === expected.contract && r.transfer.newOwner === expected.buyer
    && r.transfer.queryId === expected.queryId);
  const payoutMessages = [...messages.values()].filter(e => e.owner.account === expected.contract && e.message.kind !== 'other');
  if (delivered.length !== 1 || payoutMessages.length !== expected.payouts.length) return 'needs-recovery';
  for (const payout of expected.payouts) {
    const matching = payoutMessages.filter(e => e.owner.success && e.message.kind === payout.kind
      && e.message.queryId === expected.queryId && e.message.recipient === payout.recipient && e.message.value === payout.amount);
    if (matching.length !== 1) return 'needs-recovery';
    // Value must actually arrive in a causal child receipt. Balance changes from other trades do not count.
    // A payout must descend from delivery, including the NFT acknowledgement path.
    let cursor = matching[0]!.owner; let followsDelivery = false;
    while (parents.get(cursor.hash) !== null) { cursor = receipts.get(parents.get(cursor.hash)!)!; if (cursor === delivered[0]) followsDelivery = true; }
    if (!followsDelivery) return 'needs-recovery';
  }
  return expected.payouts.every(payout => {
    const emission = payoutMessages.find(entry => entry.message.kind === payout.kind)!;
    return trace.receipts.some(receipt => receipt.parent === emission.owner.hash
      && receipt.inputMessageHash === emission.message.hash && receipt.account === payout.recipient
      && receipt.success && receipt.credit?.status === 'confirmed' && receipt.credit.amount === payout.amount);
  }) ? 'settled' : 'pending';
}
