import type { FallbackPollingOptions } from '../../../common/polling/fallbackPollingScheduler';
import type { WalletWatcher } from '../../../common/websocket/abstractWsClient';
import type { ApiNetwork, ApiNft, EVMChain } from '../../../types';
import type { EvmNftTransferEvent } from '../types';

import { createCallbackManager } from '../../../../util/callbacks';
import { logDebug } from '../../../../util/logs';
import { normalizeNftAddress } from '../../../../util/nft';
import { FallbackPollingScheduler } from '../../../common/polling/fallbackPollingScheduler';
import { inactiveNftTiming, periodToMs } from '../../../common/polling/utils';
import { fetchNftByAddress, streamAllAccountNfts } from '../nfts';
import { inactiveWallets } from './inactiveWallets';
import { getAlchemySocket } from './socket';

export type OnNftUpdate = (params:
  { direction: 'set'; nfts: ApiNft[]; hasNewNfts?: boolean; isFullLoading: boolean; streamedAddresses?: string[] }
  | { direction: 'send'; nftAddress: string; newOwner: string }
  | { direction: 'receive'; nft: ApiNft }
) => void;

export type OnLoadingChange = (isLoading: boolean) => void;

// The slowest pace at which the app already polls an inactive NFT wallet
const [, INACTIVE_RECHECK_MS] = periodToMs(inactiveNftTiming.forcedPollingPeriod);

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
  #inactiveCheckedAt = 0;
  #inactiveConnectCount = 0;
  #connectCount = 0;

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

  /** Loads the NFTs of a wallet the precheck has not found active yet, once activity proves it is */
  public activate() {
    // An active stream polls on its own schedule, so a repeated activity signal must not add full loads
    if (this.#isDestroyed || this.#walletStatus === 'active') return;

    this.#markWalletActive();
    this.#fallbackPollingScheduler.forceImmediatePoll();
  }

  #handleSocketConnect = () => {
    // The socket can miss the event that wakes an empty wallet before or between subscriptions,
    // so an empty verdict read before this connect no longer holds
    this.#connectCount++;
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

    const nftAddress = normalizeNftAddress(`${contractAddress}/${tokenId}`);

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
    // An empty wallet is woken by a socket transfer or `activate`; the schedule rechecks it only after a
    // connect or at the pace of an inactive NFT stream, in case that event was lost
    if (this.#walletStatus === 'inactive') {
      const isVerdictFresh = this.#inactiveConnectCount === this.#connectCount
        && Date.now() - this.#inactiveCheckedAt < INACTIVE_RECHECK_MS;
      if (isVerdictFresh) return;
      // A read that started before the connect may have cached the verdict after it
      inactiveWallets.forget(this.#network, this.#chain, this.#address);
    }

    const startedAt = Date.now();
    const connectCount = this.#connectCount;

    const streamedAddresses = new Set<string>();
    const ignorePreCheck = this.#ignoreNextPollPreCheck || this.#walletStatus === 'active';
    this.#ignoreNextPollPreCheck = false;
    let didComplete = false;
    let didFail = false;

    try {
      this.#abortController?.abort();
      this.#abortController = new AbortController();
      this.#loadingListeners.runCallbacks(true);

      await streamAllAccountNfts(this.#chain, this.#accountId, {
        signal: this.#abortController.signal,
        ignorePreCheck,
        onPreCheckResult: (isActive) => this.#handlePreCheckResult(isActive, startedAt, connectCount),
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
      didComplete = true;
    } catch (err) {
      didFail = true;
      throw err;
    } finally {
      logDebug('nftStream.fullLoadFinal', {
        accountId: this.#accountId,
        chain: this.#chain,
        streamedCount: streamedAddresses.size,
        didComplete,
        didFail,
        destroyed: this.#isDestroyed,
        aborted: this.#abortController?.signal.aborted,
      });

      if (!this.#isDestroyed) {
        this.#updateListeners.runCallbacks({
          direction: 'set',
          nfts: [],
          hasNewNfts: false,
          isFullLoading: false,
          streamedAddresses: didComplete ? [...streamedAddresses] : undefined,
        });
        this.#loadingListeners.runCallbacks(false);
      }
    }
  };

  #handlePreCheckResult = (isActive: boolean, startedAt: number, connectCount: number) => {
    if (!isActive && this.#walletStatus === 'active') return;

    this.#walletStatus = isActive ? 'active' : 'inactive';
    if (isActive) return;

    // Tied to the connect the read began under, so a connect while it was in flight leaves the recheck due
    this.#inactiveCheckedAt = startedAt;
    this.#inactiveConnectCount = connectCount;
  };

  #markWalletActive() {
    this.#walletStatus = 'active';
  }
}
