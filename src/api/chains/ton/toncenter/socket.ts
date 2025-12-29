import type { ApiActivity, ApiNetwork } from '../../../types';
import type {
  AccountStateChangeSocketMessage,
  ActionsSocketMessage,
  AddressBook,
  AnyAction,
  ClientSocketMessage,
  JettonChangeSocketMessage,
  ServerSocketMessage,
  SocketSubscriptionEvent,
} from './types';

import { TONCENTER_ACTIONS_VERSION } from '../../../../config';
import ReconnectingWebSocket, { type InMessageCallback } from '../../../../util/reconnectingWebsocket';
import safeExec from '../../../../util/safeExec';
import { forbidConcurrency, setCancellableTimeout, throttle } from '../../../../util/schedulers';
import withCache from '../../../../util/withCache';
import { areAddressesEqual, toBase64Address } from '../util/tonCore';
import { getNftSuperCollectionsByCollectionAddress } from '../../../common/addresses';
import { addBackendHeadersToSocketUrl } from '../../../common/backend';
import { SEC } from '../../../constants';
import { NETWORK_CONFIG } from '../constants';
import { parseActions } from './actions';

const ACTUALIZATION_DELAY = 10;

// Toncenter closes the socket after 30 seconds of inactivity
const PING_INTERVAL = 20 * SEC;

// When the internet connection is interrupted, the Toncenter socket doesn't always disconnect automatically.
// Disconnecting manually if there is no response for "ping".
const PONG_TIMEOUT = 5 * SEC;

export interface WalletWatcher {
  /** Whether the socket is connected and subscribed to the given wallets */
  readonly isConnected: boolean;
  /** Removes the watcher and cleans the memory */
  destroy(): void;
}

interface WalletWatcherInternal extends WalletWatcher {
  id: number;
  addresses: string[];
  isConnected: boolean;
  /**
   * Called when new activities (either regular or pending) arrive into one of the listened address.
   *
   * Called only when `isConnected` is true. Therefore, when the socket reconnects, the users should synchronize,
   * otherwise the activities arriving during the reconnect will miss.
   */
  onNewActivities?: NewActivitiesCallback;
  /**
   * Called when a balance changes (either TON or token) in one of the listened address.
   *
   * Called only when `isConnected` is true. Therefore, when the socket reconnects, the users should synchronize,
   * otherwise the balances changed during the reconnect will be outdated.
   */
  onBalanceUpdate?: BalanceUpdateCallback;
  /** Called when isConnected turns true */
  onConnect?: NoneToVoidFunction;
  /** Called when isConnected turns false */
  onDisconnect?: NoneToVoidFunction;
}

export type NewActivitiesCallback = (update: ActivitiesUpdate) => void;

export interface ActivitiesUpdate {
  address: string;
  /**
   * Multiple events with the same normalized hash can arrive. Every time it happens, the new event data must replace
   * the previous event data in the app state. If the `activities` array is empty, the actions with that normalized hash
   * must be removed from the app state. Pending actions are eventually either removed or replaced with confirmed actions.
   */
  messageHashNormalized: string;
  /** Pending actions are not confirmed by the blockchain yet */
  arePending: boolean;
  /** The activities may be unsorted */
  activities: ApiActivity[];
}

export type BalanceUpdateCallback = (update: BalanceUpdate) => void;

export interface BalanceUpdate {
  address: string;
  /** `undefined` for TON */
  tokenAddress?: string;
  balance: bigint;
}

/**
 * Connects to Toncenter to passively listen to updates.
 */
class ToncenterSocket {
  #network: ApiNetwork;

  #socket?: ReconnectingWebSocket<ClientSocketMessage, ServerSocketMessage>;

  /** See #rememberAddressesOfNormalizedHash */
  #addressesByHash: Record<string, string[]> = {};

  #walletWatchers: WalletWatcherInternal[] = [];

