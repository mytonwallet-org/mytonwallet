import type { InMessageCallback } from '../../../common/websocket/abstractWsClient';
import type { ApiNetwork } from '../../../types';
import type { ClientSocketMessage, ServerSocketMessage, UnsubscribeMethod } from '../types';

import safeExec from '../../../../util/safeExec';
import { setCancellableTimeout } from '../../../../util/schedulers';
import withCache from '../../../../util/withCache';
import { AbstractWebsocketClient } from '../../../common/websocket/abstractWsClient';
import { SEC } from '../../../constants';
import { NETWORK_CONFIG, SOLANA_PROGRAM_IDS } from '../constants';

type Subscription = {
  type: 'native' | 'token-legacy' | 'token-2022' | 'nft';
  address: string;
  watcherId: number;
  subId?: number;
};

const PING_INTERVAL = 60 * SEC;

const PONG_TIMEOUT = 5 * SEC;

class HeliusSocket extends AbstractWebsocketClient<ClientSocketMessage, ServerSocketMessage> {
  #subscriptions = new Map<string, Subscription>();

  #stopPing?: NoneToVoidFunction;
  #cancelReconnect?: NoneToVoidFunction;

  constructor(network: ApiNetwork) {
    super(getSocketUrl(network));
  }

  protected handleSocketMessage: InMessageCallback<ServerSocketMessage> = (message) => {
    this.#cancelReconnect?.();

    if ('result' in message) {
      const sub = this.#subscriptions.get(message.id);
      if (sub) {
        this.#subscriptions.set(message.id, { ...sub, subId: message.result });

        this.#handleSubscriptionSet(sub);
      }
    }

    if (message.method === 'accountNotification') {
      const sub = Array.from(this.#subscriptions.values())
        .find((s) => s.subId === message.params.subscription && s.type === 'native');

      if (sub) {
        this.#notifyBalanceUpdate(sub.address, undefined, BigInt(message.params.result.value.lamports));
      }
    }

    if (message.method === 'programNotification') {
      const { info } = message.params.result.value.account.data.parsed;

      const sub = Array.from(this.#subscriptions.values())
        .find((s) => s.subId === message.params.subscription && (s.type === 'token-legacy' || s.type === 'token-2022'));

      if (sub) {
        this.#notifyBalanceUpdate(
          sub.address,
          info.mint,
          BigInt(info.tokenAmount.amount),
        );
      }
    }

    if (message.method === 'logsNotification') {
      const logs = message.params.result.value.logs;

      const hasNftOperation = logs.some((e) => {
        return !!SOLANA_PROGRAM_IDS.nft.find((program) => {
          if (e.includes(program)) {
            return true;
          }
        });
      });

      if (hasNftOperation) {
        const sub = Array.from(this.#subscriptions.values())
          .find((s) => s.subId === message.params.subscription && s.type === 'nft');

        if (sub) {
          this.#notifyNftsUpdate(sub.address, message.params.result.value.signature);
        }
      }
    }
  };

  #notifyBalanceUpdate(walletAddress: string, tokenAddress: string | undefined, balance: bigint) {
    for (const watcher of this.walletWatchers) {
      const { onBalanceUpdate } = watcher;

      if (!this.isWatcherReady(watcher) || !onBalanceUpdate) {
        continue;
      }

      for (const wallet of watcher.wallets) {
        if (wallet.address !== walletAddress) {
          continue;
        }

        safeExec(() => onBalanceUpdate({
          address: wallet.address,
          tokenAddress,
          balance,
          finality: 'confirmed',
        }));
      }
    }
  }

  #notifyNftsUpdate(walletAddress: string, signature: string) {
    for (const watcher of this.walletWatchers) {
      const { onNftUpdated } = watcher;

      if (!this.isWatcherReady(watcher) || !onNftUpdated) {
        continue;
      }

      for (const wallet of watcher.wallets) {
        if (wallet.address !== walletAddress) {
          continue;
        }

        safeExec(() => onNftUpdated({ signature }));
      }
    }
  }

