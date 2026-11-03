import type { createTaskQueue } from '../../../util/schedulers';
import type { FallbackPollingOptions } from '../../common/polling/fallbackPollingScheduler';
import type { ApiBalanceBySlug, ApiChain, ApiNetwork, StampedBalances } from '../../types';
import type { AbstractWebsocketClient, BalanceUpdate, NewActivitiesCallback, WalletWatcher } from './abstractWsClient';

import { areDeepEqual } from '../../../util/areDeepEqual';
import { createCallbackManager } from '../../../util/callbacks';
import { getChainConfig, getChainsByStandard, getSupportedChains } from '../../../util/chain';
import Deferred from '../../../util/Deferred';
import { pick } from '../../../util/iteratees';
import { logDebug } from '../../../util/logs';
import { throttle } from '../../../util/schedulers';
import { getChainBySlug } from '../../../util/tokens';
import { FallbackPollingScheduler } from '../../common/polling/fallbackPollingScheduler';
import { buildTokenSlug, getTokenByAddress, tokensPreload } from '../../common/tokens';
import { onTokenSlugsMove } from '../../common/tokenSlugMoves';

/** `poll` — HTTP / fallback sync (including first load after connect); `socket` — live wallet subscription. */
export type BalanceStreamUpdateSource = 'poll' | 'socket';

export type OnBalancesUpdate = (balances: ApiBalanceBySlug, updateSource: BalanceStreamUpdateSource) => void;
export type OnLoadingChange = (isLoading: boolean) => void;

type OnSocketBalancesUpdate = (balances: BalanceByTokenAddress, blockByTokenAddress: Record<string, number>) => void;
type BalanceByTokenAddress = Record<string, bigint>;

export type BalanceUpdateCallback = (update: BalanceUpdate) => void;

// An arbitrary string for representing native balance for slugs inside this file only
const VIRTUAL_ADDRESS = '@VIRTUAL';

const SOCKET_THROTTLE_DELAY = 100;
const MISSING_POSITION_BLOCK_TIMEOUT = 10 * 60_000;
const OLDER_POSITION_BLOCK_TIMEOUT = 30 * 60_000;

