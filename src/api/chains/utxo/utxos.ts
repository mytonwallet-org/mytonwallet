import type { ApiNetwork, UTXOChain } from '../../types';
import type { UtxoListItem, UtxoListResponse } from './types';

import { fetchJson } from '../../../util/fetch';
import { toUtxoApiAddress } from './address';
import { UTXO_COINBASE_MATURITY, UTXO_RPC_URLS } from './constants';

export function getUtxoConfirmations(utxo: UtxoListItem) {
  return utxo.confirmations ?? (utxo.height && utxo.height > 0 ? 1 : 0);
}

export function isSpendableUtxo(utxo: UtxoListItem) {
  const confirmations = getUtxoConfirmations(utxo);

  if (confirmations < 1) {
    return false;
  }

  if (utxo.coinbase && confirmations < UTXO_COINBASE_MATURITY) {
    return false;
  }

  return true;
}

export function getSpendableUtxos(utxos: UtxoListItem[]) {
  return utxos.filter(isSpendableUtxo);
}

export function getSpendableBalance(utxos: UtxoListItem[]) {
  return utxos.reduce((sum, utxo) => sum + BigInt(utxo.value), 0n);
}

export async function fetchUtxoList(chain: UTXOChain, network: ApiNetwork, address: string) {
  const endpoint = UTXO_RPC_URLS[network](chain);
  const apiAddress = toUtxoApiAddress(chain, network, address);

  // Blockbook subtracts mempool spends only when unconfirmed outputs are included.
  // Local `isSpendableUtxo` still drops 0-conf; this query must not use `confirmed=true`.
  return fetchJson<UtxoListResponse>(`${endpoint}/api/v2/utxo/${apiAddress}`);
}

export async function fetchSpendableUtxos(chain: UTXOChain, network: ApiNetwork, address: string) {
  return getSpendableUtxos(await fetchUtxoList(chain, network, address));
}
