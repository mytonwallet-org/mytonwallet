import { TronWeb } from 'tronweb';

import type { ApiNetwork } from '../../../types';

import withCache from '../../../../util/withCache';
import withCacheAsync from '../../../../util/withCacheAsync';
import { NETWORK_CONFIG } from '../constants';

export const getTronClient = withCache((network: ApiNetwork) => {
  return new TronWeb({
    fullHost: NETWORK_CONFIG[network].apiUrl,
  });
});

export const getChainParameters = withCacheAsync(async (network: ApiNetwork) => {
  const chainParameters = await getTronClient(network).trx.getChainParameters();
  const energyUnitFee = chainParameters.find((param) => param.key === 'getEnergyFee')!.value;
  const bandwidthUnitFee = chainParameters.find((param) => param.key === 'getTransactionFee')!.value;
  return { energyUnitFee, bandwidthUnitFee };
});
