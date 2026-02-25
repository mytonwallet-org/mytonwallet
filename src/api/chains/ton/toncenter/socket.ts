import type {
  ActivitiesUpdate,
  NewActivitiesCallback,
  WalletWatcherInternal,
} from '../../../common/websocket/abstractWsClient';
import type { ApiActivity, ApiNetwork } from '../../../types';
import type {
  AccountStateChangeSocketMessage,
  ActionsSocketMessage,
  AddressBook,
  AnyAction,
  ClientSocketMessage,
  JettonChangeSocketMessage,
  ServerSocketMessage,
  SocketFinality,
  SocketSubscriptionEvent,
  StatusSocketMessage,
} from './types';

import { TONCENTER_ACTIONS_VERSION } from '../../../../config';
import { logDebug } from '../../../../util/logs';
import { type InMessageCallback } from '../../../../util/reconnectingWebsocket';
import safeExec from '../../../../util/safeExec';
import { forbidConcurrency, setCancellableTimeout } from '../../../../util/schedulers';
import withCache from '../../../../util/withCache';
import { areAddressesEqual, toBase64Address } from '../util/tonCore';
import { getNftSuperCollectionsByCollectionAddress } from '../../../common/addresses';
import { addBackendHeadersToSocketUrl } from '../../../common/backend';
import { AbstractWebsocketClient } from '../../../common/websocket/abstractWsClient';
import { SEC } from '../../../constants';
import { NETWORK_CONFIG } from '../constants';
import { parseActions } from './actions';

// Toncenter closes the socket after 30 seconds of inactivity
const PING_INTERVAL = 20 * SEC;

// When the internet connection is interrupted, the Toncenter socket doesn't always disconnect automatically.
// Disconnecting manually if there is no response for "ping".
const PONG_TIMEOUT = 5 * SEC;

/**
 * Connects to Toncenter to passively listen to updates.
 */
class ToncenterSocket extends AbstractWebsocketClient<ClientSocketMessage, ServerSocketMessage> {
  #network: ApiNetwork;

  /** See #rememberAddressesOfNormalizedHash */
  #addressesByHash: Record<string, string[]> = {};

  #stopPing?: NoneToVoidFunction;
  #cancelReconnect?: NoneToVoidFunction;

  constructor(network: ApiNetwork) {
    super(getSocketUrl(network));
    this.#network = network;
  }

  protected handleSocketMessage: InMessageCallback<ServerSocketMessage> = (message) => {
    this.#cancelReconnect?.();

    if ('status' in message) {
      if (message.status === 'subscribed') {
        this.#handleSubscribed(message);
      }
      return;
    }

    switch (message.type) {
      case 'trace_invalidated':
        logDebug('toncenter: trace invalidated', { hash: message.trace_external_hash_norm });

        // Notify watchers about the invalidation so they can re-fetch balances.
        // Balance updates from `confirmed` finality level may be stale after invalidation.
        this.#notifyTraceInvalidation(message.trace_external_hash_norm);

        // Create an empty actions message to clear the activities for this trace
        void this.#handleNewActions({
          type: 'actions',
          finality: 'finalized',
          trace_external_hash_norm: message.trace_external_hash_norm,
          actions: [],
          address_book: {},
          metadata: {},
        } satisfies ActionsSocketMessage);
        break;
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

  protected handleSocketConnect = () => {
    this.sendWatchedWalletsToSocket();

    this.#startPing();
  };

  protected handleSocketDisconnect = () => {
    this.#stopPing?.();

    for (const watcher of this.walletWatchers) {
      if (watcher.isConnected) {
        watcher.isConnected = false;
        if (watcher.onDisconnect) safeExec(watcher.onDisconnect);
      }
    }
  };

