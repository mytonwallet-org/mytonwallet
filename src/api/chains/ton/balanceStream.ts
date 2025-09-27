import type { createTaskQueue } from '../../../util/schedulers';
import type { FallbackPollingOptions } from '../../common/polling/fallbackPollingScheduler';
import type { ApiBalanceBySlug, ApiNetwork } from '../../types';
import type { BalanceUpdateCallback, WalletWatcher } from './toncenter/socket';

import { TONCOIN } from '../../../config';
import { areDeepEqual } from '../../../util/areDeepEqual';
import { createCallbackManager } from '../../../util/callbacks';
import Deferred from '../../../util/Deferred';
import { pick } from '../../../util/iteratees';
import { throttle } from '../../../util/schedulers';
import withCacheAsync from '../../../util/withCacheAsync';
import { FallbackPollingScheduler } from '../../common/polling/fallbackPollingScheduler';
import { buildTokenSlug, getTokenByAddress, tokensPreload } from '../../common/tokens';
import { getToncenterSocket } from './toncenter/socket';
import { importToken, loadTokenBalances } from './tokens';
import { getWalletInfo } from './wallet';

export type OnBalancesUpdate = (balances: ApiBalanceBySlug) => void;
export type OnLoadingChange = (isLoading: boolean) => void;

type OnSocketBalancesUpdate = (balances: BalanceByTokenAddress) => void;
type BalanceByTokenAddress = Record<string, bigint>;

const TON_VIRTUAL_ADDRESS = '@TON'; // An arbitrary string for representing TON balance inside this file only
const SOCKET_THROTTLE_DELAY = 100;

/**
 * Watches the TON and token balances of the given TON wallet.
 * Uses the socket, and fallbacks to HTTP polling when the socket is unavailable.
 */
export class BalanceStream {
  #network: ApiNetwork;
  #address: string;
  #sendUpdateTokens: NoneToVoidFunction;
  #loadingConcurrencyLimiter?: ReturnType<typeof createTaskQueue>;

  /** Contains all the address balances. `undefined` until the all the balances are loaded. */
  #balances?: ApiBalanceBySlug;
  #balancesDeferred = new Deferred();

  #walletWatcher: WalletWatcher;
  #fallbackPollingScheduler: FallbackPollingScheduler;

  #updateListeners = createCallbackManager<OnBalancesUpdate>();
  #loadingListeners = createCallbackManager<OnLoadingChange>();

  #isDestroyed = false;

