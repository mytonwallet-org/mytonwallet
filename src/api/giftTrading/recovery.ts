import { address, timestamp } from './protocol.js';

export type RecoveryState = Readonly<{ phase: number; query: string; seller: string; initiator: string;
  codeHash: string; observedAt: number; stateHash: string }>;
export type RecoveryDecision = Readonly<{ action: 'reconcile' | 'drive' | 'retry-return' | 'none';
  query: string | null; reason: string }>;
/** Does not build or send anything. Caller must independently authenticate and recheck the snapshot. */
export function recoveryDecision(state: RecoveryState, account: string, allowedCode: readonly string[], now: number): RecoveryDecision {
  address(account); address(state.seller); address(state.initiator); timestamp(now); timestamp(state.observedAt);
  if (!/^[a-f0-9]{64}$/.test(state.codeHash) || !allowedCode.includes(state.codeHash)
    || !/^[a-f0-9]{64}$/.test(state.stateHash) || now < state.observedAt || now - state.observedAt > 15
    || !Number.isInteger(state.phase) || state.phase < 0 || state.phase > 11
    || !/^(0|[1-9][0-9]{0,19})$/.test(state.query) || BigInt(state.query) >= 2n ** 64n) throw Error('Unverified recovery state');
  if ([4,8].includes(state.phase)) return Object.freeze({ action: 'reconcile', query: null, reason: 'Delivery is uncertain; neither timeout refund nor retransmission is safe' });
  if ([3,5,6,7].includes(state.phase)) return Object.freeze({ action: 'drive', query: state.query, reason: 'Resume the stored operation; fresh gas review required' });
  if (state.phase === 11) {
    if (![state.seller,state.initiator].includes(account) || BigInt(state.query) === 2n ** 64n - 1n) throw Error('Return recovery is unavailable to this account');
    return Object.freeze({ action: 'retry-return', query: (BigInt(state.query) + 1n).toString(), reason: 'Confirmed failed return only; fresh state and gas review required' });
  }
  return Object.freeze({ action: 'none', query: null, reason: 'No pending recoverable operation' });
}