  #handleSubscribed(message: StatusSocketMessage) {
    for (const watcher of this.walletWatchers) {
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

    for (const watcher of this.walletWatchers) {
      if (!this.#isWatcherReadyForNewActivities(watcher)) {
        continue;
      }

      for (const wallet of watcher.wallets) {
        if (!addressesToNotify.has(wallet.address)) {
          continue;
        }

        safeExec(() => watcher.onNewActivities({
          address: wallet.address,
          messageHashNormalized,
          finality: message.finality,
          activities: activitiesByAddress[wallet.address] ?? [],
        }));
      }
    }
  });

  #handleAccountStateChange(message: AccountStateChangeSocketMessage) {
    this.#notifyBalanceUpdate(
      message.account,
      undefined,
      BigInt(message.state.balance),
      message.finality,
    );
  }

  #handleJettonChange(message: JettonChangeSocketMessage) {
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
    for (const watcher of this.walletWatchers) {
      const { onBalanceUpdate } = watcher;

      if (!this.isWatcherReady(watcher) || !onBalanceUpdate) {
        continue;
      }

      for (const wallet of watcher.wallets) {
        if (!areAddressesEqual(wallet.address, rawAddress)) {
          continue;
        }

        safeExec(() => onBalanceUpdate({
          address: wallet.address,
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

    for (const watcher of this.walletWatchers) {
      const { onTraceInvalidated } = watcher;

      if (!this.isWatcherReady(watcher) || !onTraceInvalidated) {
        continue;
      }

      const hasAffectedAddress = watcher.wallets.some((watchedWallet) =>
        affectedAddresses.some((affected) => areAddressesEqual(watchedWallet.address, affected)),
      );

      if (hasAffectedAddress) {
        safeExec(onTraceInvalidated);
      }
    }
  }

  protected sendWatchedWalletsToSocket = () => {
    // It's necessary to collect the watched addresses synchronously with locking the request id.
    // It makes sure that all the watchers with ids < the response id will be subscribed.
    const addresses = this.#getWatchedAddresses();
    const requestId = String(this.currentUniqueId++);

    // It's necessary to send a `subscribe` request on every `#sendWatchedWalletsToSocket` call, even if the list
    // of addresses hasn't changed. Otherwise, the mechanism turning `isConnected` to `true` in the watchers will break
    // if a new watcher containing only existing addresses is added.
    this.socket!.send({
      operation: 'subscribe',
      id: requestId,
      addresses,
      types: this.#getSubscriptionTypes(),
      min_finality: 'pending',
      include_address_book: true,
      include_metadata: true,
      supported_action_types: [TONCENTER_ACTIONS_VERSION],
    });
  };

  #getWatchedAddresses() {
    const addresses = new Set<string>();
    for (const watcher of this.walletWatchers) {
      for (const wallet of watcher.wallets) {
        addresses.add(wallet.address);
      }
    }
    return [...addresses];
  }

  /** Returns subscription types for the streaming API (uses `min_finality`) */
  #getSubscriptionTypes() {
    let shouldSubscribeActions = false;
    let shouldSubscribeBalances = false;

    for (const watcher of this.walletWatchers) {
      if (watcher.onNewActivities) {
        shouldSubscribeActions = true;
      }
      if (watcher.onBalanceUpdate) {
        shouldSubscribeBalances = true;
      }
    }

    const types: SocketSubscriptionEvent[] = [];
    if (shouldSubscribeActions) {
      types.push('actions');
    }
    if (shouldSubscribeBalances) {
      types.push('account_state_change', 'jettons_change');
    }

    return types;
  }

  #getAddressesReadyForActivities() {
    const watchedAddresses = new Set<string>();

    for (const watcher of this.walletWatchers) {
      if (this.#isWatcherReadyForNewActivities(watcher)) {
        for (const wallet of watcher.wallets) {
          watchedAddresses.add(wallet.address);
        }
      }
    }

    return watchedAddresses;
  }

  #startPing() {
    this.#stopPing?.();

    const pingIntervalId = setInterval(() => {
      this.socket?.send({ operation: 'ping' });

      this.#cancelReconnect?.();
      this.#cancelReconnect = setCancellableTimeout(PONG_TIMEOUT, () => {
        this.socket?.reconnect();
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

  #isWatcherReadyForNewActivities(
    watcher: WalletWatcherInternal,
  ): watcher is WalletWatcherInternal & { onNewActivities: NewActivitiesCallback } {
    return this.isWatcherReady(watcher) && !!watcher.onNewActivities;
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

function getSocketUrl(network: ApiNetwork) {
  const url = new URL(NETWORK_CONFIG[network].toncenterUrl);
  url.protocol = 'wss:';
  url.pathname = '/api/streaming/v2/ws';
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
