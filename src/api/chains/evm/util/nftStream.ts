import type { FallbackPollingOptions } from '../../../common/polling/fallbackPollingScheduler';
import type { WalletWatcher } from '../../../common/websocket/abstractWsClient';
import type { ApiNetwork, ApiNft, EVMChain } from '../../../types';
import type { EvmNftTransferEvent } from '../types';

import { createCallbackManager } from '../../../../util/callbacks';
import { FallbackPollingScheduler } from '../../../common/polling/fallbackPollingScheduler';
import { fetchNftByAddress, streamAllAccountNfts } from '../nfts';
import { getAlchemySocket } from './socket';

export type OnNftUpdate = (params:
  { direction: 'set'; nfts: ApiNft[]; hasNewNfts?: boolean; isFullLoading: boolean; streamedAddresses?: string[] }
  | { direction: 'send'; nftAddress: string; newOwner: string }
  | { direction: 'receive'; nft: ApiNft }
) => void;

export type OnLoadingChange = (isLoading: boolean) => void;

/**
 * Streams NFT-related updates and exposes ready-to-use structures.
 * Reacts to ERC-721 and ERC-1155 Transfer events via the Alchemy WebSocket for immediate
 * send/receive updates; falls back to periodic polling for full synchronisation.
 */
export class NftStream {
  #chain: EVMChain;
  #network: ApiNetwork;
  #address: string;
  #accountId: string;
  #persistedNftAddresses = new Set<string>();

  #walletWatcher: WalletWatcher;
  #fallbackPollingScheduler: FallbackPollingScheduler;

  #updateListeners = createCallbackManager<OnNftUpdate>();
  #loadingListeners = createCallbackManager<OnLoadingChange>();

  #abortController?: AbortController;
  #isDestroyed = false;
  #ignoreNextPollPreCheck = false;
  #walletStatus: 'active' | 'inactive' | undefined = undefined;

  constructor(
    chain: EVMChain,
    network: ApiNetwork,
    address: string,
    accountId: string,
    fallbackPollingOptions: FallbackPollingOptions,
  ) {
    this.#chain = chain;
    this.#network = network;
    this.#address = address;
    this.#accountId = accountId;

    this.#walletWatcher = getAlchemySocket(network, chain).watchWallets(
      [{ address, chain }],
      {
        onConnect: this.#handleSocketConnect,
        onDisconnect: this.#handleSocketDisconnect,
        onNftUpdated: this.#handleSocketNftTransfer,
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

  #handleSocketNftTransfer = async (event: EvmNftTransferEvent) => {
    if (this.#isDestroyed) return;
    this.#fallbackPollingScheduler.onSocketMessage();
    this.#markWalletActive();

    const { contractAddress, from, to, tokenId } = event;
    const ourAddress = this.#address.toLowerCase();

    if (!tokenId) {
      // TransferBatch or undecodable event: trigger a full rescan
      this.#ignoreNextPollPreCheck = true;
      this.#fallbackPollingScheduler.forceImmediatePoll();
      return;
    }

    const nftAddress = `${contractAddress}/${tokenId}`;

    if (from === ourAddress) {
      this.#updateListeners.runCallbacks({
        direction: 'send',
        nftAddress,
        newOwner: to,
      });
      return;
    }

    if (to === ourAddress) {
      const nft = await fetchNftByAddress(this.#chain, this.#network, contractAddress, tokenId, this.#address);
      if (this.#isDestroyed) return;

      if (nft) {
        this.#updateListeners.runCallbacks({ direction: 'receive', nft });
      } else {
        // Metadata fetch failed — fall back to a full poll
        this.#ignoreNextPollPreCheck = true;
        this.#fallbackPollingScheduler.forceImmediatePoll();
      }
    }
  };

  #poll = async () => {
    const streamedAddresses = new Set<string>();
    const ignorePreCheck = this.#ignoreNextPollPreCheck || this.#walletStatus === 'active';
    this.#ignoreNextPollPreCheck = false;

    try {
      this.#abortController?.abort();
      this.#abortController = new AbortController();
      this.#loadingListeners.runCallbacks(true);

      await streamAllAccountNfts(this.#chain, this.#accountId, {
        signal: this.#abortController.signal,
        ignorePreCheck,
        onPreCheckResult: this.#handlePreCheckResult,
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

  #handlePreCheckResult = (isActive: boolean) => {
    if (!isActive && this.#walletStatus === 'active') return;

    this.#walletStatus = isActive ? 'active' : 'inactive';
  };

  #markWalletActive() {
    this.#walletStatus = 'active';
  }
}
