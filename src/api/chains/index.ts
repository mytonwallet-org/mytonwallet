import type { ApiChain } from '../types';
import type { ChainSdk } from '../types/chains';

import EVMSdk from './evm';
import solanaSdk from './solana';
import tonSdk from './ton';
import tronSdk from './tron';
import UTXOSdk from './utxo';

/**
 * This dictionary contains only universal chain methods, i.e. the methods having the same interface in all the chains.
 *
 * If you need chain-specific methods, import them directly from the corresponding chain module. This is deprecated —
 * all chain methods should be universal. If a chain doesn't support some functionality yet, the corresponding methods
 * should simply throw an error.
 *
 * Every chain is registered behind a `process.env.NO_*` build flag. For a disabled chain, `plugins/disabledImports.ts`
 * replaces the `./<chain>` import below with a stub, so neither the SDK nor its heavy npm dependencies reach the
 * bundle. Keep importing each SDK as `./<chain>`: the build fails otherwise when its flag is on. The exported type
 * is intentionally the full `Record<ApiChain, ...>` (not `Partial`): a disabled chain is simply absent at runtime, but
 * it is never indexed because polling iterates `Object.keys(chains)` and the UI never initiates actions for a chain the
 * account doesn't have.
 */
export const chains = {} as { [K in ApiChain]: ChainSdk<K> };

if (process.env.NO_TON !== '1') {
  chains.ton = tonSdk;
}

if (process.env.NO_TRON !== '1') {
  chains.tron = tronSdk;
}

if (process.env.NO_SOLANA !== '1') {
  chains.solana = solanaSdk;
}

if (process.env.NO_UTXO !== '1') {
  Object.assign(chains, {
    bitcoin: new UTXOSdk('bitcoin'),
    litecoin: new UTXOSdk('litecoin'),
    bitcoincash: new UTXOSdk('bitcoincash'),
    dogecoin: new UTXOSdk('dogecoin'),
    zcash: new UTXOSdk('zcash'),
  });
}

if (process.env.NO_EVM !== '1') {
  Object.assign(chains, {
    ethereum: new EVMSdk('ethereum'),
    base: new EVMSdk('base'),
    bnb: new EVMSdk('bnb'),
    polygon: new EVMSdk('polygon'),
    arbitrum: new EVMSdk('arbitrum'),
    optimism: new EVMSdk('optimism'),
    monad: new EVMSdk('monad'),
    avalanche: new EVMSdk('avalanche'),
    hyperliquid: new EVMSdk('hyperliquid'),
    robinhood: new EVMSdk('robinhood'),
    arc: new EVMSdk('arc'),
  });
}

export default chains;
