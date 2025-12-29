import type { ApiChain } from '../../api/types';

import { getChainConfig } from '../chain';

type NetWorthToken = { chain?: ApiChain };

export function isNetWorthChartAvailable(token?: NetWorthToken) {
  return token?.chain ? getChainConfig(token.chain).isNetWorthSupported : false;
}