  /**
   * A shared incremental counter for various unique ids. The fact that it's incremental is used to tell what actions
   * happened earlier or later than others.
   */
  #currentUniqueId = 0;

  #stopPing?: NoneToVoidFunction;
  #cancelReconnect?: NoneToVoidFunction;

  constructor(network: ApiNetwork) {
    this.#network = network;
  }

  public watchWallets(
    addresses: string[],
    {
      onNewActivities,
      onBalanceUpdate,
      onConnect,
      onDisconnect,
    }: Pick<WalletWatcherInternal, 'onNewActivities' | 'onBalanceUpdate' | 'onConnect' | 'onDisconnect'> = {},
  ): WalletWatcher {
    const id = this.#currentUniqueId++;
    const watcher: WalletWatcherInternal = {
      id,
      addresses,
      // The status will turn to `true` via `#actualizeSocket` → `#sendWatchedWalletsToSocket` → socket request → socket response → `#handleSubscriptionSet`
      isConnected: false,
      onNewActivities,
      onBalanceUpdate,
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
  #actualizeSocket = throttle(() => {
    if (this.#doesHaveWatchedAddresses()) {
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
    const socket = new ReconnectingWebSocket<ClientSocketMessage, ServerSocketMessage>(url);
    socket.onMessage(this.#handleSocketMessage);
    socket.onConnect(this.#handleSocketConnect);
    socket.onDisconnect(this.#handleSocketDisconnect);
    return socket;
  }

  #handleSocketMessage: InMessageCallback<ServerSocketMessage> = (message) => {
    this.#cancelReconnect?.();

    if ('status' in message) {
      if (message.status === 'subscription_set') {
        this.#handleSubscriptionSet(message);
      }
    }

    if ('type' in message) {
      if (message.type === 'trace_invalidated') {
        message = {
          ...message,
          type: 'pending_actions',
          actions: [],
          address_book: {},
          metadata: {},
        };
        // Falling down to the below `switch` intentionally
      }

      switch (message.type) {
        case 'actions':
        case 'pending_actions':
          void this.#handleNewActions(message);
          break;
        case 'account_state_change':
          this.#handleAccountStateChange(message);
          break;
        case 'jettons_change':
          this.#handleJettonChange(message);
          break;
      }
    }
  };

  #handleSocketConnect = () => {
    this.#socket?.send({
      operation: 'configure',
      include_address_book: true,
      include_metadata: true,
      supported_action_types: [TONCENTER_ACTIONS_VERSION],
    });
    this.#sendWatchedWalletsToSocket();

    this.#startPing();
  };

  #handleSocketDisconnect = () => {
    this.#stopPing?.();

    for (const watcher of this.#walletWatchers) {
      if (watcher.isConnected) {
        watcher.isConnected = false;
        if (watcher.onDisconnect) safeExec(watcher.onDisconnect);
      }
    }
  };

