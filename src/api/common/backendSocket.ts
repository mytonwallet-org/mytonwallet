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
import safeExec from '../../util/safeExec';
import withCache from '../../util/withCache';
import { AbstractWebsocketClient } from './websocket/abstractWsClient';
import { addBackendHeadersToSocketUrl } from './backend';

interface ExtendedWatchedWallet {
  chain: ApiChain;
  events: ApiSocketEventType[];
  address: string;
}

/**
 * Connects to the MTW backend to passively listen to updates.
 */
class BackendSocket extends AbstractWebsocketClient<
  ApiClientSocketMessage,
  ApiServerSocketMessage,
  ExtendedWatchedWallet,
  { address: string }
> {
  constructor(network: ApiNetwork) {
    super(getSocketUrl(network));
  }

  protected handleSocketMessage: InMessageCallback<ApiServerSocketMessage> = (message) => {
    switch (message.type) {
      case 'subscribed':
        this.#handleSubscribed(message);
        break;
      case 'newActivity':
        this.#handleNewActivity(message);
        break;
    }
  };

  protected handleSocketConnect = () => {
    this.sendWatchedWalletsToSocket();
  };

  protected handleSocketDisconnect = () => {
    for (const watcher of this.walletWatchers) {
      if (watcher.isConnected) {
        watcher.isConnected = false;
        if (watcher.onDisconnect) safeExec(watcher.onDisconnect);
      }
    }
  };

  #handleSubscribed(message: ApiSubscribedSocketMessage) {
    for (const watcher of this.walletWatchers) {
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

    for (const { wallets, isConnected, onNewActivities } of this.walletWatchers) {
      // Even though the socket may already listen to some wallet addresses, we promise the class users to trigger the
      // onNewActivity callback only in the connected state.
      if (!isConnected || !onNewActivities) {
        continue;
      }

      for (const wallet of wallets) {
        const doesWalletMatch = (
          wallet.chain === message.chain
          && messageAddresses.has(wallet.address)
          && wallet.events.includes('activity')
        );

        if (doesWalletMatch) {
          safeExec(() => onNewActivities({ address: wallet.address }));
        }
      }
    }
  }

  protected sendWatchedWalletsToSocket = () => {
    // It's necessary to collect the watched addresses synchronously with locking the request id.
    // It makes sure that all the watchers with ids < the response id will be subscribed.
    const addresses = this.#getWatchedAddresses(['activity']);
    const requestId = this.currentUniqueId++;

    // It's necessary to send a `subscribe` request on every `#sendWatchedWalletsToSocket` call, even if the list of
    // addresses hasn't changed. Otherwise, the mechanism turning `isConnected` to `true` in the watchers will break if
    // a new watcher containing only existing addresses is added.
    this.socket!.send({
      type: 'subscribe',
      id: requestId,
      addresses: addresses.map((address) => ({
        ...address,
        events: ['activity'],
      })),
    });
  };

  /** Collects the addresses (grouped by chain) from the current watchers */
  #getWatchedAddresses(events: ApiSocketEventType[]) {
    const addresses: { chain: ApiChain; address: string }[] = [];

    for (const watcher of this.walletWatchers) {
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
