import type { DefaultActivitiesUpdate, InMessageCallback } from '../../../common/websocket/abstractWsClient';
import type { ApiNetwork, EVMChain } from '../../../types';
import type {
  AlchemySocketClientMessage,
  AlchemySocketServerMessage,
  EthSubscriptionMessage,
  EvmNftTransferEvent,
  EvmSubscriptionType,
  EvmWatchedWallet,
  LogNotification,
  MinedTransactionNotification,
} from '../types';

import { logDebugError } from '../../../../util/logs';
import safeExec from '../../../../util/safeExec';
import withCache from '../../../../util/withCache';
import { AbstractWebsocketClient } from '../../../common/websocket/abstractWsClient';
import { EVM_RPC_URLS } from '../constants';
import { getErc20Balance, getWalletBalance } from '../wallet';

type Subscription = {
  key: string;
  requestId: string;
  watcherId: number;
  address: string;
  type: EvmSubscriptionType;
  subId?: string;
};

const TRANSFER_EVENT_TOPIC = '0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef';
const ERC1155_TRANSFER_SINGLE_TOPIC = '0xc3d58168c5ae7397731d063d5bbf3d657854427343f4c083240f7aacaa2d0f62';
const ERC1155_TRANSFER_BATCH_TOPIC = '0x4a39dc06d4c0dbc64b70af90fd698a233a518aa5d07e595d983b8c0526c8f7fb';

/** ERC-721 Transfer has 4 topics (tokenId is indexed); ERC-20 Transfer has 3 */
const NFT_TRANSFER_TOPICS_COUNT = 4;

class AlchemySocket extends AbstractWebsocketClient<
  AlchemySocketClientMessage,
  AlchemySocketServerMessage,
  EvmWatchedWallet,
  DefaultActivitiesUpdate,
  EvmNftTransferEvent
