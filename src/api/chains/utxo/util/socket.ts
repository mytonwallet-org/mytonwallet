import type {
  DefaultNftUpdateArgument,
  InMessageCallback,
} from '../../../common/websocket/abstractWsClient';
import type { ApiNetwork, UTXOChain } from '../../../types';
import type {
  UtxoActivitiesUpdate,
  UtxoSocketAddressEvent,
  UtxoSocketClientMessage,
  UtxoSocketServerMessage,
  UtxoSocketSubscribeResult,
  UtxoWatchedWallet,
} from '../types';

import safeExec from '../../../../util/safeExec';
import withCache from '../../../../util/withCache';
import { AbstractWebsocketClient } from '../../../common/websocket/abstractWsClient';
import { parseUtxoTransaction } from '../activities';
import { isSameUtxoAddress, toUtxoApiAddress } from '../address';
import { UTXO_RPC_URLS } from '../constants';
import { getWalletBalance } from '../wallet';

class UtxoSocket extends AbstractWebsocketClient<
  UtxoSocketClientMessage,
  UtxoSocketServerMessage,
  UtxoWatchedWallet,
  UtxoActivitiesUpdate,
  DefaultNftUpdateArgument
> {
  #network: ApiNetwork;
  #chain: UTXOChain;

  constructor(network: ApiNetwork, chain: UTXOChain) {
    super(getSocketUrl(network, chain));
    this.#network = network;
    this.#chain = chain;
  }

  protected handleSocketMessage: InMessageCallback<UtxoSocketServerMessage> = (message) => {
    if (isSubscribeResult(message)) {
      this.#handleSubscriptionReady();
      return;
    }

    if (!isAddressEvent(message)) {
      return;
    }

    void this.#handleAddressEvent(message);
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

  protected sendWatchedWalletsToSocket = () => {
    if (!this.socket?.isConnected) {
      return;
    }

    const addresses = [...new Set(
      this.walletWatchers
        .filter((watcher) => watcher.onBalanceUpdate || watcher.onNewActivities)
        .flatMap((watcher) => watcher.wallets.map((wallet) => (
          toUtxoApiAddress(this.#chain, this.#network, wallet.address)
        ))),
    )];

    if (!addresses.length) {
      return;
    }

    const requestId = String(this.currentUniqueId++);

    this.socket.send({
      id: requestId,
      method: 'subscribeAddresses',
      params: {
        addresses,
      },
    });
  };

  #handleSubscriptionReady() {
    for (const watcher of this.walletWatchers) {
      if (watcher.isConnected || (!watcher.onBalanceUpdate && !watcher.onNewActivities)) {
        continue;
      }

      watcher.isConnected = true;
      if (watcher.onConnect) safeExec(watcher.onConnect);
    }
  }

  async #handleAddressEvent(message: UtxoSocketAddressEvent) {
    const { address, tx } = message.data;
    const finality = (tx.confirmations ?? 0) > 0 ? 'confirmed' as const : 'pending' as const;

    for (const watcher of this.walletWatchers) {
      if (!this.isWatcherReady(watcher)) {
        continue;
      }

      for (const wallet of watcher.wallets) {
        if (!isSameUtxoAddress(this.#chain, this.#network, wallet.address, address)) {
          continue;
        }

        if (watcher.onNewActivities) {
          const activity = parseUtxoTransaction(this.#chain, this.#network, wallet.address, tx);

          if (!activity.shouldHide) {
            safeExec(() => watcher.onNewActivities!({
              address: wallet.address,
              activities: [activity],
            }));
          }
        }

        if (!watcher.onBalanceUpdate) {
          continue;
        }

        try {
          const balance = await getWalletBalance(this.#chain, this.#network, wallet.address);
          watcher.onBalanceUpdate({
            address: wallet.address,
            balance,
            finality,
          });
        } catch {
          // Balance re-fetch failed; fallback polling will reconcile.
        }
      }
    }
  }
}

function isSubscribeResult(message: UtxoSocketServerMessage): message is UtxoSocketSubscribeResult {
  return 'data' in message && 'subscribed' in message.data;
}

function isAddressEvent(message: UtxoSocketServerMessage): message is UtxoSocketAddressEvent {
  return 'data' in message && 'address' in message.data && 'tx' in message.data;
}

function getSocketUrl(network: ApiNetwork, chain: UTXOChain) {
  const url = new URL(UTXO_RPC_URLS[network](chain));
  url.protocol = 'wss:';

  return url;
}

export const getUtxoSocket = withCache((network: ApiNetwork, chain: UTXOChain) => {
  return new UtxoSocket(network, chain);
});

export type { UtxoSocket };
