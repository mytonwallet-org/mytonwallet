import type { createTaskQueue } from '../../../util/schedulers';
import type { FallbackPollingOptions } from '../../common/polling/fallbackPollingScheduler';
import type { ApiBalanceBySlug, ApiChain, ApiNetwork } from '../../types';
import type { AbstractWebsocketClient, BalanceUpdate, WalletWatcher } from './abstractWsClient';

import { areDeepEqual } from '../../../util/areDeepEqual';
import { createCallbackManager } from '../../../util/callbacks';
import { getChainConfig, getSupportedChains } from '../../../util/chain';
import Deferred from '../../../util/Deferred';
import { pick } from '../../../util/iteratees';
import { logDebug } from '../../../util/logs';
import { throttle } from '../../../util/schedulers';
import { getChainBySlug } from '../../../util/tokens';
import { FallbackPollingScheduler } from '../../common/polling/fallbackPollingScheduler';
import { buildTokenSlug, getTokenByAddress, tokensPreload } from '../../common/tokens';

/** `poll` — HTTP / fallback sync (including first load after connect); `socket` — live wallet subscription. */
export type BalanceStreamUpdateSource = 'poll' | 'socket';

export type OnBalancesUpdate = (balances: ApiBalanceBySlug, updateSource: BalanceStreamUpdateSource) => void;
export type OnLoadingChange = (isLoading: boolean) => void;

type OnSocketBalancesUpdate = (balances: BalanceByTokenAddress) => void;
type BalanceByTokenAddress = Record<string, bigint>;

export type BalanceUpdateCallback = (update: BalanceUpdate) => void;

// An arbitrary string for representing native balance for slugs inside this file only
const VIRTUAL_ADDRESS = '@VIRTUAL';

const SOCKET_THROTTLE_DELAY = 100;

const crosschainAssetsByChain = new Map<ApiChain, ApiBalanceBySlug>();

type BalanceStreamOptions = {
  chain: ApiChain;
  wsClient: AbstractWebsocketClient<any, any, any, any, any>;
  network: ApiNetwork;
  address: string;
  sendUpdateTokens: NoneToVoidFunction;
  fallbackPollingOptions: FallbackPollingOptions;
  fetchBalancesCb: (
    network: ApiNetwork,
    address: string,
    sendUpdateTokens: NoneToVoidFunction,
  ) => Promise<ApiBalanceBySlug>;
  fetchCrosschainBalancesCb?: (
    network: ApiNetwork,
    address: string,
    sendUpdateTokens: NoneToVoidFunction,
  ) => Promise<ApiBalanceBySlug>;
  importUnknownTokens?: (
    network: ApiNetwork,
    tokenAddresses: string[],
    sendUpdateTokens: NoneToVoidFunction,
  ) => Promise<void>;
  loadingConcurrencyLimiter?: ReturnType<typeof createTaskQueue>;
  ensureIsPollingNeeded?: () => Promise<boolean>;
};

/**
 * Watches the native/custom token balances of the given wallet.
 * Uses the socket, and fallbacks to HTTP polling when the socket is unavailable.
 */
export class BalanceStream {
  #chain: ApiChain;
  #network: ApiNetwork;
  #address: string;
  #sendUpdateTokens: NoneToVoidFunction;
  #loadingConcurrencyLimiter?: ReturnType<typeof createTaskQueue>;

  /** Contains all the address balances. `undefined` until the all the balances are loaded. */
  #balances?: ApiBalanceBySlug;
  #balancesDeferred = new Deferred();

  /**
   * A client-local monotonic clock used to order balance writes from the two sources that update
   * `#balances`: HTTP polls (full snapshots) and socket deltas (per-token pushes). A poll stamps its
   * version when it starts (a lower bound on the snapshot's freshness), a socket delta stamps when it
   * applies (always the newest data at that moment). The clock has no relation to wall time.
   */
  #clock = 0;

  /** Per-slug `#clock` version of the value currently stored in `#balances` for that slug. */
  #balanceVersionBySlug = new Map<string, number>();

  #walletWatcher: WalletWatcher;
  #fallbackPollingOptions: FallbackPollingOptions;
  #fallbackPollingScheduler?: FallbackPollingScheduler;

