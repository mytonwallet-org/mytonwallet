import { parseAccountId } from '../../util/account';
import * as ton from '../chains/ton';

export { getTokenBySlug, buildTokenSlug } from '../common/tokens';

export function fetchToken(accountId: string, address: string) {
  const { network } = parseAccountId(accountId);
  return ton.fetchToken(network, address);
}
