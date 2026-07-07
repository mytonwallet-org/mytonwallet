import type { ApiChain } from '../types';
import type { ChainSdk } from '../types/chains';

/**
 * This dictionary contains only universal chain methods, i.e. the methods having the same interface in all the chains.
 *
 * If you need chain-specific methods, import them directly from the corresponding chain module. This is deprecated —
 * all chain methods should be universal. If a chain doesn't support some functionality yet, the corresponding methods
 * should simply throw an error.
 *
 * Every chain is registered behind a `process.env.NO_*` build flag, letting Webpack dead-code elimination drop unused
 * chain modules and their heavy npm dependencies. The exported type is intentionally the full `Record<ApiChain, ...>`
 * (not `Partial`): a disabled chain is simply absent at runtime, but it is never indexed because polling iterates
 * `Object.keys(chains)` and the UI never initiates actions for a chain the account doesn't have.
 */
/* eslint-disable @typescript-eslint/no-require-imports */
export const chains = {} as { [K in ApiChain]: ChainSdk<K> };

if (process.env.NO_TON !== '1') {
  chains.ton = require('./ton').default;
}

if (process.env.NO_TRON !== '1') {
  chains.tron = require('./tron').default;
}

if (process.env.NO_SOLANA !== '1') {
  chains.solana = require('./solana').default;
}

if (process.env.NO_EVM !== '1') {
  const EVMSdk = require('./evm').default;
  Object.assign(chains, {
    ethereum: new EVMSdk('ethereum'),
    base: new EVMSdk('base'),
    bnb: new EVMSdk('bnb'),
    polygon: new EVMSdk('polygon'),
    arbitrum: new EVMSdk('arbitrum'),
    monad: new EVMSdk('monad'),
    avalanche: new EVMSdk('avalanche'),
    hyperliquid: new EVMSdk('hyperliquid'),
  });
}
/* eslint-enable @typescript-eslint/no-require-imports */

export default chains;
