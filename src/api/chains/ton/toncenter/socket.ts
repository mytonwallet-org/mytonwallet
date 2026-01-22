import type { ApiActivity, ApiNetwork } from '../../../types';
import type {
  AccountStateChangeSocketMessageV2,
  ActionsSocketMessageV2,
  AddressBook,
  AnyAction,
  ClientSocketMessage,
  JettonChangeSocketMessageV2,
  RawServerSocketMessage,
  ServerSocketMessage,
  SetSubscriptionSocketMessageV1,
  SocketFinality,
  SocketSubscriptionEventV1,
  SocketSubscriptionEventV2,
} from './types';

import { TONCENTER_ACTIONS_VERSION } from '../../../../config';
import { logDebug } from '../../../../util/logs';
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
  /**
   * Called when a trace is invalidated. This means any balance updates received from `confirmed` finality level
   * for this trace may be stale and should trigger a balance re-fetch.
   *
   * Note: The V2 streaming API doesn't provide corrected balance updates on trace invalidation,
   * so we must re-poll to get accurate balances.
   */
  onTraceInvalidated?: TraceInvalidatedCallback;
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
   * must be removed from the app state.
   *
   * Activities progress through finality levels: pending → confirmed/signed → finalized (or get invalidated).
   * Only finalized activities (status='completed'/'failed') are guaranteed to never change or be invalidated.
   */
  messageHashNormalized: string;
  finality: SocketFinality;
  /** The activities may be unsorted */
  activities: ApiActivity[];
}

export type BalanceUpdateCallback = (update: BalanceUpdate) => void;

export type TraceInvalidatedCallback = NoneToVoidFunction;

export interface BalanceUpdate {
  address: string;
  /** `undefined` for TON */
  tokenAddress?: string;
  balance: bigint;
  finality: SocketFinality;
}

/**
 * Connects to Toncenter to passively listen to updates.
 */
class ToncenterSocket {
  #network: ApiNetwork;