> {
  #network: ApiNetwork;
  #chain: EVMChain;
  #subscriptionsByKey = new Map<string, Subscription>();
  #subscriptionsByRequestId = new Map<string, Subscription>();
  #subscriptionsBySubId = new Map<string, Subscription>();

  constructor(network: ApiNetwork, chain: EVMChain) {
    super(getSocketUrl(network, chain));
    this.#network = network;
    this.#chain = chain;
  }

  protected handleSocketMessage: InMessageCallback<AlchemySocketServerMessage> = (message) => {
    if (isSubscribeResultMessage(message)) {
      const sub = this.#subscriptionsByRequestId.get(message.id);

      if (!sub) {
        return;
      }

      sub.subId = message.result;
      this.#subscriptionsBySubId.set(message.result, sub);
      this.#handleSubscriptionSet(sub.watcherId);
      return;
    }

    if (!isSubscriptionMessage(message)) {
      return;
    }

    const sub = this.#subscriptionsBySubId.get(message.params.subscription);
    if (!sub) {
      return;
    }

    if (sub.type === 'native') {
      void this.#handleNativeNotification(sub, message.params.result as MinedTransactionNotification);
      return;
    }

    const log = message.params.result as LogNotification;

    if (sub.type === 'erc721_in' || sub.type === 'erc721_out'
      || sub.type === 'erc1155_in' || sub.type === 'erc1155_out') {
      void this.#handleNftNotification(sub, log);
      return;
    }

    void this.#handleTokenNotification(sub, log);
  };

  protected handleSocketConnect = () => {
    this.sendWatchedWalletsToSocket();
  };

  protected handleSocketDisconnect = () => {
    this.#subscriptionsByKey.clear();
    this.#subscriptionsByRequestId.clear();
    this.#subscriptionsBySubId.clear();

    for (const watcher of this.walletWatchers) {
      if (watcher.isConnected) {
        watcher.isConnected = false;

        if (watcher.onDisconnect) safeExec(watcher.onDisconnect);
      }
    }
  };

  protected sendWatchedWalletsToSocket = () => {
    const required = this.#buildRequiredSubscriptions();

    const stale = [...this.#subscriptionsByKey].filter(([key]) => !required.has(key));

    for (const [key, sub] of stale) {
      this.#unsubscribe(sub);
      this.#subscriptionsByKey.delete(key);
      this.#subscriptionsByRequestId.delete(sub.requestId);
      if (sub.subId) {
        this.#subscriptionsBySubId.delete(sub.subId);
      }
    }

    for (const [key, sub] of required) {
      if (this.#subscriptionsByKey.has(key)) {
        continue;
      }

      this.#subscriptionsByKey.set(key, sub);
      this.#subscriptionsByRequestId.set(sub.requestId, sub);
      this.#subscribe(sub);
    }
  };

  #buildRequiredSubscriptions() {
    const required = new Map<string, Subscription>();

    for (const watcher of this.walletWatchers) {
      for (const wallet of watcher.wallets) {
        const normalizedAddress = wallet.address.toLowerCase();

        if (watcher.onBalanceUpdate) {
          const nativeKey = `${watcher.id}:${normalizedAddress}:native`;
          const erc20InKey = `${watcher.id}:${normalizedAddress}:erc20_in`;
          const erc20OutKey = `${watcher.id}:${normalizedAddress}:erc20_out`;

          required.set(nativeKey, this.#createSubscription(nativeKey, watcher.id, normalizedAddress, 'native'));
          required.set(erc20InKey, this.#createSubscription(erc20InKey, watcher.id, normalizedAddress, 'erc20_in'));
          required.set(erc20OutKey, this.#createSubscription(erc20OutKey, watcher.id, normalizedAddress, 'erc20_out'));
        }

        if (watcher.onNftUpdated) {
          const erc721InKey = `${watcher.id}:${normalizedAddress}:erc721_in`;
          const erc721OutKey = `${watcher.id}:${normalizedAddress}:erc721_out`;
          const erc1155InKey = `${watcher.id}:${normalizedAddress}:erc1155_in`;
          const erc1155OutKey = `${watcher.id}:${normalizedAddress}:erc1155_out`;

          required.set(erc721InKey,
            this.#createSubscription(erc721InKey, watcher.id, normalizedAddress, 'erc721_in'));
          required.set(erc721OutKey,
            this.#createSubscription(erc721OutKey, watcher.id, normalizedAddress, 'erc721_out'));
          required.set(erc1155InKey,
            this.#createSubscription(erc1155InKey, watcher.id, normalizedAddress, 'erc1155_in'));
          required.set(erc1155OutKey,
            this.#createSubscription(erc1155OutKey, watcher.id, normalizedAddress, 'erc1155_out'));
        }
      }
    }

    return required;
  }

  #createSubscription(
    key: string,
    watcherId: number,
    address: string,
    type: EvmSubscriptionType,
  ): Subscription {
    return {
      key,
      requestId: `${this.currentUniqueId++}`,
      watcherId,
      address,
      type,
    };
  }

  #subscribe(sub: Subscription) {
    if (!this.socket?.isConnected) {
      return;
    }

    this.socket.send(buildSubscribeMessage(sub));
  }

  #unsubscribe(sub: Subscription) {
    if (!sub.subId || !this.socket?.isConnected) {
      return;
    }

    this.socket.send({
      jsonrpc: '2.0',
      id: `${this.currentUniqueId++}`,
      method: 'eth_unsubscribe',
      params: [sub.subId],
    });
  }

  #handleSubscriptionSet(watcherId: number) {
    for (const watcher of this.walletWatchers) {
      if (watcher.id !== watcherId || watcher.isConnected) {
        continue;
      }

      watcher.isConnected = true;
      if (watcher.onConnect) safeExec(watcher.onConnect);
    }
  }

  async #handleNativeNotification(sub: Subscription, result: MinedTransactionNotification) {
    const balance = await getWalletBalance(this.#chain, this.#network, sub.address);

    this.#notifyBalanceUpdate(sub.watcherId, sub.address, undefined, balance);
  }

  async #handleTokenNotification(sub: Subscription, result: LogNotification) {
    // Skip ERC-721 logs that arrive on ERC-20 subscriptions (same Transfer topic0, but 4 topics vs 3)
    if (result.topics.length !== 3) return;

    const tokenAddress = result.address.toLowerCase();
    const balance = await getErc20Balance(this.#network, this.#chain, sub.address, tokenAddress);

    this.#notifyBalanceUpdate(sub.watcherId, sub.address, tokenAddress, balance);
  }

  #handleNftNotification(sub: Subscription, result: LogNotification) {
    if (result.removed) return;

    const isErc1155 = result.topics[0] === ERC1155_TRANSFER_SINGLE_TOPIC
      || result.topics[0] === ERC1155_TRANSFER_BATCH_TOPIC;

    if (!isErc1155 && result.topics.length !== NFT_TRANSFER_TOPICS_COUNT) {
      // ERC-20 Transfer arriving on ERC-721 subscription — skip
      return;
    }

    if (isErc1155 && result.topics.length !== NFT_TRANSFER_TOPICS_COUNT) {
      return;
    }

    const contractAddress = result.address.toLowerCase();
    // For ERC-721: topics = [event, from, to, tokenId]
    // For ERC-1155: topics = [event, operator, from, to]
    const fromTopic = isErc1155 ? result.topics[2] : result.topics[1];
    const toTopic = isErc1155 ? result.topics[3] : result.topics[2];

    const from = `0x${fromTopic.slice(-40)}`;
    const to = `0x${toTopic.slice(-40)}`;

    let tokenId: string | undefined;

    if (!isErc1155) {
      if (result.topics[3]) {
        tokenId = BigInt(result.topics[3]).toString();
      } else {
        logDebugError(`EVM socket:${this.#chain}: tokenId not provided, ${result.topics.join(', ')}`);

        return;
      }
    } else if (result.topics[0] === ERC1155_TRANSFER_SINGLE_TOPIC && result.data && result.data.length >= 66) {
      // data = abi.encode(uint256 id, uint256 value): first 32 bytes = id
      tokenId = BigInt(`0x${result.data.slice(2, 66)}`).toString();
    }
    // For TransferBatch: tokenId stays undefined → NftStream falls back to a full poll

    const event: EvmNftTransferEvent = {
      contractAddress,
      from,
      to,
      tokenType: isErc1155 ? 'erc1155' : 'erc721',
      tokenId,
    };

    this.#notifyNftTransfer(sub.watcherId, sub.address, event);
  }

  #notifyNftTransfer(watcherId: number, walletAddress: string, event: EvmNftTransferEvent) {
    for (const watcher of this.walletWatchers) {
      const { onNftUpdated } = watcher;

      if (!this.isWatcherReady(watcher) || !onNftUpdated || watcher.id !== watcherId) {
        continue;
      }

      const matchedWallet = watcher.wallets.find((wallet) => wallet.address.toLowerCase() === walletAddress);
      if (!matchedWallet) continue;

      safeExec(() => onNftUpdated(event));
    }
  }

  #notifyBalanceUpdate(
    watcherId: number,
    walletAddress: string,
    tokenAddress: string | undefined,
    balance: bigint,
  ) {
    for (const watcher of this.walletWatchers) {
      const { onBalanceUpdate } = watcher;

      if (!this.isWatcherReady(watcher) || !onBalanceUpdate || watcher.id !== watcherId) {
        continue;
      }

      const matchedWallet = watcher.wallets.find((wallet) => {
        return wallet.address.toLowerCase() === walletAddress;
      });

      if (!matchedWallet) {
        continue;
      }

      safeExec(() => onBalanceUpdate({
        address: matchedWallet.address,
        tokenAddress,
        balance,
        finality: 'confirmed',
      }));
    }
  }
}

