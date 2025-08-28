import type { ApiActivity, ApiNetwork } from '../../../types';
import type { ActionsSocketMessage, AddressBook, AnyAction, ClientSocketMessage, ServerSocketMessage } from './types';

import { TONCENTER_ACTIONS_VERSION, TONCENTER_MAINNET_URL, TONCENTER_TESTNET_URL } from '../../../../config';
import { findDifference } from '../../../../util/iteratees';
import ReconnectingWebSocket, { type InMessageCallback } from '../../../../util/reconnectingWebsocket';
import safeExec from '../../../../util/safeExec';
import { forbidConcurrency, setCancellableTimeout, throttle } from '../../../../util/schedulers';
import { getNftSuperCollectionsByCollectionAddress } from '../../../common/addresses';
import { addBackendHeadersToSocketUrl } from '../../../common/backend';
import { SEC } from '../../../constants';
import { parseActions } from './actions';

const ACTUALIZATION_DELAY = 10;

// Toncenter closes the socket after 30 seconds of inactivity
const PING_INTERVAL = 20 * SEC;

// When the internet connection is interrupted, the Toncenter socket doesn't always disconnect automatically.
// Disconnecting manually if there is no response for "ping".
const PONG_TIMEOUT = 5 * SEC;

const toncenterSockets: Partial<Record<ApiNetwork, ToncenterSocket>> = {};

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
   * Called only when isConnected is true. Therefore, when the socket reconnects, the users should synchronize,
   * otherwise the activities arriving during the reconnect will miss.
   */
  onNewActivities?: NewActivitiesCallback;
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

/**
 * Connects to Toncenter to passively listen to updates.
 */
class ToncenterSocket {
  #network: ApiNetwork;

  #socket?: ReconnectingWebSocket<ClientSocketMessage, ServerSocketMessage>;

  /** See #rememberAddressesOfNormalizedHash */
  #addressesByHash: Record<string, string[]> = {};

  #walletWatchers: WalletWatcherInternal[] = [];

  /** The addresses that the socket is currently subscribed to */
  #subscribedAddresses = new Set<string>();

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
      onConnect,
      onDisconnect,
    }: Pick<WalletWatcherInternal, 'onNewActivities' | 'onConnect' | 'onDisconnect'> = {},
  ): WalletWatcher {
    const id = this.#currentUniqueId++;
    const watcher: WalletWatcherInternal = {
      id,
      addresses,
      isConnected: false,
      onNewActivities,
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
      if (message.status === 'subscribed') {
        this.#handleSubscribed(message);
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
        // Falling down to the below `if` intentionally
      }

      if (message.type === 'actions' || message.type === 'pending_actions') {
        void this.#handleNewActions(message);
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
    this.#subscribedAddresses.clear();
    this.#stopPing?.();

    for (const watcher of this.#walletWatchers) {
      if (watcher.isConnected) {
        watcher.isConnected = false;
        if (watcher.onDisconnect) safeExec(watcher.onDisconnect);
      }
    }
  };

  #handleSubscribed(message: Extract<ServerSocketMessage, { status: any }>) {
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
    const activitiesByAddress = await parseSocketActions(this.#network, message, this.#getWatchedAddresses(true));
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

  #sendWatchedWalletsToSocket() {
    // It's necessary to collect the watched addresses synchronously with locking the request id.
    // It makes sure that all the watchers with ids < the response id will be subscribed.
    const requestId = String(this.#currentUniqueId++);

    const oldAddresses = this.#subscribedAddresses;
    const newAddresses = this.#getWatchedAddresses();
    const deletedAddresses = findDifference(oldAddresses, newAddresses);
    const addedAddresses = findDifference(newAddresses, oldAddresses);

    if (deletedAddresses.length) {
      this.#socket!.send({
        operation: 'unsubscribe',
        addresses: deletedAddresses,
      });
    }

    if (addedAddresses.length) {
      this.#socket!.send({
        operation: 'subscribe',
        id: requestId,
        addresses: addedAddresses,
        types: ['actions', 'pending_actions'],
      });
    }

    this.#subscribedAddresses = newAddresses;
  }

  #doesHaveWatchedAddresses() {
    return this.#walletWatchers.some((watcher) => watcher.addresses.length);
  }

  #getWatchedAddresses(isOnlyReadyForNewActivities?: boolean) {
    const watchedAddresses = new Set<string>();

    for (const watcher of this.#walletWatchers) {
      if (isOnlyReadyForNewActivities && !isWatcherReadyForNewActivities(watcher)) {
        continue;
      }

      for (const address of watcher.addresses) {
        watchedAddresses.add(address);
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
export function getToncenterSocket(network: ApiNetwork) {
  toncenterSockets[network] ??= new ToncenterSocket(network);
  return toncenterSockets[network];
}

/**
 * Returns true if the activities update is final, i.e. no other updates are expected for the corresponding message hash.
 */
export function isActivityUpdateFinal(update: ActivitiesUpdate) {
  return !update.arePending || !update.activities.length;
}

function getSocketUrl(network: ApiNetwork) {
  const url = new URL(network === 'testnet' ? TONCENTER_TESTNET_URL : TONCENTER_MAINNET_URL);
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

    activitiesByAddress[address] = parseActions(
      network,
      address,
      actions,
      message.address_book,
      message.metadata,
      nftSuperCollectionsByCollectionAddress,
      message.type === 'pending_actions',
    );
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

function isWatcherReadyForNewActivities(
  watcher: WalletWatcherInternal,
): watcher is WalletWatcherInternal & { onNewActivities: NewActivitiesCallback } {
  // Even though the socket may already listen to some wallet addresses, we promise the class users to trigger the
  // onNewActions callback only in the connected state.
  return watcher.isConnected && !!watcher.onNewActivities;
}
