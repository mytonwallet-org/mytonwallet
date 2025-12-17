import type { ApiChain, OnApiUpdate } from '../types';

import { parseAccountId } from '../../util/account';
import chains from '../chains';
import { sendUpdateTokens } from '../common/tokens';

export { buildTokenSlug } from '../common/tokens';

export function fetchToken(accountId: string, chain: ApiChain, tokenAddress: string) {
  const { network } = parseAccountId(accountId);
  return chains[chain].fetchToken(network, tokenAddress);
}

let onUpdate: OnApiUpdate | undefined;

export function initTokens(_onUpdate: OnApiUpdate) {
  onUpdate = _onUpdate;
}

export async function importToken(accountId: string, chain: ApiChain, tokenAddress: string) {
  const { network } = parseAccountId(accountId);
  await chains[chain].importToken(network, tokenAddress, () => onUpdate && sendUpdateTokens(onUpdate));
}
