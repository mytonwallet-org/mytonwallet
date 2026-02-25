import type { FallbackPollingOptions } from '../../../common/polling/fallbackPollingScheduler';
import type { WalletWatcher } from '../../../common/websocket/abstractWsClient';
import type { ApiNetwork, ApiNft } from '../../../types';

import { createCallbackManager } from '../../../../util/callbacks';
import { FallbackPollingScheduler } from '../../../common/polling/fallbackPollingScheduler';
import { parseSolTx } from '../activities';
import { fetchNftByAddress, getAccountNfts, streamAllAccountNfts } from '../nfts';
import { getHeliusSocket } from './socket';

export type OnNftUpdate = (params:
  { direction: 'set'; nfts: ApiNft[]; hasNewNfts?: boolean; isFullLoading: boolean; streamedAddresses?: string[] }
  | { direction: 'send'; nftAddress: string; newOwner: string }
  | { direction: 'receive'; nft: ApiNft }
) => void;

export type OnLoadingChange = (isLoading: boolean) => void;

/**
 * Streams NFT-related updates and fetches resources in order of event, then exposes ready-to-use structures
 */
export class NftStream {
  #accountId: string;
  #network: ApiNetwork;
  #address: string;
  #persistedNftAddresses = new Set<string>();

  #walletWatcher: WalletWatcher;

  #fallbackPollingScheduler: FallbackPollingScheduler;

  #updateListeners = createCallbackManager<OnNftUpdate>();
  #loadingListeners = createCallbackManager<OnLoadingChange>();

  #abortController?: AbortController;
  #isDestroyed = false;

  constructor(
    network: ApiNetwork,
    address: string,
    accountId: string,
    fallbackPollingOptions: FallbackPollingOptions,
  ) {
    this.#accountId = accountId;
    this.#network = network;
    this.#address = address;

    this.#walletWatcher = getHeliusSocket(network).watchWallets(
      [{ address }],
      {
        onConnect: this.#handleSocketConnect,
        onDisconnect: this.#handleSocketDisconnect,
        onNftUpdated: this.#handleSocketChangeNfts,
      },
    );

    this.#fallbackPollingScheduler = new FallbackPollingScheduler(
      this.#poll,
      this.#walletWatcher.isConnected,
      fallbackPollingOptions,
    );
  }

  public onUpdate(callback: OnNftUpdate) {
    return this.#updateListeners.addCallback(callback);
  }

  public onLoadingChange(callback: OnLoadingChange) {
    return this.#loadingListeners.addCallback(callback);
  }

  public destroy() {
    this.#isDestroyed = true;
    this.#abortController?.abort();
    this.#walletWatcher.destroy();
    this.#fallbackPollingScheduler.destroy();
  }

  #handleSocketConnect = () => {
    this.#fallbackPollingScheduler.onSocketConnect();
  };

  #handleSocketDisconnect = () => {
    this.#fallbackPollingScheduler.onSocketDisconnect();
  };

  #handleSocketChangeNfts = async (params: { signature: string }) => {
    if (this.#isDestroyed) return;
    this.#fallbackPollingScheduler.onSocketMessage();

    const parsedTx = await parseSolTx(this.#network, params.signature);

    const { compressed, nft } = parsedTx?.events || {};

    switch (true) {
      case compressed?.[0].oldLeafOwner === this.#address: {
        this.#updateListeners.runCallbacks({
          direction: 'send',
          nftAddress: compressed[0].assetId,
          newOwner: compressed[0].newLeafOwner!,
        });
        break;
      }
      case compressed?.[0].newLeafOwner === this.#address: {
        const received = await fetchNftByAddress(this.#network, compressed[0].assetId);
        this.#updateListeners.runCallbacks({
          direction: 'receive',
          nft: received,
        });
        break;
      }
      case nft?.buyer === this.#address && !!nft.nfts[0]: {
        const received = await fetchNftByAddress(this.#network, nft.nfts[0].mint);
        this.#updateListeners.runCallbacks({
          direction: 'receive',
          nft: received,
        });
        break;
      }
      case nft?.seller === this.#address && !!nft.nfts[0]: {
        this.#updateListeners.runCallbacks({
          direction: 'send',
          nftAddress: nft.nfts[0].mint,
          newOwner: nft.buyer,
        });
        break;
      }
      default: {
        // Don't have parsed tx, but know it's NFT-related - update all nfts
        const nfts = await getAccountNfts(this.#accountId);

        this.#updateListeners.runCallbacks({ direction: 'set', nfts, hasNewNfts: true, isFullLoading: false });
      }
    }
  };

  #poll = async () => {
    const streamedAddresses = new Set<string>();

    try {
      this.#abortController?.abort();
      this.#abortController = new AbortController();
      this.#loadingListeners.runCallbacks(true);

      await streamAllAccountNfts(this.#accountId, {
        signal: this.#abortController.signal,
        onBatch: (batchNfts) => {
          const hasNewNfts = batchNfts.some((nft) => !this.#persistedNftAddresses.has(nft.address));
          batchNfts.forEach((nft) => streamedAddresses.add(nft.address));
          this.#updateListeners.runCallbacks({
            direction: 'set', nfts: batchNfts, hasNewNfts, isFullLoading: true,
          });
        },
      });

      if (this.#isDestroyed) return;

      this.#persistedNftAddresses = streamedAddresses;
    } finally {
      if (!this.#isDestroyed) {
        this.#updateListeners.runCallbacks({
          direction: 'set',
          nfts: [],
          hasNewNfts: false,
          isFullLoading: false,
          streamedAddresses: [...streamedAddresses],
        });
        this.#loadingListeners.runCallbacks(false);
      }
    }
  };
}