  #handleSubscriptionSet(sub: Subscription) {
    for (const watcher of this.walletWatchers) {
      if (watcher.id !== sub.watcherId) {
        continue;
      }

      if (!watcher.isConnected) {
        watcher.isConnected = true;
        if (watcher.onConnect) safeExec(watcher.onConnect);
      }
    }
  }

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
    this.#subscriptions = new Map();
  };

  #startPing() {
    this.#stopPing?.();

    // Send random payload that returns error from Helius, but ignore error.
    // Returning of this error keeps connection alive anyway.
    const pingIntervalId = setInterval(() => {
      this.socket?.send({
        jsonrpc: '2.0',
        method: 'ping',
        id: 'pingId',
      });

      this.#cancelReconnect?.();
      this.#cancelReconnect = setCancellableTimeout(PONG_TIMEOUT, () => {
        this.socket?.reconnect();
      });
    }, PING_INTERVAL);

    this.#stopPing = () => clearInterval(pingIntervalId);
  }

  protected sendWatchedWalletsToSocket = () => {
    // Find wallets that are in subscriptions but not in watchedWallets list and unsubscribe
    const aggregatedAddresses = new Set(this.walletWatchers.map((e) => e.wallets.map((e) => e.address)).flat());

    const staleSubscribes = [...this.#subscriptions].filter((e) =>
      e[1].subId && !aggregatedAddresses.has(e[1].address),
    );

    for (const [reqId, sub] of staleSubscribes) {
      let method: UnsubscribeMethod = 'accountUnsubscribe';
      if (sub.type === 'token-legacy' || sub.type === 'token-2022') {
        method = 'programUnsubscribe';
      }
      if (sub.type === 'nft') {
        method = 'logsUnsubscribe';
      }

      this.socket!.send({
        jsonrpc: '2.0',
        id: `${reqId}-unsubscribe`,
        method,
        params: [
          sub.subId!,
        ],
      });

      this.#subscriptions.delete(reqId);
    }

    const subscribedAddresses = new Set([...this.#subscriptions].map((e) => e[1].address));

    for (const watcher of this.walletWatchers) {
      for (const wallet of watcher.wallets) {
        const requestId = this.currentUniqueId++;

        // Init subscription only on watcher w/ corresponding callbacks
        if (watcher.onBalanceUpdate) {
          this.#subscriptions.set(`${requestId}-native`, {
            type: 'native',
            address: wallet.address,
            watcherId: watcher.id,
          });

          this.socket!.send(buildSocketSubscribeMessage({ type: 'account', requestId, address: wallet.address }));

          let isLegacySubscribed = false;

          for (const tokenProgram of SOLANA_PROGRAM_IDS.token) {
            const type = !isLegacySubscribed ? 'token-legacy' : 'token-2022';

            this.#subscriptions.set(`${requestId}-${type}`, {
              type,
              address: wallet.address,
              watcherId: watcher.id,
            });

            this.socket!.send(buildSocketSubscribeMessage({
              type,
              requestId,
              address: wallet.address,
              tokenProgram,
            }));

            isLegacySubscribed = true;
          }
        }
        if (watcher.onNftUpdated) {
          this.#subscriptions.set(`${requestId}-nft`, {
            type: 'nft',
            address: wallet.address,
            watcherId: watcher.id,
          });

          this.socket!.send(buildSocketSubscribeMessage({ type: 'nft', requestId, address: wallet.address }));
        }

        subscribedAddresses.add(wallet.address);
      }
    }
  };
}

export type { HeliusSocket };

function buildSocketSubscribeMessage(params:
  | { type: 'account' | 'nft'; requestId: number; address: string }
  | { type: 'token-legacy' | 'token-2022'; requestId: number; address: string; tokenProgram: string },
): ClientSocketMessage {
  if (params.type === 'account') {
    return {
      jsonrpc: '2.0',
      id: `${params.requestId}-native`,
      method: 'accountSubscribe',
      params: [
        params.address,
        {
          encoding: 'jsonParsed',
          commitment: 'confirmed',
        },
      ],
    };
  }
  if (params.type === 'nft') {
    return {
      jsonrpc: '2.0',
      id: `${params.requestId}-nft`,
      method: 'logsSubscribe',
      params: [
        {
          mentions: [params.address],
        },
        {
          commitment: 'confirmed',
        },
      ],
    };
  }
  if (params.type === 'token-legacy' || params.type === 'token-2022') {
    return {
      jsonrpc: '2.0',
      id: `${params.requestId}-${params.type}`,
      method: 'programSubscribe',
      params: [
        params.tokenProgram,
        {
          encoding: 'jsonParsed',
          commitment: 'confirmed',
          filters: [
            {
              memcmp: {
                offset: 32,
                bytes: params.address,
              },
            },
          ],
        },
      ],
    };
  }
  throw new Error('buildSocketSubscribeMessage: Unknown subscription type');
}

/** Returns a singleton (one constant instance per a network) */
export const getHeliusSocket = withCache((network: ApiNetwork) => {
  return new HeliusSocket(network);
});

function getSocketUrl(network: ApiNetwork) {
  const url = new URL(NETWORK_CONFIG[network].rpcUrl);
  url.protocol = 'wss:';

  return url;
}