  constructor(
    network: ApiNetwork,
    address: string,
    sendUpdateTokens: NoneToVoidFunction,
    fallbackPollingOptions: FallbackPollingOptions,
    /** To prevent too many simultaneous HTTP requests for inactive accounts */
    loadingConcurrencyLimiter?: ReturnType<typeof createTaskQueue>,
  ) {
    this.#network = network;
    this.#address = address;
    this.#sendUpdateTokens = sendUpdateTokens;
    this.#loadingConcurrencyLimiter = loadingConcurrencyLimiter;

    this.#walletWatcher = getToncenterSocket(network).watchWallets(
      [address],
      {
        onConnect: this.#handleSocketConnect,
        onDisconnect: this.#handleSocketDisconnect,
        onBalanceUpdate: throttleSocketBalanceUpdates(this.#handleSocketBalanceUpdate),
      },
    );

    this.#fallbackPollingScheduler = new FallbackPollingScheduler(
      this.#poll,
      this.#walletWatcher.isConnected,
      fallbackPollingOptions,
    );
  }

  public async getBalances() {
    await this.#balancesDeferred.promise;
    if (!this.#balances) {
      throw new Error('Unexpected missing balances');
    }
    return this.#balances;
  }

  /**
   * Registers a callback firing then the balances change.
   * The callback calls are throttled.
   */
  public onUpdate(callback: OnBalancesUpdate) {
    return this.#updateListeners.addCallback(callback);
  }

  /**
   * Registers a callback firing when the regular polling starts of finishes.
   * Guaranteed to be called with `isLoading=false` after calling the `onUpdate` callbacks.
   */
  public onLoadingChange(callback: OnLoadingChange) {
    return this.#loadingListeners.addCallback(callback);
  }

  public destroy() {
    this.#isDestroyed = true;
    this.#walletWatcher.destroy();
    this.#fallbackPollingScheduler.destroy();
  }

  #handleSocketConnect = () => {
    this.#fallbackPollingScheduler.onSocketConnect();
  };

  #handleSocketDisconnect = () => {
    this.#fallbackPollingScheduler.onSocketDisconnect();
  };

  #handleSocketBalanceUpdate: OnSocketBalancesUpdate = async (newBalances) => {
    if (this.#isDestroyed) return;
    this.#fallbackPollingScheduler.onSocketMessage();

    // `this.#balances` must contain all the balances, so we ignore partial updates until we load all the balances
    if (!this.#balances) return;

    const tokenAddresses = await splitKnownAndUnknownTokens(newBalances);
    this.#setBalancesPartially(pick(newBalances, tokenAddresses.known));

    await importUnknownTokens(this.#network, tokenAddresses.unknown, this.#sendUpdateTokens);
    if (this.#isDestroyed) return;
    this.#setBalancesPartially(pick(newBalances, tokenAddresses.unknown));
  };

  /** Fetches all balances when the socket is not connected or has just connected */
  #poll = async () => {
    try {
      this.#loadingListeners.runCallbacks(true);

      const throttledFetchBalances = this.#loadingConcurrencyLimiter?.wrap(fetchBalances) ?? fetchBalances;
      const newBalances = await throttledFetchBalances(this.#network, this.#address, this.#sendUpdateTokens);
      if (this.#isDestroyed) return;

      this.#setAllBalances(newBalances);
      this.#balancesDeferred.resolve();
    } finally {
      if (!this.#isDestroyed) {
        this.#loadingListeners.runCallbacks(false);
      }
    }
  };

  #setAllBalances(newBalances: ApiBalanceBySlug) {
    if (!areDeepEqual(this.#balances, newBalances)) {
      this.#balances = newBalances;
      this.#updateListeners.runCallbacks(this.#balances);
    }
  }

  #setBalancesPartially(newBalances: BalanceByTokenAddress) {
    const newBySlug = balanceByTokeyAddressToBySlug(newBalances);
    const hasChanged = !this.#balances || !areDeepEqual(pick(this.#balances, Object.keys(newBySlug)), newBySlug);

    if (hasChanged) {
      this.#balances = {
        ...this.#balances,
        ...newBySlug,
      };
      this.#updateListeners.runCallbacks(this.#balances);
    }
  }
}

/**
 * When an incoming token transfer arrives, the socket triggers both TON and token balance updates in a quick succession.
 * To avoid excessive UI updates, we throttle the balance updates.
 */
function throttleSocketBalanceUpdates(onUpdate: OnSocketBalancesUpdate): BalanceUpdateCallback {
  let pendingUpdates: BalanceByTokenAddress = {};

  const notifyThrottled = throttle(() => {
    const updates = pendingUpdates;
    pendingUpdates = {};
    onUpdate(updates);
  }, SOCKET_THROTTLE_DELAY, false);

  return ({ tokenAddress, balance }) => {
    pendingUpdates[tokenAddress ?? TON_VIRTUAL_ADDRESS] = balance;
    notifyThrottled();
  };
}

async function splitKnownAndUnknownTokens(balances: BalanceByTokenAddress) {
  await tokensPreload.promise;

  const known: string[] = [];
  const unknown: string[] = [];

  for (const tokenAddress of Object.keys(balances)) {
    if (tokenAddress === TON_VIRTUAL_ADDRESS || getTokenByAddress(tokenAddress)) {
      known.push(tokenAddress);
    } else {
      unknown.push(tokenAddress);
    }
  }

  return { known, unknown };
}

async function fetchBalances(network: ApiNetwork, address: string, sendUpdateTokens: NoneToVoidFunction) {
  const [{ balance: tonBalance }, tokenBalances] = await Promise.all([
    getWalletInfo(network, address),
    loadTokenBalances(network, address, sendUpdateTokens),
  ]);

  return {
    [TONCOIN.slug]: tonBalance,
    ...tokenBalances,
  };
}

function importUnknownTokens(network: ApiNetwork, tokenAddresses: string[], sendUpdateTokens: NoneToVoidFunction) {
  return Promise.all(tokenAddresses.map(
    (tokenAddress) => importUnknownToken(network, tokenAddress, sendUpdateTokens),
  ));
}

// Using `withCacheAsync` mainly to prevent concurrent execution
const importUnknownToken = withCacheAsync(importToken);

function balanceByTokeyAddressToBySlug(byAddress: BalanceByTokenAddress) {
  const bySlug: ApiBalanceBySlug = {};

  for (const [tokenAddress, balance] of Object.entries(byAddress)) {
    const slug = tokenAddress === TON_VIRTUAL_ADDRESS ? TONCOIN.slug : buildTokenSlug('ton', tokenAddress);
    bySlug[slug] = balance;
  }

  return bySlug;
}