  #handleSubscriptionSet(message: Extract<ServerSocketMessage, { status: any }>) {
    for (const watcher of this.#walletWatchers) {
      // If message id < watcher id, then the watcher was created after the subscribe request was sent, therefore
      // the socket may be not subscribed to all the watcher addresses yet.
      if (message.id && Number(message.id) < watcher.id) {
        continue;
      }

      if (!watcher.isConnected) {
        watcher.isConnected = true;
        if (watcher.onConnect) safeExec(watcher.onConnect);
      }
    }
  }

  // Limiting the concurrency to 1 to ensure the new activities are reported in the order they were received
  #handleNewActions = forbidConcurrency(async (message: ActionsSocketMessage) => {
    const arePending = message.type === 'pending_actions';
    const messageHashNormalized = message.trace_external_hash_norm;
    const activitiesByAddress = await parseSocketActions(
      this.#network,
      message,
      this.#getAddressesReadyForActivities(),
    );
    const addressesToNotify = this.#rememberAddressesOfHash(
      messageHashNormalized,
      Object.keys(activitiesByAddress),
      arePending,
    );

    for (const watcher of this.#walletWatchers) {
      if (!isWatcherReadyForNewActivities(watcher)) {
        continue;
      }

      for (const address of watcher.addresses) {
        if (!addressesToNotify.has(address)) {
          continue;
        }

        safeExec(() => watcher.onNewActivities({
          address,
          messageHashNormalized,
          arePending,
          activities: activitiesByAddress[address] ?? [],
        }));
      }
    }
  });

  #handleAccountStateChange(message: AccountStateChangeSocketMessage) {
    this.#notifyBalanceUpdate(
      message.account,
      undefined,
      BigInt(message.state.balance),
    );
  }

  #handleJettonChange(message: JettonChangeSocketMessage) {
    this.#notifyBalanceUpdate(
      message.jetton.owner,
      toBase64Address(message.jetton.jetton, true, this.#network),
      BigInt(message.jetton.balance),
    );
  }

  #notifyBalanceUpdate(rawAddress: string, tokenBase64Address: string | undefined, balance: bigint) {
    for (const watcher of this.#walletWatchers) {
      const { onBalanceUpdate } = watcher;

      if (!isWatcherReady(watcher) || !onBalanceUpdate) {
        continue;
      }

      for (const watchedAddress of watcher.addresses) {
        if (!areAddressesEqual(watchedAddress, rawAddress)) {
          continue;
        }

        safeExec(() => onBalanceUpdate({
          address: watchedAddress,
          tokenAddress: tokenBase64Address,
          balance,
        }));
      }
    }
  }

  #sendWatchedWalletsToSocket() {
    // It's necessary to collect the watched addresses synchronously with locking the request id.
    // It makes sure that all the watchers with ids < the response id will be subscribed.
    const subscriptions = this.#getAddressSubscriptions();
    const requestId = String(this.#currentUniqueId++);

    // It's necessary to send a `set_subscription` request on every `#sendWatchedWalletsToSocket` call, even if the list
    // of addresses hasn't changed. Otherwise, the mechanism turning `isConnected` to `true` in the watchers will break
    // if a new watcher containing only existing addresses is added.
    this.#socket!.send({
      operation: 'set_subscription',
      id: requestId,
      subscriptions,
    });
  }

  #doesHaveWatchedAddresses() {
    return this.#walletWatchers.some((watcher) => watcher.addresses.length);
  }

  #getAddressSubscriptions() {
    const subscriptions: Record<string, Set<SocketSubscriptionEvent>> = {};

    for (const watcher of this.#walletWatchers) {
      for (const address of watcher.addresses) {
        subscriptions[address] ||= new Set();

        if (watcher.onNewActivities) {
          subscriptions[address].add('actions');
          subscriptions[address].add('pending_actions');
        }

        if (watcher.onBalanceUpdate) {
          subscriptions[address].add('account_state_change');
          subscriptions[address].add('jettons_change');
        }
      }
    }

    const preparedSubscriptions: Record<string, SocketSubscriptionEvent[]> = {};

    for (const [address, events] of Object.entries(subscriptions)) {
      if (events.size) {
        preparedSubscriptions[address] = [...events];
      }
    }

    return preparedSubscriptions;
  }

  #getAddressesReadyForActivities() {
    const watchedAddresses = new Set<string>();

    for (const watcher of this.#walletWatchers) {
      if (isWatcherReadyForNewActivities(watcher)) {
        for (const address of watcher.addresses) {
          watchedAddresses.add(address);
        }
      }
    }

    return watchedAddresses;
  }

  #startPing() {
    this.#stopPing?.();

    const pingIntervalId = setInterval(() => {
      this.#socket?.send({ operation: 'ping' });

      this.#cancelReconnect?.();
      this.#cancelReconnect = setCancellableTimeout(PONG_TIMEOUT, () => {
        this.#socket?.reconnect();
      });
    }, PING_INTERVAL);

    this.#stopPing = () => clearInterval(pingIntervalId);
  }

  /**
   * When a pending action is invalidated, a message arrives with no data except the normalized hash. In order to find
   * what addresses it belongs to and notify those addresses, we save the addresses from the previous message with the
   * same normalized hash.
   *
   * @returns The addresses that should be notified about the new actions, even if no new action belongs to the address
   */
  #rememberAddressesOfHash(
    messageHashNormalized: string,
    newActionAddresses: Iterable<string>,
    areNewActionsPending: boolean,
  ) {
    const prevSavedAddresses = this.#addressesByHash[messageHashNormalized] ?? [];
    const nextSavedAddresses: string[] = [];
    const addressesToNotify = new Set<string>();

    // Notifying the addresses where the actions were seen at previously. It is necessary to let the addresses know that
    // the given normalized message hash is no longer in the activity history.
    for (const address of prevSavedAddresses) {
      addressesToNotify.add(address);
    }

    for (const address of newActionAddresses) {
      addressesToNotify.add(address);

      // Saving the corresponding addresses only for pending actions, because confirmed actions don't change or invalidate
      if (areNewActionsPending) {
        nextSavedAddresses.push(address);
      }
    }

    if (nextSavedAddresses.length) {
      this.#addressesByHash[messageHashNormalized] = nextSavedAddresses;
    } else {
      delete this.#addressesByHash[messageHashNormalized];
    }

    return addressesToNotify;
  }
}

