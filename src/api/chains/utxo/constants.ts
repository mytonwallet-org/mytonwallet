import type { ApiNetwork, UTXOChain } from '../../types';

import {
  UTXO_MAINNET_RPC_URL,
  UTXO_TESTNET_RPC_URL,
} from '../../../config';

export const UTXO_ADDRESS_TYPES = ['legacy', 'wrapped-segwit', 'segwit', 'taproot'] as const;

export type UtxoAddressType = typeof UTXO_ADDRESS_TYPES[number];

export const UTXO_COIN_TYPES: Record<UTXOChain, number> = {
  bitcoin: 0,
  litecoin: 2,
  dogecoin: 3,
  bitcoincash: 145,
};

export const UTXO_SUPPORTED_ADDRESS_TYPES: Record<UTXOChain, readonly UtxoAddressType[]> = {
  bitcoin: ['legacy', 'wrapped-segwit', 'segwit', 'taproot'],
  litecoin: ['legacy', 'wrapped-segwit', 'segwit', 'taproot'],
  bitcoincash: ['legacy'],
  dogecoin: ['legacy'],
};

export type UtxoDerivationPaths = Record<UtxoAddressType, string>;

const UTXO_DERIVATION_PATH_TEMPLATES: Record<UtxoAddressType, string> = {
  legacy: `m/44'/{coinType}'/0'/0/{index}`,
  'wrapped-segwit': `m/49'/{coinType}'/0'/0/{index}`,
  segwit: `m/84'/{coinType}'/0'/0/{index}`,
  taproot: `m/86'/{coinType}'/0'/0/{index}`,
};

export function getUtxoDerivationPaths(chain: UTXOChain): Partial<UtxoDerivationPaths> {
  const coinType = UTXO_COIN_TYPES[chain];

  return Object.fromEntries(
    UTXO_SUPPORTED_ADDRESS_TYPES[chain].map((addressType) => [
      addressType,
      UTXO_DERIVATION_PATH_TEMPLATES[addressType].replace('{coinType}', String(coinType)),
    ]),
  ) as Partial<UtxoDerivationPaths>;
}

/** Paths scanned on import to match wallets with non-standard coin types (e.g. BCH with BTC coin type). */
export function getUtxoImportPathTemplates(chain: UTXOChain): Array<{ label: UtxoAddressType; pathTemplate: string }> {
  const paths = getUtxoDerivationPaths(chain);

  const entries = Object.entries(paths).map(([label, pathTemplate]) => ({
    label: label as UtxoAddressType,
    pathTemplate,
  }));

  if (chain === 'bitcoincash') {
    entries.push({
      label: 'legacy',
      pathTemplate: UTXO_DERIVATION_PATH_TEMPLATES.legacy.replace('{coinType}', '0'),
    });
  }

  return entries;
}

export function getDefaultUtxoAddressType(chain: UTXOChain): UtxoAddressType {
  if (chain === 'bitcoin' || chain === 'litecoin') {
    return 'taproot';
  }

  return 'legacy';
}

export function getDefaultUtxoDerivationPath(chain: UTXOChain): string {
  const paths = getUtxoDerivationPaths(chain);

  return paths[getDefaultUtxoAddressType(chain)]!;
}

export const UTXO_RPC_URLS: Record<ApiNetwork, (chain: UTXOChain) => string> = {
  mainnet: (chain: UTXOChain) => `${UTXO_MAINNET_RPC_URL}/${chain}/v2`,
  testnet: (chain: UTXOChain) => `${UTXO_TESTNET_RPC_URL}/${chain}/v2`,
};

/** Default fee rate in sat/vB when the node estimate is unavailable */
export const UTXO_DEFAULT_FEE_RATE_SAT_VB = 10n;

/** Conservative Dogecoin fallback (~0.01 DOGE/kB) when estimatefee is unavailable */
export const DOGECOIN_DEFAULT_FEE_RATE_SAT_VB = 1000n;

export const UTXO_COINBASE_MATURITY = 100;

/**
 * Fallback only for REST/direct UTXO activity parsing when no backend websocket update has supplied
 * the authoritative maxConfirmations for the transaction. Backend `utxoActivityUpdate` owns finality.
 */
export const UTXO_REST_ACTIVITY_MAX_CONFIRMATIONS_FALLBACK = 2;
