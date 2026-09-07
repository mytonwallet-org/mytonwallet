import type { createTaskQueue } from '../../../util/schedulers';
import type { FallbackPollingOptions } from '../../common/polling/fallbackPollingScheduler';
import type { ApiBalanceBySlug, ApiChain, ApiNetwork, StampedBalances } from '../../types';
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
  ) => Promise<StampedBalances>;
  fetchCrosschainBalancesCb?: (
    network: ApiNetwork,
    address: string,
    sendUpdateTokens: NoneToVoidFunction,
  ) => Promise<StampedBalances>;
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

  /**
   * Per-slug instant at which the source observed the value currently stored for that slug, in
   * unix ms. `#clock` orders writes by when this client saw them, which mis-ranks a snapshot
   * served from a cache filled before a delta that has already landed: it starts later, so it
   * looks newer. This map ranks by where the data comes from instead, and outranks `#clock`
   * whenever both the stored value and the incoming snapshot carry an instant. A source that
   * states no instant (an older gateway) leaves the slug unstamped and keeps the clock ordering.
   */
  #balanceAsOfBySlug = new Map<string, number>();

  #walletWatcher: WalletWatcher;
  #fallbackPollingOptions: FallbackPollingOptions;
  #fallbackPollingScheduler?: FallbackPollingScheduler;

  #updateListeners = createCallbackManager<OnBalancesUpdate>();
  #loadingListeners = createCallbackManager<OnLoadingChange>();

  #fetchBalancesCb: (
    network: ApiNetwork,
    address: string,
    sendUpdateTokens: NoneToVoidFunction
  ) => Promise<StampedBalances>;

  #fetchCrosschainBalancesCb?: (
    network: ApiNetwork,
    address: string,
    sendUpdateTokens: NoneToVoidFunction,
  ) => Promise<StampedBalances>;

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

    // Capture before flipping to `active`. `undefined` is the in-flight precheck, `inactive` is a
    // finished skip: neither has an HTTP snapshot, so the delta is the only fresh source until the
    // forced poll lands. `=== 'inactive'` alone dropped the first-funds event when it arrived
    // while `getIsWalletActive` was still running.
    const shouldApplyWithoutSnapshot = this.#walletStatus !== 'active';

    if (this.#walletStatus !== 'active') {
      this.#walletStatus = 'active';
      this.#fallbackPollingScheduler.forceImmediatePoll();
    }

    const config = getChainConfig(this.#chain);

    let chainBalances = this.#balances;

    // A stream on a non-standard chain usually receives its snapshot via the standard-chain
    // cross-chain fan-out rather than its own poll. The map is only a fallback: when this stream
    // has completed its own poll, its `#balances` are authoritative, and the map may legitimately
    // be empty (the standard-chain stream is inactive for wallets with no activity there).
    if (!chainBalances && config.chainStandard && config.chainStandard !== this.#chain) {
      chainBalances = crosschainAssetsByChain.get(this.#chain);
    }

    // Normally `this.#balances` must contain all balances before applying partial socket deltas.
    // For a wallet just activated by the socket, the delta is the only fresh source until HTTP APIs catch up.
    if (!chainBalances && !shouldApplyWithoutSnapshot) return;

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

      // True when a socket/activity wake flipped the stream to active while this precheck was
      // still in flight. The isInitial cross-chain skip below would otherwise return without
      // fetching this chain, and a non-standard EVM wallet that just received its first funds
      // would wait until restart.
      let wasWokenDuringPrecheck = false;

      if (!this.#walletStatus) {
        const isEnsured = await this.#ensureIsPollingNeeded!();

        if (!isEnsured && !this.#isWalletActive()) {
          logDebug('balanceStream: wallet is inactive, skip polling', this.#chain, this.#address);
          this.#walletStatus = 'inactive';
          return;
        }
        wasWokenDuringPrecheck = !isEnsured;
        this.#walletStatus = 'active';
      }

      if (this.#walletStatus === 'inactive') {
        return;
      }

      if (isInitial && this.#fetchCrosschainBalancesCb) {
        const config = getChainConfig(this.#chain);
        if (!config.chainStandard || config.chainStandard !== this.#chain) {
          if (!wasWokenDuringPrecheck) {
            return;
          }
        } else {
          // Capture the freshness version before awaiting, so a socket delta that arrives during the
          // fetch is recognised as newer than this snapshot.
          const pollVersion = ++this.#clock;
          const crosschainResult
            = await this.#fetchCrosschainBalancesCb?.(this.#network, this.#address, this.#sendUpdateTokens);

          if (crosschainResult) {
            const { balances: crosschainBalances, asOf: crosschainAsOf } = crosschainResult;
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

            this.#setAllBalances(crosschainBalances, pollVersion, crosschainAsOf);
            this.#balancesDeferred.resolve();
          }

          return;
        }
      }

      const throttledFetchBalances = this.#loadingConcurrencyLimiter?.wrap(this.#fetchBalancesCb)
        ?? this.#fetchBalancesCb;
      // Capture the freshness version before awaiting, so a socket delta that arrives during the
      // fetch is recognised as newer than this snapshot.
      const pollVersion = ++this.#clock;
      const result = await throttledFetchBalances(this.#network, this.#address, this.#sendUpdateTokens);
      if (this.#isDestroyed) return;

      const { balances: newBalances, asOf } = result;
      this.#setAllBalances(newBalances, pollVersion, asOf);
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
  /**
   * True when the value stored for `slug` was observed after this snapshot was, so the snapshot
   * must not touch it however late it arrives. Only a snapshot that states its own instant can be
   * outranked: without one there is nothing to compare, and `#clock` decides as before.
   */
  #isOutrankedBySlugStamp(slug: string, snapshotAsOf?: number) {
    if (snapshotAsOf === undefined) return false;
    const storedAsOf = this.#balanceAsOfBySlug.get(slug);
    return storedAsOf !== undefined && storedAsOf > snapshotAsOf;
  }

  #setAllBalances(newBalances: ApiBalanceBySlug, pollVersion: number, snapshotAsOf?: number) {
    let hasOutrankedSlug = false;
    if (snapshotAsOf !== undefined) {
      for (const storedAsOf of this.#balanceAsOfBySlug.values()) {
        if (storedAsOf > snapshotAsOf) {
          hasOutrankedSlug = true;
          break;
        }
      }
    }

    // Fast path: nothing advanced the clock since this poll captured its version and no stored
    // value was observed after the snapshot, so the snapshot is a straight full replace. Clearing
    // the maps keeps them bounded; empty reads as "oldest", the safe default for the next write.
    if (this.#clock === pollVersion && !hasOutrankedSlug) {
      this.#balanceVersionBySlug.clear();
      this.#balanceAsOfBySlug.clear();
      if (snapshotAsOf !== undefined) {
        for (const slug of Object.keys(newBalances)) {
          this.#balanceAsOfBySlug.set(slug, snapshotAsOf);
        }
      }
      if (!areDeepEqual(this.#balances, newBalances)) {
        this.#balances = newBalances;
        this.#updateListeners.runCallbacks(this.#balances, 'poll');
      }
      return;
    }

    // Slow path: a newer write interleaved; merge per-slug, provenance first and clock second.
    const merged: ApiBalanceBySlug = {};

    // Keep slugs that a newer source updated and that this snapshot does not refresh.
    for (const slug of Object.keys(this.#balances ?? {})) {
      if (!(slug in newBalances)
        && (this.#isOutrankedBySlugStamp(slug, snapshotAsOf)
          || pollVersion < (this.#balanceVersionBySlug.get(slug) ?? -1))) {
        merged[slug] = this.#balances![slug];
      }
    }

    // Apply this snapshot's slugs unless a newer source already wrote a fresher value.
    for (const [slug, balance] of Object.entries(newBalances)) {
      if (!this.#isOutrankedBySlugStamp(slug, snapshotAsOf)
        && pollVersion >= (this.#balanceVersionBySlug.get(slug) ?? -1)) {
        merged[slug] = balance;
        this.#balanceVersionBySlug.set(slug, pollVersion);
        if (snapshotAsOf === undefined) {
          // A stamp describes the value it was stored with. This source states no instant, so the
          // slug's provenance is unknown again and `#clock` alone ranks it, as it does everywhere
          // no instant is available. Keeping the previous entry would rank this value by an
          // instant it was never observed at.
          this.#balanceAsOfBySlug.delete(slug);
        } else {
          this.#balanceAsOfBySlug.set(slug, snapshotAsOf);
        }
      } else {
        merged[slug] = this.#balances![slug];
      }
    }

    // Forget entries for slugs that are no longer present to keep the maps bounded.
    for (const slug of this.#balanceVersionBySlug.keys()) {
      if (!(slug in merged)) {
        this.#balanceVersionBySlug.delete(slug);
      }
    }
    for (const slug of this.#balanceAsOfBySlug.keys()) {
      if (!(slug in merged)) {
        this.#balanceAsOfBySlug.delete(slug);
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

    // A genuine socket delta is the newest data at apply time, so its changed slugs are stamped now,
    // both on the client clock and with the observation instant a later snapshot is ranked against.
    const version = ++this.#clock;
    const observedAt = Date.now();
    for (const slug of changedSlugs) {
      this.#balanceVersionBySlug.set(slug, version);
      this.#balanceAsOfBySlug.set(slug, observedAt);
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
