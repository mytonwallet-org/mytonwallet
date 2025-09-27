import type { ApiNetwork } from '../../../types';

import { TRX } from '../../../../config';
import { buildTokenSlug } from '../../../common/tokens';
import { NETWORK_CONFIG } from '../constants';

export function getTokenSlugs(network: ApiNetwork) {
  const { usdtAddress } = NETWORK_CONFIG[network];
  const usdtSlug = buildTokenSlug('tron', usdtAddress);
  return [TRX.slug, usdtSlug];
}
