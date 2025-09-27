import type { InMessageCallback } from '../../util/reconnectingWebsocket';
import type {
  ApiChain,
  ApiClientSocketMessage,
  ApiNetwork,
  ApiNewActivitySocketMessage,
  ApiServerSocketMessage,
  ApiSocketEventType,
  ApiSubscribedSocketMessage,
} from '../types';

import { BRILLIANT_API_BASE_URL } from '../../config';
import ReconnectingWebSocket from '../../util/reconnectingWebsocket';
import safeExec from '../../util/safeExec';
import { throttle } from '../../util/schedulers';
import withCache from '../../util/withCache';
import { addBackendHeadersToSocketUrl } from './backend';
import { getBackendConfigCache } from './cache';

const ACTUALIZATION_DELAY = 10;

interface WatchedWallet {
  chain: ApiChain;
  events: ApiSocketEventType[];
  address: string;
}

export interface WalletWatcher {
  /** Whether the socket is connected and subscribed to the given wallets */
  readonly isConnected: boolean;
  /** Removes the watcher and cleans the memory */
  destroy(): void;
}

interface WalletWatcherInternal extends WalletWatcher {
  id: number;
  wallets: WatchedWallet[];
  isConnected: boolean;
  /**
   * Called when a new activity arrives into one of the listened address.
   * In this context activity is any confirmed wallet change.
   * Called only for wallets with an `activity` event.
   *
   * Called only when `isConnected` is true. Therefore, when the socket reconnects, the users should synchronize,
   * otherwise the activity happening during the reconnect will miss.
   */
  onNewActivity?: NewActivityCallback;
  /** Called when isConnected turns true */
  onConnect?: NoneToVoidFunction;
  /** Called when isConnected turns false */
  onDisconnect?: NoneToVoidFunction;
}

export type NewActivityCallback = (wallet: WatchedWallet) => void;

/**
 * Connects to the MTW backend to passively listen to updates.
 */
class BackendSocket {
  #network: ApiNetwork;

  /** Defined only when the socket it needed (i.e. somebody wants to watch something) */
  #socket?: ReconnectingWebSocket<ApiClientSocketMessage, ApiServerSocketMessage>;

  #walletWatchers: WalletWatcherInternal[] = [];

  /**
   * A shared incremental counter for various unique ids. The fact that it's incremental is used to tell what actions
   * happened earlier or later than others.
   */
  #currentUniqueId = 0;

  constructor(network: ApiNetwork) {
    this.#network = network;
  }

  public watchWallets(
    wallets: WatchedWallet[],
    {
      onNewActivity,
      onConnect,
      onDisconnect,
    }: Pick<WalletWatcherInternal, 'onNewActivity' | 'onConnect' | 'onDisconnect'> = {},
  ): WalletWatcher {
    const id = this.#currentUniqueId++;
    const watcher: WalletWatcherInternal = {
      id,
      wallets,
      // The status will turn to `true` via `#actualizeSocket` → `#sendWatchedWalletsToSocket` → socket request → socket response → `#handleSubscribed`
      isConnected: false,
      onNewActivity,
      onConnect,
      onDisconnect,
      destroy: this.#destroyWalletWatcher.bind(this, id),
    };
    this.#walletWatchers.push(watcher);
    this.#actualizeSocket();
    return watcher;
  }

