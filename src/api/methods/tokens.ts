import type { OnApiUpdate } from '../types';

import { parseAccountId } from '../../util/account';
import * as ton from '../chains/ton';
import { sendUpdateTokens } from '../common/tokens';

export { getTokenBySlug, buildTokenSlug } from '../common/tokens';

export function fetchToken(accountId: string, address: string) {
  const { network } = parseAccountId(accountId);
  return ton.fetchToken(network, address);
}

let onUpdate: OnApiUpdate | undefined;

export function initTokens(_onUpdate: OnApiUpdate) {
  onUpdate = _onUpdate;
}

export async function importToken(accountId: string, address: string) {
  const { network } = parseAccountId(accountId);
  await ton.importToken(network, address, () => onUpdate && sendUpdateTokens(onUpdate));
}