  #updateListeners = createCallbackManager<OnBalancesUpdate>();
  #loadingListeners = createCallbackManager<OnLoadingChange>();

  #fetchBalancesCb: (
    network: ApiNetwork,
    address: string,
    sendUpdateTokens: NoneToVoidFunction
  ) => Promise<ApiBalanceBySlug>;

  #fetchCrosschainBalancesCb?: (
    network: ApiNetwork,
    address: string,
    sendUpdateTokens: NoneToVoidFunction,
  ) => Promise<ApiBalanceBySlug>;

  #importUnknownTokens?: ((
    network: ApiNetwork,
    tokenAddresses: string[],
    sendUpdateTokens: NoneToVoidFunction
  ) => Promise<void>);

  #isDestroyed = false;

  #ensureIsPollingNeeded?: () => Promise<boolean>;
  #walletStatus: 'active' | 'inactive' | undefined = undefined;

  constructor({
    chain,
    wsClient,
    network,
    address,
    sendUpdateTokens,
    fallbackPollingOptions,
    fetchBalancesCb,
    fetchCrosschainBalancesCb,
    importUnknownTokens,
    loadingConcurrencyLimiter,
    ensureIsPollingNeeded,
  }: BalanceStreamOptions) {
    this.#chain = chain;
    this.#network = network;
    this.#address = address;
    this.#sendUpdateTokens = sendUpdateTokens;
    this.#loadingConcurrencyLimiter = loadingConcurrencyLimiter;
    this.#fetchBalancesCb = fetchBalancesCb;
    this.#fetchCrosschainBalancesCb = fetchCrosschainBalancesCb;
    this.#importUnknownTokens = importUnknownTokens;
    this.#ensureIsPollingNeeded = ensureIsPollingNeeded;
    this.#fallbackPollingOptions = fallbackPollingOptions;
    this.#walletWatcher = wsClient.watchWallets(
      [{ address, chain }],
      {
        onConnect: this.#handleSocketConnect,
        onDisconnect: this.#handleSocketDisconnect,
        onBalanceUpdate: throttleSocketBalanceUpdates(this.#handleSocketBalanceUpdate),
        onTraceInvalidated: this.#handleTraceInvalidated,
      },
    );

    if (!ensureIsPollingNeeded) {
      this.#walletStatus = 'active';
    }
  }

  public start() {
    if (this.#isDestroyed || this.#fallbackPollingScheduler) return;

    this.#fallbackPollingScheduler = new FallbackPollingScheduler(
      this.#poll,
      this.#walletWatcher.isConnected,
      this.#fallbackPollingOptions,
    );
  }

  public async getBalances() {
    await this.#balancesDeferred.promise;

    if (!this.#balances) {
      throw new Error('Unexpected missing balances');
    }

    const config = getChainConfig(this.#chain);
    let chainBalances = this.#balances;

    if (config.chainStandard && config.chainStandard !== this.#chain) {
      chainBalances = crosschainAssetsByChain.get(this.#chain) || {};
    }

    return chainBalances;
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
    this.#fallbackPollingScheduler?.destroy();
  }

  public markWalletActiveAndForcePoll() {
    if (this.#isDestroyed) return;

    this.#walletStatus = 'active';
    this.#fallbackPollingScheduler?.forceImmediatePoll();
  }

  #handleSocketConnect = () => {
    this.#fallbackPollingScheduler?.onSocketConnect();
  };

  #handleSocketDisconnect = () => {
    this.#fallbackPollingScheduler?.onSocketDisconnect();
  };

  #isWalletActive() {
    return this.#walletStatus === 'active';
  }

  /**
   * Called when a trace is invalidated. Balance updates received from `confirmed` finality level
   * may be stale, so we need to re-fetch actual balances from the network.
   */
  #handleTraceInvalidated = () => {
    logDebug('toncenter: trace invalidated, forcing balance re-poll', { address: this.#address });
    this.#fallbackPollingScheduler?.forceImmediatePoll();
  };

  #handleSocketBalanceUpdate: OnSocketBalancesUpdate = async (newBalances) => {
    if (this.#isDestroyed) return;
    if (!this.#fallbackPollingScheduler) return;

    this.#fallbackPollingScheduler.onSocketMessage();

    const wasInactive = this.#walletStatus === 'inactive';

    if (this.#walletStatus !== 'active') {
      this.#walletStatus = 'active';
      this.#fallbackPollingScheduler.forceImmediatePoll();
    }

    const config = getChainConfig(this.#chain);

    let chainBalances = this.#balances;

    if (config.chainStandard && config.chainStandard !== this.#chain) {
      chainBalances = crosschainAssetsByChain.get(this.#chain);
    }

    // Normally `this.#balances` must contain all balances before applying partial socket deltas.
    // For a wallet just activated by the socket, the delta is the only fresh source until HTTP APIs catch up.
    if (!chainBalances && !wasInactive) return;

    const tokenAddresses = await splitKnownAndUnknownTokens(newBalances);

    this.#setBalancesPartially(pick(newBalances, tokenAddresses.known));

    await this.#importUnknownTokens?.(this.#network, tokenAddresses.unknown, this.#sendUpdateTokens);

    if (this.#isDestroyed) return;

    this.#setBalancesPartially(pick(newBalances, tokenAddresses.unknown));
  };

  /** Fetches all balances when the socket is not connected or has just connected */
  #poll = async (isInitial?: boolean) => {
    try {
      this.#loadingListeners.runCallbacks(true);

      if (!this.#walletStatus) {
        const isEnsured = await this.#ensureIsPollingNeeded!();

        if (!isEnsured && !this.#isWalletActive()) {
          logDebug('balanceStream: wallet is inactive, skip polling', this.#chain, this.#address);
          this.#walletStatus = 'inactive';
          return;
        }
        this.#walletStatus = 'active';
      }

      if (this.#walletStatus === 'inactive') {
        return;
      }

      if (isInitial && this.#fetchCrosschainBalancesCb) {
        const config = getChainConfig(this.#chain);
        if (!config.chainStandard || config.chainStandard !== this.#chain) {
          return;
        }

        // Capture the freshness version before awaiting, so a socket delta that arrives during the
        // fetch is recognised as newer than this snapshot.
        const pollVersion = ++this.#clock;
        const crosschainBalances
        = await this.#fetchCrosschainBalancesCb?.(this.#network, this.#address, this.#sendUpdateTokens);

        if (crosschainBalances) {
          const knownChains = getSupportedChains();

          for (const [slug, balance] of Object.entries(crosschainBalances)) {
            const assetChain = getChainBySlug(slug);

            if (!knownChains.includes(assetChain)) {
              continue;
            }

            crosschainAssetsByChain.set(assetChain, {
              ...crosschainAssetsByChain.get(assetChain),
              [slug]: balance,
            });
          }

          this.#setAllBalances(crosschainBalances, pollVersion);
          this.#balancesDeferred.resolve();
        }

        return;
      }

      const throttledFetchBalances = this.#loadingConcurrencyLimiter?.wrap(this.#fetchBalancesCb)
        ?? this.#fetchBalancesCb;
      // Capture the freshness version before awaiting, so a socket delta that arrives during the
      // fetch is recognised as newer than this snapshot.
      const pollVersion = ++this.#clock;
      const newBalances = await throttledFetchBalances(this.#network, this.#address, this.#sendUpdateTokens);
      if (this.#isDestroyed) return;

      this.#setAllBalances(newBalances, pollVersion);
      this.#balancesDeferred.resolve();
    } finally {
      if (!this.#isDestroyed) {
        this.#loadingListeners.runCallbacks(false);
      }
    }
  };

  /**
   * Applies an HTTP poll snapshot as a version-gated merge rather than a blind full replace. A slug
   * is updated or removed only when the poll's `pollVersion` is at least as fresh as the version
   * already stored for that slug, so a slow poll that started before a socket delta cannot clobber
   * (or drop) the slug that delta refreshed. With no interleaving (every stored version is at most
   * `pollVersion`) this is equivalent to the previous full-replace behaviour.
   */
  #setAllBalances(newBalances: ApiBalanceBySlug, pollVersion: number) {
    // Fast path: nothing advanced the clock since this poll captured its version, so no socket delta
    // interleaved and the snapshot is a straight full replace. Clearing the version map keeps it
    // bounded; an empty map reads as "oldest", which is the safe default for the next poll/delta.
    if (this.#clock === pollVersion) {
      this.#balanceVersionBySlug.clear();
      if (!areDeepEqual(this.#balances, newBalances)) {
        this.#balances = newBalances;
        this.#updateListeners.runCallbacks(this.#balances, 'poll');
      }
      return;
    }

    // Slow path: a socket delta interleaved; merge per-slug by version.
    const merged: ApiBalanceBySlug = {};

    // Keep slugs that a newer source updated and that this snapshot does not refresh.
    for (const slug of Object.keys(this.#balances ?? {})) {
      if (!(slug in newBalances) && pollVersion < (this.#balanceVersionBySlug.get(slug) ?? -1)) {
        merged[slug] = this.#balances![slug];
      }
    }

    // Apply this snapshot's slugs unless a newer source already wrote a fresher value.
    for (const [slug, balance] of Object.entries(newBalances)) {
      if (pollVersion >= (this.#balanceVersionBySlug.get(slug) ?? -1)) {
        merged[slug] = balance;
        this.#balanceVersionBySlug.set(slug, pollVersion);
      } else {
        merged[slug] = this.#balances![slug];
      }
    }

    // Forget versions of slugs that are no longer present to keep the map bounded.
    for (const slug of this.#balanceVersionBySlug.keys()) {
      if (!(slug in merged)) {
        this.#balanceVersionBySlug.delete(slug);
      }
    }

    if (!areDeepEqual(this.#balances, merged)) {
      this.#balances = merged;
      this.#updateListeners.runCallbacks(this.#balances, 'poll');
    }
  }

  #setBalancesPartially(newBalances: BalanceByTokenAddress) {
    const newBySlug = balanceByTokenAddressToBySlug(this.#chain, newBalances);

    // Keep only the slugs whose value actually changes. A no-op re-emit (the same value pushed
    // again at a later finality) must not advance `#clock` or any slug version, otherwise it would
    // out-version and block a genuinely fresher in-flight poll in `#setAllBalances`.
    const changedBySlug: ApiBalanceBySlug = {};
    for (const [slug, balance] of Object.entries(newBySlug)) {
      if (!this.#balances || this.#balances[slug] !== balance) {
        changedBySlug[slug] = balance;
      }
    }

    const changedSlugs = Object.keys(changedBySlug);
    if (!changedSlugs.length) {
      return;
    }

    // A genuine socket delta is the newest data at apply time, so its changed slugs are stamped now.
    const version = ++this.#clock;
    for (const slug of changedSlugs) {
      this.#balanceVersionBySlug.set(slug, version);
    }

    this.#balances = {
      ...this.#balances,
      ...changedBySlug,
    };
    this.#updateListeners.runCallbacks(this.#balances, 'socket');
  }
}

/**
 * When an incoming token transfer arrives, the socket triggers assets balance updates in a quick succession.
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
    pendingUpdates[tokenAddress ?? VIRTUAL_ADDRESS] = balance;
    notifyThrottled();
  };
}

async function splitKnownAndUnknownTokens(balances: BalanceByTokenAddress) {
  await tokensPreload.promise;

  const known: string[] = [];
  const unknown: string[] = [];

  for (const tokenAddress of Object.keys(balances)) {
    if (tokenAddress === VIRTUAL_ADDRESS || getTokenByAddress(tokenAddress)) {
      known.push(tokenAddress);
    } else {
      unknown.push(tokenAddress);
    }
  }

  return { known, unknown };
}

function balanceByTokenAddressToBySlug(chain: ApiChain, byAddress: BalanceByTokenAddress) {
  const bySlug: ApiBalanceBySlug = {};

  for (const [tokenAddress, balance] of Object.entries(byAddress)) {
    const slug = tokenAddress === VIRTUAL_ADDRESS
      ? getChainConfig(chain).nativeToken.slug
      : buildTokenSlug(chain, tokenAddress);
    bySlug[slug] = balance;
  }

  return bySlug;
}