export type { ToncenterSocket };

/** Returns a singleton (one constant instance per a network) */
export const getToncenterSocket = withCache((network: ApiNetwork) => {
  return new ToncenterSocket(network);
});

/**
 * Returns true if the activities update is final, i.e. no other updates are expected for the corresponding message hash.
 */
export function isActivityUpdateFinal(update: ActivitiesUpdate) {
  return !update.arePending || !update.activities.length;
}

function getSocketUrl(network: ApiNetwork) {
  const url = new URL(NETWORK_CONFIG[network].toncenterUrl);
  url.protocol = 'wss:';
  url.pathname = '/api/streaming/v1/ws';
  addBackendHeadersToSocketUrl(url);
  return url;
}

async function parseSocketActions(network: ApiNetwork, message: ActionsSocketMessage, addressWhitelist: Set<string>) {
  const actionsByAddress = groupActionsByAddress(message.actions, message.address_book);
  const activitiesByAddress: Record<string, ApiActivity[]> = {};
  const nftSuperCollectionsByCollectionAddress = await getNftSuperCollectionsByCollectionAddress();

  for (const [address, actions] of Object.entries(actionsByAddress)) {
    if (!addressWhitelist.has(address)) {
      continue;
    }

    activitiesByAddress[address] = parseActions(actions, {
      network,
      walletAddress: address,
      addressBook: message.address_book,
      metadata: message.metadata,
      nftSuperCollectionsByCollectionAddress,
      isPending: message.type === 'pending_actions',
    })[0].activities;
  }

  return activitiesByAddress;
}

function groupActionsByAddress(actions: AnyAction[], addressBook: AddressBook) {
  const byAddress: Record<string, AnyAction[]> = {};

  for (const action of actions) {
    for (const rawAddress of action.accounts!) {
      const address = addressBook[rawAddress]?.user_friendly ?? rawAddress;
      byAddress[address] ??= [];
      byAddress[address].push(action);
    }
  }

  return byAddress;
}

function isWatcherReady(watcher: WalletWatcherInternal) {
  // Even though the socket may already listen to some wallet addresses, we promise the class users to trigger the
  // callbacks only in the connected state.
  return watcher.isConnected;
}

function isWatcherReadyForNewActivities(
  watcher: WalletWatcherInternal,
): watcher is WalletWatcherInternal & { onNewActivities: NewActivitiesCallback } {
  return isWatcherReady(watcher) && !!watcher.onNewActivities;
}
