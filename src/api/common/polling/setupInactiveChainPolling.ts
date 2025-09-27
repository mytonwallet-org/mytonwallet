import type { ApiChain, ApiNetwork } from '../../types';

import { createTaskQueue } from '../../../util/schedulers';
import { inactiveWalletTiming } from './utils';
import { WalletPolling } from './walletPolling';

const concurrencyLimiters: Record<string, ReturnType<typeof createTaskQueue>> = {};

/**
 * Starts polling of the given inactive account in the given chain. Returns a function that stops the polling.
 */
export function setupInactiveChainPolling(
  chain: ApiChain,
  network: ApiNetwork,
  address: string,
  updateBalance: () => Promise<unknown>,
) {
  const concurrencyLimiter = getConcurrencyLimiter(chain, network);

  const walletPolling = new WalletPolling({
    chain,
    network,
    address,
    pollingOptions: inactiveWalletTiming,
    onUpdate: concurrencyLimiter.wrap(async () => {
      await updateBalance();
    }),
  });

  return () => {
    walletPolling.destroy();
  };
}

export function getConcurrencyLimiter(chain: ApiChain, network: ApiNetwork) {
  const key = `${chain} ${network}`;
  concurrencyLimiters[key] ||= createTaskQueue();
  return concurrencyLimiters[key];
}
