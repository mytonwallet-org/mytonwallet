import type { ApiAddressInfo, ApiBalanceBySlug, ApiNetwork, UTXOChain } from '../../types';
import type { UtxoAddressInfo, UtxoTransaction } from './types';
import { ApiCommonError } from '../../types';

import { fetchJson } from '../../../util/fetch';
import { getNativeToken } from '../../../util/tokens';
import { getKnownAddressInfo } from '../../common/addresses';
import { updateTokens } from '../../common/tokens';
import { isValidAddress, normalizeAddress, toUtxoApiAddress } from './address';
import { UTXO_RPC_URLS } from './constants';
import { fetchSpendableUtxos, getSpendableBalance } from './utxos';

export async function getWalletBalance(chain: UTXOChain, network: ApiNetwork, address: string) {
  // Same spendable UTXO set as transfer construction.
  return getSpendableBalance(await fetchSpendableUtxos(chain, network, address));
}

export async function fetchAddressInfo(chain: UTXOChain, network: ApiNetwork, address: string) {
  const endpoint = UTXO_RPC_URLS[network](chain);
  const apiAddress = toUtxoApiAddress(chain, network, address);

  return fetchJson<UtxoAddressInfo>(`${endpoint}/api/v2/address/${apiAddress}`);
}

export async function fetchAccountAssets(
  chain: UTXOChain,
  network: ApiNetwork,
  address: string,
  sendUpdateTokens: NoneToVoidFunction,
): Promise<ApiBalanceBySlug> {
  const nativeToken = getNativeToken(chain);

  await updateTokens(
    [{
      priceUsd: undefined,
      percentChange24h: undefined,
      ...nativeToken,
    }], sendUpdateTokens, [], true);

  const balance = await getWalletBalance(chain, network, address);

  return {
    [nativeToken.slug]: balance,
  };
}

export function getAddressInfo(
  chain: UTXOChain,
  network: ApiNetwork,
  addressOrDomain: string,
): ApiAddressInfo | { error: ApiCommonError } {
  if (!isValidAddress(chain, network, addressOrDomain)) {
    return { error: ApiCommonError.InvalidAddress };
  }

  return {
    resolvedAddress: normalizeAddress(chain, addressOrDomain, network),
    addressName: getKnownAddressInfo(addressOrDomain)?.name,
  };
}

export async function getWalletLastTransaction(chain: UTXOChain, network: ApiNetwork, address: string) {
  try {
    const apiAddress = toUtxoApiAddress(chain, network, address);
    const info = await fetchJson<UtxoAddressInfo>(
      `${UTXO_RPC_URLS[network](chain)}/api/v2/address/${apiAddress}`,
      { page: 1, pageSize: 1 },
    );

    const lastTx = info.txids[0];

    if (!lastTx) {
      return undefined;
    }

    const tx = await fetchJson<UtxoTransaction>(
      `${UTXO_RPC_URLS[network](chain)}/api/v2/tx/${lastTx}`,
    );

    return { blockTime: tx.blockTime };
  } catch {
    return undefined;
  }
}
