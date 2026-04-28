import type { EVMChain } from '../../../types';
import type { ZerionFungibleInfo } from '../types';

import { getChainConfig } from '../../../../util/chain';
import { buildTokenSlug } from '../../../common/tokens';

export function getZerionFungibleImplementation(
  fungibleInfo: Pick<ZerionFungibleInfo, 'implementations'>,
  zerionChain: string,
) {
  return fungibleInfo.implementations.find((implementation) => implementation.chain_id === zerionChain);
}

export function isZerionNativeFungible(
  chain: EVMChain,
  zerionChain: string,
  fungibleInfo: Pick<ZerionFungibleInfo, 'implementations'>,
  fungibleId?: string,
) {
  const nativeToken = getChainConfig(chain).nativeToken;
  const implementation = getZerionFungibleImplementation(fungibleInfo, zerionChain);

  return (!!implementation && !implementation.address)
    || fungibleId === nativeToken.slug
    || (nativeToken.symbol === 'ETH' && fungibleId === 'eth');
}

export function getZerionFungibleTokenSlug(
  chain: EVMChain,
  zerionChain: string,
  fungibleInfo: Pick<ZerionFungibleInfo, 'id' | 'implementations'>,
) {
  if (isZerionNativeFungible(chain, zerionChain, fungibleInfo, fungibleInfo.id)) {
    return getChainConfig(chain).nativeToken.slug;
  }

  const implementation = getZerionFungibleImplementation(fungibleInfo, zerionChain);

  return implementation?.address ? buildTokenSlug(chain, implementation.address) : undefined;
}
