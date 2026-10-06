import type { EVMChain } from '../../../types';
import type { ZerionFungibleInfo, ZerionTransaction } from '../types';

import { getChainConfig } from '../../../../util/chain';
import { buildTokenSlug } from '../../../common/tokens';
import { normalizeAddress } from '../address';

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
    || (chain === 'polygon' && implementation?.address === '0x0000000000000000000000000000000000001010') // polygon native token
    || (chain === 'arc' && implementation?.address === '0x3600000000000000000000000000000000000000') // arc native token
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

export function collectZerionTxTokenAddresses(
  tx: ZerionTransaction,
  zerionChain: string,
  addresses: Set<string>,
) {
  function addFungible(fungibleInfo: ZerionFungibleInfo | undefined) {
    if (!fungibleInfo) return;

    const implementation = getZerionFungibleImplementation(fungibleInfo, zerionChain);
    if (implementation?.address) {
      addresses.add(normalizeAddress(implementation.address));
    }
  }

  for (const transfer of tx.attributes.transfers) {
    if ('fungible_info' in transfer) {
      addFungible(transfer.fungible_info);
    }
  }

  for (const approval of tx.attributes.approvals) {
    addFungible(approval.fungible_info);
  }
}
