import type { UnifiedSignDataPayload } from '../../api/dappProtocols/types';

export type SignDataWarningKind = 'genericTrust';

export function getSignDataWarningKinds(
  payload: UnifiedSignDataPayload | undefined,
): SignDataWarningKind[] {
  if (!payload) return [];

  // All custom-data signatures use the same single trust warning, regardless of protocol or preview quality.
  return ['genericTrust'];
}
