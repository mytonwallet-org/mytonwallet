import type { SocketFinality } from '../../chains/ton/toncenter/types';
import type { ApiActivity } from '../../types';

import ReconnectingWebSocket from '../../../util/reconnectingWebsocket';
import { throttle } from '../../../util/schedulers';

export type InMessageCallback<T> = (message: T) => void;

const ACTUALIZATION_DELAY = 10;

export interface WalletWatcher {
  /** Whether the socket is connected and subscribed to the given wallets */
  readonly isConnected: boolean;
  /** Removes the watcher and cleans the memory */
  destroy(): void;
}

export interface BalanceUpdate {
  address: string;
  /** `undefined` for chain Native Token */
  tokenAddress?: string;
  balance: bigint;
  finality: SocketFinality;
}

export interface ActivitiesUpdate {
  address: string;
  /**
   * Multiple events with the same normalized hash can arrive. Every time it happens, the new event data must replace
   * the previous event data in the app state. If the `activities` array is empty, the actions with that normalized hash
   * must be removed from the app state. Pending actions are eventually either removed or replaced with confirmed actions.
   */
  messageHashNormalized: string;
  finality: SocketFinality;
  /** The activities may be unsorted */
  activities: ApiActivity[];
}

export type NewActivitiesCallback<T = ActivitiesUpdate> = (update: T) => void;

export type BalanceUpdateCallback = (update: BalanceUpdate) => void;

export type TraceInvalidatedCallback = NoneToVoidFunction;

export type NftUpdateCallback = (update: { signature: string }) => void;

export interface WalletWatcherInternal<T = { address: string }, K = ActivitiesUpdate> extends WalletWatcher {
  id: number;
  wallets: T[];
  isConnected: boolean;
  /**
   * Called when new activities (either regular or pending) arrive into one of the listened address.
   *
   * Called only when `isConnected` is true. Therefore, when the socket reconnects, the users should synchronize,
   * otherwise the activities arriving during the reconnect will miss.
   */
  onNewActivities?: NewActivitiesCallback<K>;
  /**
   * Called when a balance changes (either native or token) in one of the listened address.
   *
   * Called only when `isConnected` is true. Therefore, when the socket reconnects, the users should synchronize,
   * otherwise the balances changed during the reconnect will be outdated.
   */
  onBalanceUpdate?: BalanceUpdateCallback;
  /** Called when isConnected turns true */
  onConnect?: NoneToVoidFunction;
  /** Called when isConnected turns false */
  onDisconnect?: NoneToVoidFunction;
  /**
   * Called when a trace is invalidated. This means any balance updates received from `confirmed` finality level
   * for this trace may be stale and should trigger a balance re-fetch.
   *
   * Note: Toncenter V2 streaming API doesn't provide corrected balance updates on trace invalidation,
   * so we must re-poll to get accurate balances.
   */
  onTraceInvalidated?: TraceInvalidatedCallback;

  onNftUpdated?: NftUpdateCallback;
}

type WalletWatcherInternalCallbacks<K = ActivitiesUpdate> = Pick<WalletWatcherInternal<never, K>,
 'onNewActivities' | 'onBalanceUpdate' | 'onConnect' | 'onDisconnect' | 'onTraceInvalidated' | 'onNftUpdated'
>;

export abstract class AbstractWebsocketClient<
  OutMessage = any,
  InMessage = any,
  WatchedWallet = { address: string },
  Activity = ActivitiesUpdate,
> {
  #url: URL;

  protected socket?: ReconnectingWebSocket<OutMessage, InMessage>;

  protected walletWatchers: WalletWatcherInternal<WatchedWallet, Activity>[] = [];

  /**
   * A shared incremental counter for various unique ids. The fact that it's incremental is used to tell what actions
   * happened earlier or later than others.
   */
  protected currentUniqueId = 0;

  constructor(url: URL) {
    this.#url = url;
  }

  public watchWallets(
    wallets: WatchedWallet[],
    {
      onNewActivities,
      onBalanceUpdate,
      onConnect,
      onDisconnect,
      onTraceInvalidated,
      onNftUpdated,
    }: WalletWatcherInternalCallbacks<Activity> = {},
  ): WalletWatcher {
    const id = this.currentUniqueId++;
    const watcher: WalletWatcherInternal<WatchedWallet, Activity> = {
      id,
      wallets,
      // The status will turn to `true` via `#actualizeSocket` → `#sendWatchedWalletsToSocket` → socket request → socket response → `#handleSubscriptionSet`
      isConnected: false,
      onNewActivities,
      onBalanceUpdate,
      onTraceInvalidated,
      onConnect,
      onDisconnect,
      onNftUpdated,
      destroy: this.#destroyWalletWatcher.bind(this, id),
    };
    this.walletWatchers.push(watcher);
    this.#actualizeSocket();
    return watcher;
  }

  /** Removes the given watcher and unsubscribes from its wallets. Brings the sockets to the proper state. */
  #destroyWalletWatcher(watcherId: number) {
    const index = this.walletWatchers.findIndex((watcher) => watcher.id === watcherId);
    if (index >= 0) {
      this.walletWatchers.splice(index, 1);
      this.#actualizeSocket();
    }
  }

  /**
   * Creates or destroys the given socket (if needed) and subscribes to the watched wallets.
   *
   * The method is throttled in order to:
   *  - Avoid sending too many requests when the watched addresses change many times in a short time range.
   *  - Avoid reconnecting the socket when watched addresses arrive shortly after stopping watching all addresses.
   */
  #actualizeSocket = throttle(() => {
    if (this.#doesHaveWatchedAddresses()) {
      this.socket ??= this.#createSocket();
      if (this.socket.isConnected) {
        this.sendWatchedWalletsToSocket();
      } // Otherwise, the addresses will be sent when the socket gets connected
    } else {
      this.socket?.close();
      this.socket = undefined;
    }
  }, ACTUALIZATION_DELAY, false);

  #createSocket() {
    const socket = new ReconnectingWebSocket<OutMessage, InMessage>(this.#url);
    socket.onMessage(this.handleSocketMessage);
    socket.onConnect(this.handleSocketConnect);
    socket.onDisconnect(this.handleSocketDisconnect);
    return socket;
  }

  #doesHaveWatchedAddresses() {
    return this.walletWatchers.some((watcher) => watcher.wallets.length);
  }

  protected isWatcherReady(watcher: WalletWatcherInternal<WatchedWallet>) {
    // Even though the socket may already listen to some wallet addresses, we promise the class users to trigger the
    // callbacks only in the connected state.
    return watcher.isConnected;
  }

  protected abstract handleSocketMessage: InMessageCallback<InMessage>;
  protected abstract handleSocketConnect: NoneToVoidFunction;
  protected abstract handleSocketDisconnect: NoneToVoidFunction;
  protected abstract sendWatchedWalletsToSocket: NoneToVoidFunction;
}