  /** Removes the given watcher and unsubscribes from its wallets. Brings the sockets to the proper state. */
  #destroyWalletWatcher(watcherId: number) {
    const index = this.#walletWatchers.findIndex((watcher) => watcher.id === watcherId);
    if (index >= 0) {
      this.#walletWatchers.splice(index, 1);
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
  #actualizeSocket = throttle(async () => {
    const { isWebSocketEnabled } = await getBackendConfigCache();

    if (isWebSocketEnabled && this.#doesHaveWatchedAddresses()) {
      this.#socket ??= this.#createSocket();
      if (this.#socket.isConnected) {
        this.#sendWatchedWalletsToSocket();
      } // Otherwise, the addresses will be sent when the socket gets connected
    } else {
      this.#socket?.close();
      this.#socket = undefined;
    }
  }, ACTUALIZATION_DELAY, false);

  #createSocket() {
    const url = getSocketUrl(this.#network);
    const socket = new ReconnectingWebSocket<ApiClientSocketMessage, ApiServerSocketMessage>(url);
    socket.onMessage(this.#handleSocketMessage);
    socket.onConnect(this.#handleSocketConnect);
    socket.onDisconnect(this.#handleSocketDisconnect);
    return socket;
  }

  #handleSocketMessage: InMessageCallback<ApiServerSocketMessage> = (message) => {
    switch (message.type) {
      case 'subscribed':
        this.#handleSubscribed(message);
        break;
      case 'newActivity':
        this.#handleNewActivity(message);
        break;
    }
  };

  #handleSocketConnect = () => {
    this.#sendWatchedWalletsToSocket();
  };

  #handleSocketDisconnect = () => {
    for (const watcher of this.#walletWatchers) {
      if (watcher.isConnected) {
        watcher.isConnected = false;
        if (watcher.onDisconnect) safeExec(watcher.onDisconnect);
      }
    }
  };

  #handleSubscribed(message: ApiSubscribedSocketMessage) {
    for (const watcher of this.#walletWatchers) {
      // If message id < watcher id, then the watcher was created after the subscribe request was sent, therefore
      // the socket may be not subscribed to all the watcher addresses yet.
      if (message.id < watcher.id) {
        continue;
      }

      if (!watcher.isConnected) {
        watcher.isConnected = true;
        if (watcher.onConnect) safeExec(watcher.onConnect);
      }
    }
  }

  #handleNewActivity(message: ApiNewActivitySocketMessage) {
    const messageAddresses = new Set(message.addresses);

    for (const { wallets, isConnected, onNewActivity } of this.#walletWatchers) {
      // Even though the socket may already listen to some wallet addresses, we promise the class users to trigger the
      // onNewActivity callback only in the connected state.
      if (!isConnected || !onNewActivity) {
        continue;
      }

      for (const wallet of wallets) {
        const doesWalletMatch = (
          wallet.chain === message.chain
          && messageAddresses.has(wallet.address)
          && wallet.events.includes('activity')
        );

        if (doesWalletMatch) {
          safeExec(() => onNewActivity(wallet));
        }
      }
    }
  }

  #sendWatchedWalletsToSocket() {
    // It's necessary to collect the watched addresses synchronously with locking the request id.
    // It makes sure that all the watchers with ids < the response id will be subscribed.
    const addresses = this.#getWatchedAddresses(['activity']);
    const requestId = this.#currentUniqueId++;

    // It's necessary to send a `subscribe` request on every `#sendWatchedWalletsToSocket` call, even if the list of
    // addresses hasn't changed. Otherwise, the mechanism turning `isConnected` to `true` in the watchers will break if
    // a new watcher containing only existing addresses is added.
    this.#socket!.send({
      type: 'subscribe',
      id: requestId,
      addresses: addresses.map((address) => ({
        ...address,
        events: ['activity'],
      })),
    });
  }

  #doesHaveWatchedAddresses() {
    return this.#walletWatchers.some((watcher) => watcher.wallets.length);
  }

  /** Collects the addresses (grouped by chain) from the current watchers */
  #getWatchedAddresses(events: ApiSocketEventType[]) {
    const addresses: { chain: ApiChain; address: string }[] = [];

    for (const watcher of this.#walletWatchers) {
      for (const wallet of watcher.wallets) {
        if (!wallet.events.some((event) => events.includes(event))) {
          continue;
        }

        addresses.push({
          chain: wallet.chain,
          address: wallet.address,
        });
      }
    }

    return addresses;
  }
}

function getSocketUrl(network: ApiNetwork) {
  const url = new URL(BRILLIANT_API_BASE_URL);
  url.protocol = url.protocol === 'http' ? 'ws' : 'wss';
  url.pathname += `${network === 'testnet' ? 'testnet/' : ''}ws`;
  addBackendHeadersToSocketUrl(url);
  return url;
}

/** Returns a singleton (one constant instance per a network) */
export const getBackendSocket = withCache((network: ApiNetwork) => {
  return new BackendSocket(network);
});

export type { BackendSocket };