  #socket?: ReconnectingWebSocket<ClientSocketMessage, RawServerSocketMessage>;

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
      onTraceInvalidated,
      onConnect,
      onDisconnect,
    }: Pick<
      WalletWatcherInternal,
      'onNewActivities' | 'onBalanceUpdate' | 'onTraceInvalidated' | 'onConnect' | 'onDisconnect'
    > = {},
  ): WalletWatcher {
    const id = this.#currentUniqueId++;
    const watcher: WalletWatcherInternal = {
      id,
      addresses,
      // The status will turn to `true` via `#actualizeSocket` → `#sendWatchedWalletsToSocket` → socket request → socket response → `#handleSubscriptionSet`
      isConnected: false,
      onNewActivities,
      onBalanceUpdate,
      onTraceInvalidated,
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
    const socket = new ReconnectingWebSocket<ClientSocketMessage, RawServerSocketMessage>(url);
    socket.onMessage(this.#handleSocketMessage);
    socket.onConnect(this.#handleSocketConnect);
    socket.onDisconnect(this.#handleSocketDisconnect);
    return socket;
  }

  #handleSocketMessage: InMessageCallback<RawServerSocketMessage> = (rawMessage) => {
    this.#cancelReconnect?.();

    if ('status' in rawMessage) {
      if (rawMessage.status === 'subscribed' || rawMessage.status === 'subscription_set') {
        this.#handleSubscribed(rawMessage);
      }
      return;
    }

    if (!('type' in rawMessage)) {
      return;
    }

    // Handle `trace_invalidated` first (before normalization) since it has a different structure
    if (rawMessage.type === 'trace_invalidated') {
      logDebug('toncenter: trace invalidated', { hash: rawMessage.trace_external_hash_norm });

      // Notify watchers about the invalidation so they can re-fetch balances.
      // Balance updates from `confirmed` finality level may be stale after invalidation.
      this.#notifyTraceInvalidation(rawMessage.trace_external_hash_norm);

      // Create an empty actions message to clear the activities for this trace
      const emptyActionsMessage: ActionsSocketMessageV2 = {
        type: 'actions',
        finality: 'finalized',
        trace_external_hash_norm: rawMessage.trace_external_hash_norm,
        actions: [],
        address_book: {},
        metadata: {},
      };
      void this.#handleNewActions(emptyActionsMessage);
      return;
    }

    // Normalize V1 messages to V2 format (add finality field)
    const message = normalizeServerMessage(rawMessage);

    switch (message.type) {
      case 'actions':
        void this.#handleNewActions(message);
        break;
      case 'account_state_change':
        this.#handleAccountStateChange(message);
        break;
      case 'jettons_change':
        this.#handleJettonChange(message);
        break;
    }
  };

  #handleSocketConnect = () => {
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
  #handleNewActions = forbidConcurrency(async (message: ActionsSocketMessageV2) => {
    if (message.finality === 'confirmed') {
      logDebug('toncenter: trace confirmed (shard)', { hash: message.trace_external_hash_norm });
    } else if (message.finality === 'finalized') {
      logDebug('toncenter: trace finalized', { hash: message.trace_external_hash_norm });
    }
    const messageHashNormalized = message.trace_external_hash_norm;
    const activitiesByAddress = await parseSocketActions(
      this.#network,
      message,
      this.#getAddressesReadyForActivities(),
    );
    const addressesToNotify = this.#rememberAddressesOfHash(
      messageHashNormalized,
      Object.keys(activitiesByAddress),
      message.finality,
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
          finality: message.finality,
          activities: activitiesByAddress[address] ?? [],
        }));
      }
    }
  });

  #handleAccountStateChange(message: AccountStateChangeSocketMessageV2) {
    logDebug('toncenter: account balance update', {
      address: message.account,
      balance: message.state.balance,
      finality: message.finality,
    });
    this.#notifyBalanceUpdate(
      message.account,
      undefined,
      BigInt(message.state.balance),
      message.finality,
    );
  }

  #handleJettonChange(message: JettonChangeSocketMessageV2) {
    logDebug('toncenter: jetton balance update', {
      owner: message.jetton.owner,
      jettonWallet: message.jetton.address,
      token: message.jetton.jetton,
      balance: message.jetton.balance,
      finality: message.finality,
    });
    this.#notifyBalanceUpdate(
      message.jetton.owner,
      toBase64Address(message.jetton.jetton, true, this.#network),
      BigInt(message.jetton.balance),
      message.finality,
    );
  }

  #notifyBalanceUpdate(
    rawAddress: string,
    tokenBase64Address: string | undefined,
    balance: bigint,
    finality: SocketFinality,
  ) {
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
          finality,
        }));
      }
    }
  }

  #notifyTraceInvalidation(messageHashNormalized: string) {
    const affectedAddresses = this.#addressesByHash[messageHashNormalized] ?? [];
    if (!affectedAddresses.length) {
      return;
    }

    for (const watcher of this.#walletWatchers) {
      const { onTraceInvalidated } = watcher;

      if (!isWatcherReady(watcher) || !onTraceInvalidated) {
        continue;
      }

      const hasAffectedAddress = watcher.addresses.some((watchedAddress) =>
        affectedAddresses.some((affected) => areAddressesEqual(watchedAddress, affected)),
      );

      if (hasAffectedAddress) {
        safeExec(onTraceInvalidated);
      }
    }
  }

  #sendWatchedWalletsToSocket() {
    // It's necessary to collect the watched addresses synchronously with locking the request id.
    // It makes sure that all the watchers with ids < the response id will be subscribed.
    const addresses = this.#getWatchedAddresses();
    const requestId = String(this.#currentUniqueId++);
    const isV2 = isStreamingApiV2(this.#network);

    // It's necessary to send a `subscribe` request on every `#sendWatchedWalletsToSocket` call, even if the list
    // of addresses hasn't changed. Otherwise, the mechanism turning `isConnected` to `true` in the watchers will break
    // if a new watcher containing only existing addresses is added.
    if (isV2) {
      // V2: `include_address_book` and `include_metadata` are part of subscribe
      this.#socket!.send({
        operation: 'subscribe',
        id: requestId,
        addresses,
        types: this.#getSubscriptionTypesV2(),
        min_finality: 'pending',
        include_address_book: true,
        include_metadata: true,
        supported_action_types: [TONCENTER_ACTIONS_VERSION],
      });
    } else {
      // V1: Send configure first to set options, then set_subscription for snapshot semantics
      // `configure` sets options like `include_address_book` for all subsequent messages
      this.#socket!.send({
        operation: 'configure',
        include_address_book: true,
        include_metadata: true,
        supported_action_types: [TONCENTER_ACTIONS_VERSION],
      });
      // V1 `set_subscription` replaces entire subscription (snapshot semantics like V2)
      // and supports per-address event type granularity
      const setSubscriptionMessage = this.#buildSetSubscriptionMessageV1(requestId);
      logDebug('toncenter: V1 set_subscription message', setSubscriptionMessage);
      this.#socket!.send(setSubscriptionMessage);
    }
  }

  #doesHaveWatchedAddresses() {
    return this.#walletWatchers.some((watcher) => watcher.addresses.length);
  }

  #getWatchedAddresses() {
    const addresses = new Set<string>();
    for (const watcher of this.#walletWatchers) {
      for (const address of watcher.addresses) {
        addresses.add(address);
      }
    }
    return [...addresses];
  }

  /** Returns subscription types for V2 API (uses `min_finality`) */
  #getSubscriptionTypesV2() {
    let shouldSubscribeActions = false;
    let shouldSubscribeBalances = false;

    for (const watcher of this.#walletWatchers) {
      if (watcher.onNewActivities) {
        shouldSubscribeActions = true;
      }
      if (watcher.onBalanceUpdate) {
        shouldSubscribeBalances = true;
      }
    }

    const types: SocketSubscriptionEventV2[] = [];
    if (shouldSubscribeActions) {
      types.push('actions');
    }
    if (shouldSubscribeBalances) {
      types.push('account_state_change', 'jettons_change');
    }

    return types;
  }

  /**
   * Builds a V1 `set_subscription` message with per-address event type granularity.
   * Unlike V2 which has global `types`, V1 `set_subscription` allows different event types per address.
   * This also provides snapshot semantics - removed addresses stop streaming immediately.
   * V1 API expects addresses as keys.
   */
  #buildSetSubscriptionMessageV1(requestId: string): SetSubscriptionSocketMessageV1 {
    const subscriptionMap: Record<string, Set<SocketSubscriptionEventV1>> = {};

    for (const watcher of this.#walletWatchers) {
      const watcherTypes: SocketSubscriptionEventV1[] = [];
      if (watcher.onNewActivities) {
        watcherTypes.push('pending_actions', 'actions');
      }
      if (watcher.onBalanceUpdate) {
        watcherTypes.push('account_state_change', 'jettons_change');
      }

      for (const address of watcher.addresses) {
        subscriptionMap[address] ??= new Set();
        for (const type of watcherTypes) {
          subscriptionMap[address].add(type);
        }
      }
    }

    // Convert Sets to arrays for the message
    const message: SetSubscriptionSocketMessageV1 = {
      operation: 'set_subscription',
      id: requestId,
      subscriptions: {},
    };
    for (const [address, types] of Object.entries(subscriptionMap)) {
      message.subscriptions[address] = [...types];
    }

    return message;
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
   * When a non-final trace is invalidated, a message arrives with no data except the normalized hash. In order to find
   * what addresses it belongs to and notify those addresses, we save the addresses from the previous message with the
   * same normalized hash until the trace is finalized.
   *
   * @returns The addresses that should be notified about the new actions, even if no new action belongs to the address
   */
  #rememberAddressesOfHash(
    messageHashNormalized: string,
    newActionAddresses: Iterable<string>,
    finality: SocketFinality,
  ) {
    const prevSavedAddresses = this.#addressesByHash[messageHashNormalized] ?? [];
    const nextSavedAddresses: string[] = [];
    const addressesToNotify = new Set<string>();
    const shouldRemember = finality !== 'finalized';

    // Notifying the addresses where the actions were seen at previously. It is necessary to let the addresses know that
    // the given normalized message hash is no longer in the activity history.
    for (const address of prevSavedAddresses) {
      addressesToNotify.add(address);
    }

    for (const address of newActionAddresses) {
      addressesToNotify.add(address);

      // Save addresses until the trace reaches finality so invalidations can clear previous versions
      if (shouldRemember) {
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
  return update.finality === 'finalized' || !update.activities.length;
}

function isStreamingApiV2(network: ApiNetwork) {
  return network === 'testnet';
}

function getSocketUrl(network: ApiNetwork) {
  const url = new URL(NETWORK_CONFIG[network].toncenterUrl);
  url.protocol = 'wss:';
  url.pathname = isStreamingApiV2(network) ? '/api/streaming/v2/ws' : '/api/streaming/v1/ws';
  addBackendHeadersToSocketUrl(url);
  return url;
}

type NormalizableMessage = Exclude<RawServerSocketMessage, { status: any } | { type: 'trace_invalidated' }>;

/**
 * Normalizes V1 socket messages to V2 format by adding the `finality` field.
 * V1 uses separate message types (`pending_actions` vs `actions`) to indicate finality,
 * while V2 uses a single type with an explicit finality field.
 *
 * Note: This function should NOT be called for `trace_invalidated` messages or status messages.
 */
function normalizeServerMessage(message: NormalizableMessage): Exclude<ServerSocketMessage, { status: any }> {
  if (message.type === 'pending_actions') {
    return {
      id: message.id,
      type: 'actions',
      finality: 'pending',
      trace_external_hash_norm: message.trace_external_hash_norm,
      actions: message.actions,
      address_book: message.address_book,
      metadata: message.metadata,
    } satisfies ActionsSocketMessageV2 as ActionsSocketMessageV2;
  }

  if (message.type === 'actions' && !('finality' in message)) {
    return {
      id: message.id,
      type: 'actions',
      finality: 'finalized',
      trace_external_hash_norm: message.trace_external_hash_norm,
      actions: message.actions,
      address_book: message.address_book,
      metadata: message.metadata,
    } satisfies ActionsSocketMessageV2 as ActionsSocketMessageV2;
  }

  if (message.type === 'account_state_change' && !('finality' in message)) {
    return {
      id: message.id,
      type: 'account_state_change',
      finality: 'finalized',
      account: message.account,
      state: message.state,
    } satisfies AccountStateChangeSocketMessageV2 as AccountStateChangeSocketMessageV2;
  }

  if (message.type === 'jettons_change' && !('finality' in message)) {
    return {
      id: message.id,
      type: 'jettons_change',
      finality: 'finalized',
      jetton: message.jetton,
      address_book: message.address_book,
      metadata: message.metadata,
    } satisfies JettonChangeSocketMessageV2 as JettonChangeSocketMessageV2;
  }

  // Already in V2 format
  return message as any;
}

async function parseSocketActions(network: ApiNetwork, message: ActionsSocketMessageV2, addressWhitelist: Set<string>) {
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
      isPending: message.finality === 'pending',
      finality: message.finality,
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