function buildSubscribeMessage(sub: Subscription): AlchemySocketClientMessage {
  if (sub.type === 'native') {
    return {
      jsonrpc: '2.0',
      id: sub.requestId,
      method: 'eth_subscribe',
      params: [
        'alchemy_minedTransactions',
        {
          addresses: [{
            from: sub.address,
          }, {
            to: sub.address,
          }],
          includeRemoved: true,
          hashesOnly: false,
        },
      ],
    };
  }

  const paddedAddress = `0x${sub.address.replace('0x', '').padStart(64, '0')}`;

  if (sub.type === 'erc721_in' || sub.type === 'erc721_out') {
    // ERC-721 shares Transfer topic0 with ERC-20; we distinguish by topics.length in the handler
    const topics = sub.type === 'erc721_in'
      ? [TRANSFER_EVENT_TOPIC, undefined, paddedAddress]
      : [TRANSFER_EVENT_TOPIC, paddedAddress, undefined];

    return {
      jsonrpc: '2.0',
      id: sub.requestId,
      method: 'eth_subscribe',
      params: ['logs', { topics }],
    };
  }

  if (sub.type === 'erc1155_in' || sub.type === 'erc1155_out') {
    // Match both TransferSingle and TransferBatch using an OR filter on topic0
    const erc1155Topics = sub.type === 'erc1155_in'
      ? [[ERC1155_TRANSFER_SINGLE_TOPIC, ERC1155_TRANSFER_BATCH_TOPIC], undefined, undefined, paddedAddress]
      : [[ERC1155_TRANSFER_SINGLE_TOPIC, ERC1155_TRANSFER_BATCH_TOPIC], undefined, paddedAddress, undefined];

    return {
      jsonrpc: '2.0',
      id: sub.requestId,
      method: 'eth_subscribe',
      params: ['logs', { topics: erc1155Topics }],
    };
  }

  const topics = sub.type === 'erc20_in'
    ? [TRANSFER_EVENT_TOPIC, undefined, paddedAddress]
    : [TRANSFER_EVENT_TOPIC, paddedAddress, undefined];

  return {
    jsonrpc: '2.0',
    id: sub.requestId,
    method: 'eth_subscribe',
    params: [
      'logs',
      {
        topics,
      },
    ],
  };
}

function getSocketUrl(network: ApiNetwork, chain: EVMChain) {
  const url = new URL(`${EVM_RPC_URLS[network](chain)}/v2`);
  url.protocol = 'wss:';

  return url;
}

function isSubscribeResultMessage(
  message: AlchemySocketServerMessage,
): message is { jsonrpc: '2.0'; id: string; result: string } {
  return 'id' in message && typeof message.id === 'string' && 'result' in message && typeof message.result === 'string';
}

function isSubscriptionMessage(message: AlchemySocketServerMessage): message is EthSubscriptionMessage {
  return 'method' in message && message.method === 'eth_subscription';
}

/** Returns a singleton (one constant instance per network+chain combination) */
export const getAlchemySocket = withCache((network: ApiNetwork, chain: EVMChain) => {
  return new AlchemySocket(network, chain);
});

export type { AlchemySocket };