const crosschainAssetsByChain = new Map<string, ApiBalanceBySlug>();
const crosschainBlocksByChain = new Map<string, Record<string, { block: number; observedAt: number }>>();

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
  onNewActivities?: NewActivitiesCallback;
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

  /**
   * Blocks at which the stored balances were observed, with their source and observation instant. Socket stamps
   * keep their observation instant when a snapshot replaces the value (see `#carryBlockStamp`).
   */
  #balanceBlockBySlug = new Map<string, { block: number; observedAt: number; source: 'socket' | 'snapshot' }>();

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
  /** The chains whose slugs the running poll assigns, `undefined` between the polls */
  #pollChains?: readonly ApiChain[];
  /**
   * A moved slug of another chain asks the next poll to fetch every chain of the standard together, as the first poll
   * does. Only the stream that fetches them together holds such slugs. Kept until that poll starts, as the throttled
   * poll runs with the arguments of its last request.
   */
  #isCrosschainRefetchPending = false;
  #removeSlugMoveListener: NoneToVoidFunction;

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
    onNewActivities,
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
        onNewActivities,
      },
    );
    this.#removeSlugMoveListener = onTokenSlugsMove(this.#handleTokenSlugsMove);

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
      const crosschainKey = `${this.#network}:${this.#chain}:${this.#address.toLowerCase()}`;
      chainBalances = crosschainAssetsByChain.get(crosschainKey) || {};
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
    this.#removeSlugMoveListener();
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

  /**
   * The balances already sent under a slug that passed to another token are amounts of the previous holder, which the
   * UI would show with the new holder's decimals and price. They are dropped at once, before the UI gets the new
   * holder, and fetched again. A poll yet to start assigns the new slugs itself, while a running one may have assigned
   * the old ones, so it is followed by another and cannot bring the dropped balances back. A stream holding the slugs of
   * other chains fetches them all again.
   */
  #handleTokenSlugsMove = (slugs: string[]) => {
    const crosschainKey = `${this.#network}:${this.#chain}:${this.#address.toLowerCase()}`;
    const crosschainBalances = crosschainAssetsByChain.get(crosschainKey);
    const affectedSlugs = slugs.filter((slug) => {
      const chain = getChainBySlug(slug);
      if (this.#pollChains?.includes(chain)) return true;

      return this.#balances
        ? slug in this.#balances
        : chain === this.#chain && crosschainBalances !== undefined && slug in crosschainBalances;
    });
    if (!affectedSlugs.length) return;

    this.#dropBalances(affectedSlugs);
    if (affectedSlugs.some((slug) => getChainBySlug(slug) !== this.#chain)) {
      this.#isCrosschainRefetchPending = true;
    }
    this.#fallbackPollingScheduler?.forceImmediatePoll();
  };

  #handleSocketBalanceUpdate: OnSocketBalancesUpdate = async (newBalances, blockByTokenAddress) => {
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
      const crosschainKey = `${this.#network}:${this.#chain}:${this.#address.toLowerCase()}`;
      chainBalances = crosschainAssetsByChain.get(crosschainKey);
      if (chainBalances) {
        this.#balances = { ...chainBalances };
        for (const [slug, stamp] of Object.entries(crosschainBlocksByChain.get(crosschainKey) ?? {})) {
          if (!this.#balanceBlockBySlug.has(slug)) {
            this.#balanceBlockBySlug.set(slug, { ...stamp, source: 'snapshot' });
          }
        }
      }
    }

    // Normally `this.#balances` must contain all balances before applying partial socket deltas.
    // For a wallet just activated by the socket, the delta is the only fresh source until HTTP APIs catch up.
    if (!chainBalances && !shouldApplyWithoutSnapshot) return;

    const tokenAddresses = await splitKnownAndUnknownTokens(newBalances);

    this.#setBalancesPartially(pick(newBalances, tokenAddresses.known), blockByTokenAddress);

    await this.#importUnknownTokens?.(this.#network, tokenAddresses.unknown, this.#sendUpdateTokens);

    if (this.#isDestroyed) return;

    this.#setBalancesPartially(pick(newBalances, tokenAddresses.unknown), blockByTokenAddress);
  };

  /** Fetches all balances when the socket is not connected or has just connected */
  #poll = async (isInitial?: boolean) => {
    try {
      this.#pollChains = [this.#chain];
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

      if ((isInitial || this.#isCrosschainRefetchPending) && this.#fetchCrosschainBalancesCb) {
        const config = getChainConfig(this.#chain);
        if (!config.chainStandard || config.chainStandard !== this.#chain) {
          if (!wasWokenDuringPrecheck) {
            return;
          }
        } else {
          this.#isCrosschainRefetchPending = false;
          this.#pollChains = getChainsByStandard(this.#chain);
          // Capture the freshness version before awaiting, so a socket delta that arrives during the
          // fetch is recognised as newer than this snapshot.
          const pollVersion = ++this.#clock;
          const crosschainResult
            = await this.#fetchCrosschainBalancesCb?.(this.#network, this.#address, this.#sendUpdateTokens);

          if (crosschainResult) {
            const { balances: crosschainBalances, asOf: crosschainAsOf, blockBySlug } = crosschainResult;
            const knownChains = getSupportedChains();
            const observedAt = Date.now();

            for (const [slug, balance] of Object.entries(crosschainBalances)) {
              const assetChain = getChainBySlug(slug);

              if (!knownChains.includes(assetChain)) {
                continue;
              }

              const crosschainKey = `${this.#network}:${assetChain}:${this.#address.toLowerCase()}`;
              crosschainAssetsByChain.set(crosschainKey, {
                ...crosschainAssetsByChain.get(crosschainKey),
                [slug]: balance,
              });
              const blocks = { ...crosschainBlocksByChain.get(crosschainKey) };
              const block = blockBySlug?.[slug];
              if (block === undefined) {
                delete blocks[slug];
              } else {
                blocks[slug] = { block, observedAt };
              }
              crosschainBlocksByChain.set(crosschainKey, blocks);
            }

            this.#setAllBalances(crosschainBalances, pollVersion, crosschainAsOf, blockBySlug);
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

      const { balances: newBalances, asOf, blockBySlug } = result;
      this.#setAllBalances(newBalances, pollVersion, asOf, blockBySlug);
      this.#balancesDeferred.resolve();
    } finally {
      this.#pollChains = undefined;
      if (!this.#isDestroyed) {
        this.#loadingListeners.runCallbacks(false);
      }
    }
  };

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

  #isOutrankedByBlockStamp(slug: string, snapshotBlocks?: Record<string, number>) {
    if (snapshotBlocks === undefined) return false;
    const stamp = this.#balanceBlockBySlug.get(slug);
    if (!stamp) return false;

    const snapshotBlock = snapshotBlocks[slug];
    return snapshotBlock === undefined
      ? stamp.source === 'socket' && Date.now() - stamp.observedAt < MISSING_POSITION_BLOCK_TIMEOUT
      : snapshotBlock < stamp.block && Date.now() - stamp.observedAt < OLDER_POSITION_BLOCK_TIMEOUT;
  }

  #isOutrankedBySnapshot(
    slug: string,
    pollVersion: number,
    snapshotAsOf?: number,
    snapshotBlocks?: Record<string, number>,
  ) {
    if (this.#balanceBlockBySlug.has(slug) && snapshotBlocks?.[slug] !== undefined) {
      return this.#isOutrankedByBlockStamp(slug, snapshotBlocks);
    }

    return this.#isOutrankedBySlugStamp(slug, snapshotAsOf)
      || this.#isOutrankedByBlockStamp(slug, snapshotBlocks)
      || pollVersion < (this.#balanceVersionBySlug.get(slug) ?? -1);
  }

  /**
   * Records the block of an accepted snapshot. A socket stamp rises to the snapshot's block and keeps the socket's
   * observation instant, so it expires on the socket's schedule. Snapshot stamps use the accepted block and current
   * instant. A snapshot without a block removes either stamp.
   */
  #carryBlockStamp(slug: string, snapshotBlock: number | undefined) {
    const stamp = this.#balanceBlockBySlug.get(slug);

    if (snapshotBlock === undefined) {
      this.#balanceBlockBySlug.delete(slug);
    } else if (stamp?.source === 'socket') {
      this.#balanceBlockBySlug.set(slug, { ...stamp, block: Math.max(stamp.block, snapshotBlock) });
    } else {
      this.#balanceBlockBySlug.set(slug, { block: snapshotBlock, observedAt: Date.now(), source: 'snapshot' });
    }
  }

  #setAllBalances(
    newBalances: ApiBalanceBySlug,
    pollVersion: number,
    snapshotAsOf?: number,
    snapshotBlocks?: Record<string, number>,
  ) {
    let hasOutrankedSlug = false;
    for (const slug of Object.keys(this.#balances ?? {})) {
      if (this.#isOutrankedBySnapshot(slug, pollVersion, snapshotAsOf, snapshotBlocks)) {
        hasOutrankedSlug = true;
        break;
      }
    }

    // Fast path: nothing advanced the clock since this poll captured its version and no stored
    // value outranks the snapshot, so the snapshot is a straight full replace. Clearing
    // the maps keeps them bounded; empty reads as "oldest", the safe default for the next write.
    // Block stamps go to the replacing values, or leave with the slugs the snapshot drops.
    if (this.#clock === pollVersion && !hasOutrankedSlug) {
      this.#balanceVersionBySlug.clear();
      this.#balanceAsOfBySlug.clear();
      for (const slug of this.#balanceBlockBySlug.keys()) {
        if (!(slug in newBalances)) {
          this.#balanceBlockBySlug.delete(slug);
        }
      }
      for (const slug of Object.keys(newBalances)) {
        this.#carryBlockStamp(slug, snapshotBlocks?.[slug]);
        if (snapshotAsOf !== undefined) {
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
        && this.#isOutrankedBySnapshot(slug, pollVersion, snapshotAsOf, snapshotBlocks)) {
        merged[slug] = this.#balances![slug];
      }
    }

    // Apply this snapshot's slugs unless a newer source already wrote a fresher value.
    for (const [slug, balance] of Object.entries(newBalances)) {
      if (!this.#isOutrankedBySnapshot(slug, pollVersion, snapshotAsOf, snapshotBlocks)) {
        merged[slug] = balance;
        this.#balanceVersionBySlug.set(slug, pollVersion);
        this.#carryBlockStamp(slug, snapshotBlocks?.[slug]);
        if (snapshotAsOf === undefined) {
          // A stamp describes the value it was stored with. This source states no instant, so the
          // slug's provenance is unknown again and `#clock` alone ranks it, as it does everywhere
          // no instant is available. Keeping the previous entry would rank this value by an
          // instant it was never observed at.
          this.#balanceAsOfBySlug.delete(slug);
        } else {
          this.#balanceAsOfBySlug.set(slug, snapshotAsOf);
        }
      } else if (this.#balances && slug in this.#balances) {
        // A slug the stream dropped after this snapshot started stays dropped
        merged[slug] = this.#balances[slug];
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
    for (const slug of this.#balanceBlockBySlug.keys()) {
      if (!(slug in merged)) {
        this.#balanceBlockBySlug.delete(slug);
      }
    }

    if (!areDeepEqual(this.#balances, merged)) {
      this.#balances = merged;
      this.#updateListeners.runCallbacks(this.#balances, 'poll');
    }
  }

  #setBalancesPartially(newBalances: BalanceByTokenAddress, blockByTokenAddress: Record<string, number>) {
    const newBySlug = balanceByTokenAddressToBySlug(this.#chain, newBalances);
    const blockBySlug = balanceByTokenAddressToBySlug(this.#chain, blockByTokenAddress);

    // Keep only the slugs whose value actually changes. A no-op re-emit (the same value pushed
    // again at a later finality) must not advance `#clock` or any slug version, otherwise it would
    // out-version and block a genuinely fresher in-flight poll in `#setAllBalances`.
    const changedBySlug: ApiBalanceBySlug = {};
    const observedAt = Date.now();
    for (const [slug, balance] of Object.entries(newBySlug)) {
      const block = blockBySlug[slug];
      const stamp = this.#balanceBlockBySlug.get(slug);
      if (block !== undefined && stamp && block < stamp.block
        && observedAt - stamp.observedAt < OLDER_POSITION_BLOCK_TIMEOUT) {
        continue;
      }
      if (block !== undefined) {
        this.#balanceBlockBySlug.set(slug, {
          block: Math.max(stamp?.block ?? block, block), observedAt, source: 'socket',
        });
      }
      if (!this.#balances || this.#balances[slug] !== balance) {
        changedBySlug[slug] = balance;
        if (block === undefined) {
          this.#balanceBlockBySlug.delete(slug);
        }
      }
    }

    const changedSlugs = Object.keys(changedBySlug);
    if (!changedSlugs.length) {
      return;
    }

    // A genuine socket delta is the newest data at apply time, so its changed slugs are stamped now,
    // both on the client clock and with the observation instant a later snapshot is ranked against.
    const version = ++this.#clock;
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

  /** Removes the balances of the slugs, stamped as newer than any snapshot already fetched, so none brings them back */
  #dropBalances(slugs: string[]) {
    const version = ++this.#clock;
    for (const slug of slugs) {
      this.#balanceVersionBySlug.set(slug, version);
      this.#balanceAsOfBySlug.delete(slug);
      this.#balanceBlockBySlug.delete(slug);
    }

    if (!this.#balances || !slugs.some((slug) => slug in this.#balances!)) return;

    const balances = { ...this.#balances };
    for (const slug of slugs) {
      delete balances[slug];
    }
    this.#balances = balances;
    this.#updateListeners.runCallbacks(this.#balances, 'poll');
  }
}

/**
 * When an incoming token transfer arrives, the socket triggers assets balance updates in a quick succession.
 * To avoid excessive UI updates, we throttle the balance updates.
 */
function throttleSocketBalanceUpdates(onUpdate: OnSocketBalancesUpdate): BalanceUpdateCallback {
  let pendingUpdates: BalanceByTokenAddress = {};
  let pendingBlocks: Record<string, number> = {};

  const notifyThrottled = throttle(() => {
    const updates = pendingUpdates;
    const blocks = pendingBlocks;
    pendingUpdates = {};
    pendingBlocks = {};
    onUpdate(updates, blocks);
  }, SOCKET_THROTTLE_DELAY, false);

  return ({ tokenAddress, balance, blockNumber }) => {
    const address = tokenAddress ?? VIRTUAL_ADDRESS;
    const pendingBlock = pendingBlocks[address];
    if (blockNumber !== undefined && pendingBlock !== undefined && blockNumber < pendingBlock) return;

    pendingUpdates[address] = balance;
    if (blockNumber === undefined) {
      delete pendingBlocks[address];
    } else {
      pendingBlocks[address] = blockNumber;
    }
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

function balanceByTokenAddressToBySlug<T>(chain: ApiChain, byAddress: Record<string, T>) {
  const bySlug: Record<string, T> = {};

  for (const [tokenAddress, balance] of Object.entries(byAddress)) {
    const slug = tokenAddress === VIRTUAL_ADDRESS
      ? getChainConfig(chain).nativeToken.slug
      : buildTokenSlug(chain, tokenAddress);
    bySlug[slug] = balance;
  }

  return bySlug;
}
