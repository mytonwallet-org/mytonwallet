import type { GlobalState } from '../types';

export function selectIsEnclaveSessionValid(global: GlobalState) {
  return (global.enclaveSession?.validUntil ?? 0) > Date.now();
}

export function selectEnclaveToken(global: GlobalState) {
  return global.enclaveSession?.token;
}

/**
 * Extra Enclave token usages to request on top of the one the operation itself needs. The multichain
 * upgrade spends one usage per account. A flow that needs its own usages keeps its own field and adds
 * a term here - there is no shared counter in the global state, otherwise flows would erase each
 * other's requests.
 */
export function selectAuthUsageCountRequest(global: GlobalState) {
  return global.multichainUpgradeCount;
}
