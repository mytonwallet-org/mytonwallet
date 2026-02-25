/**
 * WalletConnect v2 Protocol Adapter
 *
 * Implements DappProtocolAdapter for WalletConnect v2 protocol
 * and adaptation for injected protocols (StandardWallet, EIP-6963).
 * Provides connectivity for EVM chains (Ethereum, Polygon, etc.),
 * Solana, and other WalletConnect-supported blockchains.
 *
 * Key responsibilities:
 * - Initialize WalletKit SDK
 * - Handle session proposals and requests
 * - Route RPC calls to appropriate chain handlers
 * - Manage session lifecycle
 */

import type { IWalletKit, WalletKitTypes } from '@reown/walletkit';
import { WalletKit } from '@reown/walletkit';
import { Core } from '@walletconnect/core';
import type { SessionTypes } from '@walletconnect/types';
import { buildApprovedNamespaces, getSdkError } from '@walletconnect/utils';

import type {
  confirmDappRequestConnect,
  confirmDappRequestSendTransaction,
  confirmDappRequestSignData,
} from '../../../methods';
import type { ApiChain, ApiDappRequest, OnApiUpdate } from '../../../types';
import type { DappProtocolError } from '../../errors';
import type { StoredDappConnection } from '../../storage';
import type {
  DappDisconnectRequest,
  UnifiedSignDataPayload } from '../../types';
import {
  type DappConnectionRequest,
  type DappConnectionResult,
  type DappMethodResult,
  type DappProtocolAdapter,
  type DappProtocolConfig,
  DappProtocolType,
  type DappSignDataRequest,
  type DappTransactionRequest,
} from '../../types';
import {
  CHAIN_IDS,
  namespacesToSessionChains,
  type WalletConnectSessionProposal,
} from './types';

import { APP_NAME, IS_EXTENSION, WALLET_CONNECT_PROJECT_ID } from '../../../../config';
import { parseAccountId } from '../../../../util/account';
import { getDappConnectionUniqueId } from '../../../../util/getDappConnectionUniqueId';
import { logDebugError } from '../../../../util/logs';
import safeExec from '../../../../util/safeExec';
import {
  fetchStoredChainAccount,
  getAccountIdByAddress,
  getCurrentAccountId,
  getCurrentAccountIdOrFail,
} from '../../../common/accounts';
import { createDappPromise } from '../../../common/dappPromises';
import { isUpdaterAlive } from '../../../common/helpers';
import { ApiUserRejectsError } from '../../../errors';
import { callHook } from '../../../hooks';
import {
  addDapp,
  deleteDapp,
  findLastConnectedAccount,
  getDapp,
  getDappsState,
  updateDapp,
} from '../../../methods/dapps';

// WalletConnect deep link patterns
const WALLET_CONNECT_DEEP_LINK_PREFIXES = [
  'wc:',
  'https://walletconnect.com/wc',
];
/**
 * WalletConnect v2 protocol adapter.
 */
class WalletConnectAdapter implements DappProtocolAdapter<DappProtocolType.WalletConnect> {
  readonly protocolType = DappProtocolType.WalletConnect;

  private onUpdate!: OnApiUpdate;

  private initialized = false;

  private walletKit!: IWalletKit;

  private chainDappSupports: NonNullable<DappProtocolConfig['chainDappSupports']> = {};

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  async init(config: DappProtocolConfig): Promise<void> {
    if (this.initialized) {
      return;
    }

    this.onUpdate = config.onUpdate;
    this.chainDappSupports = config.chainDappSupports ?? {};

    if (!WALLET_CONNECT_PROJECT_ID) {
      logDebugError('WalletConnectAdapter', 'No project ID provided');
      return;
    }

    //
    // See: https://docs.walletconnect.network/wallet-sdk/web/usage
    //
    const core = new Core({ projectId: WALLET_CONNECT_PROJECT_ID });
    this.walletKit = await WalletKit.init({
      core,
      metadata: {
        name: APP_NAME,
        description: 'Multichain cryptocurrency wallet',
        url: 'https://mytonwallet.io',
        icons: ['https://mytonwallet.io/icon-512x512.png'],
      },
    });

    this.walletKit.on('session_proposal', this.handleSessionProposal);
    this.walletKit.on('session_request', this.handleSessionRequest);
    this.walletKit.on('session_delete', this.handleSessionDelete);

    this.initialized = true;
  }

  async destroy(): Promise<void> {
    if (this.walletKit) {
      this.walletKit.off('session_proposal', this.handleSessionProposal);
      this.walletKit.off('session_request', this.handleSessionRequest);
      this.walletKit.off('session_delete', this.handleSessionDelete);
    }

    this.initialized = false;
    return Promise.resolve();
  }

  // ---------------------------------------------------------------------------
  // WalletConnect Event Handlers (internal)
  // ---------------------------------------------------------------------------

  /**
   * Handle incoming session proposal from dApp.
   * This is called when a dApp scans QR code or follows deep link.
   */
  private handleSessionProposal = async (proposal: WalletConnectSessionProposal) => {
    let dappUniqueId = '';
    let dappAccountId = '';
    let dappUrl = '';
    try {
      const { id, params } = proposal;
      const { proposer, optionalNamespaces, requiredNamespaces } = params;

      const requiredChains = namespacesToSessionChains(requiredNamespaces);
      const optionalChains = namespacesToSessionChains(optionalNamespaces);

      // Convert to unified connection request
      const connectionRequest: DappConnectionRequest = {
        protocolType: DappProtocolType.WalletConnect,
        transport: 'relay',
        requestedChains: [...requiredChains, ...optionalChains],
        permissions: {
          isAddressRequired: true,
          isPasswordRequired: false,
        },
        protocolData: proposal,
      };

      const request: ApiDappRequest = {
        url: proposer.metadata.url,
        identifier: String(id),
      };

      const result = await this.connect(request, connectionRequest, 1);

      if (!result.success) {
        return;
      }

      dappUniqueId = getDappConnectionUniqueId(result.session.dapp);
      dappAccountId = result.session.accountId;
      dappUrl = result.session.dapp.url;

      const session = await this.walletKit.approveSession({
        id,
        namespaces: result.session.protocolData,
      });

      // now we have session topic, so add it to the dapp
      await updateDapp(
        result.session.accountId,
        result.session.dapp.url,
        dappUniqueId,
        { wcTopic: session.topic },
      );
    } catch (err) {
      logDebugError('walletConnect:handleSessionProposal', err);

      await deleteDapp(
        dappAccountId,
        dappUrl,
        dappUniqueId,
      );
    }
  };

  private async requestTransactionSign(
    id: number,
    chain: ApiChain,
    topic: string,
    url: string,
    tx: string,
    full?: boolean,
  ) {
    const message: DappTransactionRequest<typeof this.protocolType> = {
      id: String(id),
      chain,
      payload: {
        // Sign and send back to Dapp, not send on wallets behalf
        isSignOnly: true,
        topic,
        data: tx,
        isFullTxRequested: full,
      },
    };

    const response = await this.sendTransaction({ url }, message);

    return response;
  }

  /**
   * Handle incoming session request (RPC call) from dApp.
   */
  private handleSessionRequest = async (event: WalletKitTypes.SessionRequest) => {
    const { id, topic, params } = event;
    const { request, chainId } = params;

    const namespace = CHAIN_IDS[chainId];

    const byTopic = await getDappByTopic(topic, 'default');
    if (!byTopic) {
      logDebugError(`walletConnect:handleSessionRequest - Dapp not found for topic: ${topic}`);
      const response = {
        id,
        jsonrpc: '2.0',
        error: getSdkError('INVALID_EVENT'),
      };

      await this.walletKit.respondSessionRequest({ topic: event.topic, response });
      return;
    }

    // Route based on method
    switch (request.method) {
      case 'eth_sendTransaction':
      case 'eth_signTransaction':
      case 'solana_signTransaction': {
        const response = await this.requestTransactionSign(
          id,
          namespace.chain,
          topic,
          byTopic.dapp.url,
          request.params.transaction,
        );

        if (!response.success) {
          return;
        }

        await this.walletKit.respondSessionRequest({
          topic,
          response: {
            id,
            jsonrpc: '2.0',
            result: { signature: response.result.result },
          },
        });
        break;
      }
      case 'solana_signAllTransactions': {
        const signatures = new Set<string>();

        for (const tx of request.params.transactions) {
          const response = await this.requestTransactionSign(
            id,
            namespace.chain,
            topic,
            byTopic.dapp.url,
            tx,
            true,
          );

          if (!response.success) {
            return;
          }

          signatures.add(response.result.result);
        }

        await this.walletKit.respondSessionRequest({
          topic,
          response: {
            id,
            jsonrpc: '2.0',
            result: { transactions: [...signatures] },
          },
        });
        break;
      }

      case 'personal_sign':
      case 'eth_sign':
      case 'eth_signTypedData':
      case 'eth_signTypedData_v4':
      case 'solana_signMessage': {
        const message: DappSignDataRequest<typeof this.protocolType> = {
          id: String(id),
          chain: namespace.chain,
          payload: {
            topic,
            data: request.params.message,
          },
        };
        await this.signData({ url: byTopic.dapp.url }, message);
        break;
      }

      default: {
        logDebugError(`walletConnect:handleSessionRequest - unsupported method: ${request.method}`);
        const response = {
          id,
          jsonrpc: '2.0',
          error: getSdkError('WC_METHOD_UNSUPPORTED'),
        };

        await this.walletKit.respondSessionRequest({ topic: event.topic, response });
      }
    }
  };

  /**
   * Handle session deletion (disconnect) from dApp.
   */
  private handleSessionDelete = async (event: { topic: string }) => {
    try {
      const byTopic = (await getDappByTopic(event.topic, 'default'));

      if (!byTopic) {
        return;
      }

      const uniqueId = getDappConnectionUniqueId(byTopic.dapp);

      await deleteDapp(byTopic.accountId, byTopic.dapp.url, uniqueId);

      this.onUpdate({ type: 'updateDapps' });
    } catch (err) {
      logDebugError('walletConnect:handleSessionDelete', err);
    }
  };

  // ---------------------------------------------------------------------------
  // DappProtocolAdapter: Connection Handling
  // ---------------------------------------------------------------------------

  async connect(
    request: ApiDappRequest,
    message: DappConnectionRequest<typeof this.protocolType>,
    requestId: number,
  ): Promise<DappConnectionResult<typeof this.protocolType>> {
    try {
      // Note: For WalletConnect, connections are initiated via handleSessionProposal
      // This method would be called if we want to programmatically initiate a connection

      await this.openExtensionPopup(true);

      this.onUpdate({
        type: 'dappLoading',
        connectionType: 'connect',
      });

      let accountId = await getCurrentAccountOrFail();
      const { network } = parseAccountId(accountId);

      const { promiseId, promise } = createDappPromise();

      const chains = await Promise.all(message.requestedChains.map(async (e) => ({
        ...e,
        network: message.transport === 'extension' ? network : e.network, // we have no useful info about network from extension request
        address: (await fetchStoredChainAccount(accountId, e.chain)).byChain[e.chain].address,
      })));

      const dapp: StoredDappConnection = {
        name: message.protocolData.params.proposer.metadata.name,
        iconUrl: message.protocolData.params.proposer.metadata.icons[0],
        protocolType: this.protocolType,
        chains,
        url: message.protocolData.params.proposer.metadata.url,
        connectedAt: Date.now(),
        wcPairingTopic: message.protocolData.params.pairingTopic,
        ...(request.isUrlEnsured && { isUrlEnsured: true }),
      };

      const uniqueId = getDappConnectionUniqueId(dapp);

      this.onUpdate({
        type: 'dappConnect',
        identifier: String(requestId),
        promiseId,
        accountId,
        dapp,
        permissions: {
          address: !!message.permissions?.isAddressRequired,
          proof: !!message.permissions?.isPasswordRequired,
        },
      });

      const promiseResult: Parameters<typeof confirmDappRequestConnect>[1] = await promise;

      accountId = promiseResult.accountId;
      request.accountId = accountId;

      await addDapp(accountId, dapp, uniqueId);

      this.onUpdate({ type: 'updateDapps' });
      this.onUpdate({ type: 'dappConnectComplete' });

      const address = (await fetchStoredChainAccount(accountId, 'solana')).byChain.solana.address;

      const namespaces = Object.entries({
        ...message.protocolData.params.requiredNamespaces,
        ...message.protocolData.params.optionalNamespaces,
      }).map((namespace) => ([
        [namespace[0]],
        {
          ...namespace[1],
          chains: namespace[1].chains || [],
          accounts: (namespace[1].chains || []).map((chain) => `${chain}:${address}`),
        },
      ]));

      const approvedNamespaces = buildApprovedNamespaces({
        proposal: message.protocolData.params,
        supportedNamespaces: Object.fromEntries(namespaces),
      });

      return {
        success: true,
        session: {
          id: String(requestId),
          protocolType: this.protocolType,
          accountId,
          dapp,
          chains,
          connectedAt: new Date().getTime(),
          protocolData: approvedNamespaces,
        },
      };
    } catch (err) {
      logDebugError('walletConnect:connect', err);
      if (message.transport === 'relay') {
        await this.walletKit.rejectSession({
          id: message.protocolData.id,
          reason: getSdkError('USER_REJECTED'),
        });
      }

      safeExec(() => {
        this.onUpdate({
          type: 'dappCloseLoading',
          connectionType: 'connect',
        });
      });

      return formatConnectError(requestId, err);
    }
  }

  async reconnect(
    request: ApiDappRequest,
    requestId: number,
  ): Promise<DappConnectionResult<typeof this.protocolType>> {
    try {
      // WalletConnect sessions are automatically restored by the SDK, but injected are not

      const { url, accountId } = await ensureRequestParams(request);

      const uniqueId = getDappConnectionUniqueId(request);
      const currentDapp = await getDapp(accountId, url, uniqueId);

      if (!currentDapp) {
        return {
          success: false,
          error: {
            code: 0,
            message: 'No dApp found',
          },
        };
      }

      await updateDapp(accountId, url, uniqueId, { connectedAt: Date.now() });

      return {
        success: true,
        session: {
          id: String(requestId),
          protocolType: this.protocolType,
          accountId,
          dapp: currentDapp,
          chains: currentDapp.chains!,
          connectedAt: new Date().getTime(),
          // reconnect is used only in injected env, so we need only `chains` field in return object
          protocolData: undefined as unknown as SessionTypes.Namespaces,
        },
      };
    } catch (err) {
      logDebugError('walletConnect:reconnect', err);
      return formatConnectError(requestId, err);
    }
  }

  async disconnect(
    request: ApiDappRequest,
    message: DappDisconnectRequest,
  ): Promise<DappMethodResult<typeof this.protocolType>> {
    let dapp: StoredDappConnection | undefined = undefined;

    const uniqueId = getDappConnectionUniqueId(request);

    try {
      const { url, accountId } = await ensureRequestParams(request);

      dapp = (await getDapp(accountId, url, uniqueId))!;

      if (!dapp) {
        throw new Error('No dApp found');
      }

      await deleteDapp(accountId, dapp.url, uniqueId);

      this.onUpdate({ type: 'updateDapps' });
    } catch (err) {
      logDebugError('walletConnect:disconnect', err);
    }

    return {
      success: true,
      result: {
        id: message.requestId,
        result: '',
      },
    };
  }

  async closeRemoteConnection(accountId: string, dapp: StoredDappConnection): Promise<void> {
    // extension dapp - only act in pageScript & storage, so we dont need to call WC
    if (!dapp.wcTopic) {
      return;
    }

    try {
      await this.walletKit.disconnectSession({
        topic: dapp.wcTopic,
        reason: getSdkError('USER_DISCONNECTED'),
      });
    } catch (err) {
      logDebugError('walletConnect:closeRemoteConnection', err);
    }
  }

  // ---------------------------------------------------------------------------
  // DappProtocolAdapter: Request Handling
  // ---------------------------------------------------------------------------

  async sendTransaction(
    request: ApiDappRequest,
    message: DappTransactionRequest<typeof this.protocolType>,
  ): Promise<DappMethodResult<typeof this.protocolType>> {
    try {
      let dapp: StoredDappConnection | undefined = undefined;
      let accountId: string | undefined = undefined;
      let accountAddress: string | undefined = undefined;

      if (message.payload.topic) {
        const byTopic = (await getDappByTopic(message.payload.topic, 'default'));

        if (!byTopic) {
          throw new Error(`No dApp found for topic ${message.payload.topic}`);
        }

        dapp = byTopic.dapp;
        accountId = byTopic.accountId;
        accountAddress = (await fetchStoredChainAccount(accountId, message.chain)).byChain[message.chain].address;
      } else {
        accountAddress = message.payload.address!;
        const uniqueId = getDappConnectionUniqueId(request);
        accountId = await getAccountIdByAddress(accountAddress, message.chain);

        dapp = (await getDapp(accountId, message.payload.url!, uniqueId))!;
      }

      const { network } = parseAccountId(accountId);

      await this.openExtensionPopup(true);

      this.onUpdate({
        type: 'dappLoading',
        connectionType: 'sendTransaction',
        accountId,
      });

      const { transfers, emulation } = await this.chainDappSupports[message.chain]!.parseTransactionForPreview!(
        message.payload.data,
        accountAddress,
        network,
      );

      const { promiseId, promise } = createDappPromise();

      this.onUpdate({
        type: 'dappSendTransactions',
        promiseId,
        accountId,
        dapp,
        operationChain: message.chain,
        transactions: transfers,
        emulation,
        validUntil: Math.floor(Date.now() / 1000 + 60 * 5),
        vestingAddress: undefined,
        shouldHideTransfers: true,
        isLegacyOutput: !message.payload.isFullTxRequested,
      });

      const signedTransactions: Parameters<
            typeof confirmDappRequestSendTransaction<typeof this.protocolType>
      >[1] = await promise;

      if (!message.payload.isSignOnly) {
        const sentTransaction = await this.chainDappSupports[message.chain]!.sendSignedTransaction!(
          signedTransactions[0].payload.base58Tx,
          network,
        );

        this.onUpdate({
          type: 'dappTransferComplete',
          accountId,
        });

        return {
          success: true,
          result: {
            result: sentTransaction,
            id: message.id,
          },
        };
      }

      this.onUpdate({
        type: 'dappTransferComplete',
        accountId,
      });

      // DApp accepts signedTx in extension and signature only in walletConnect
      const toReturn = message.payload.topic && !message.payload.isFullTxRequested
        ? signedTransactions[0].payload.signature
        : signedTransactions[0].payload.base58Tx;

      return {
        success: true,
        result: {
          result: toReturn,
          id: message.id,
        },
      };
    } catch (err) {
      logDebugError('walletConnect:sendTransaction', err);
      if (message.payload.topic) {
        const response = {
          id: Number(message.id),
          jsonrpc: '2.0',
          error: getSdkError('USER_REJECTED'),
        };
        try {
          await this.walletKit.respondSessionRequest({ topic: message.payload.topic, response });
        } catch (respondErr) {
          logDebugError('walletConnect:sendTransaction:respondSessionRequest', respondErr);
        }
      }
      return formatConnectError(Number(message.id), err);
    }
  }

  async signData(
    request: ApiDappRequest,
    message: DappSignDataRequest<typeof this.protocolType>,
  ): Promise<DappMethodResult<typeof this.protocolType>> {
    try {
      await this.openExtensionPopup(true);

      let dapp: StoredDappConnection | undefined = undefined;
      let accountId: string | undefined = undefined;

      if (message.payload.topic) {
        const byTopic = (await getDappByTopic(message.payload.topic, 'default'));

        if (!byTopic) {
          throw new Error(`No dApp found for topic ${message.payload.topic}`);
        }

        dapp = byTopic.dapp;
        accountId = byTopic.accountId;
      } else {
        const uniqueId = getDappConnectionUniqueId(request);

        accountId = await getAccountIdByAddress(message.payload.address!, message.chain);

        dapp = (await getDapp(accountId, message.payload.url!, uniqueId))!;
      }

      this.onUpdate({
        type: 'dappLoading',
        connectionType: 'signData',
        accountId,
        isSse: false,
      });

      const { promiseId, promise } = createDappPromise();

      const payloadToSign: UnifiedSignDataPayload = {
        type: 'text',
        text: message.payload.data,
      };

      this.onUpdate({
        type: 'dappSignData',
        operationChain: message.chain,
        promiseId,
        accountId,
        dapp,
        payloadToSign,
      });

      const result: Parameters<typeof confirmDappRequestSignData<typeof this.protocolType>>[1] = await promise;

      this.onUpdate({
        type: 'dappSignDataComplete',
        accountId,
      });

      if (message.payload.topic) {
        const response = {
          id: Number(message.id),
          jsonrpc: '2.0',
          result: {
            signature: result.result.signature,
          },
        };
        await this.walletKit.respondSessionRequest({ topic: message.payload.topic, response });
      }

      return {
        success: true,
        result: {
          result: result.result.signature,
          id: message.id,
        },
      };
    } catch (err) {
      logDebugError('walletConnect:signData', err);
      if (message.payload.topic) {
        const response = {
          id: Number(message.id),
          jsonrpc: '2.0',
          error: getSdkError('USER_REJECTED'),
        };

        try {
          await this.walletKit.respondSessionRequest({ topic: message.payload.topic, response });
        } catch (respondErr) {
          logDebugError('walletConnect:signData:respondSessionRequest', respondErr);
        }
      }
      return formatConnectError(Number(message.id), err);
    }
  }

  // ---------------------------------------------------------------------------
  // DappProtocolAdapter: Deep Link Handling
  // ---------------------------------------------------------------------------

  canHandleDeepLink(url: string): boolean {
    return WALLET_CONNECT_DEEP_LINK_PREFIXES.some((prefix) => url.startsWith(prefix));
  }

  async handleDeepLink(url: string): Promise<string | undefined> {
    try {
      await this.walletKit.pair({ uri: url });
    } catch (err) {
      logDebugError('walletConnect:handleDeepLink', err);
    }
    return undefined;
  }

  private async openExtensionPopup(force?: boolean) {
    if (!IS_EXTENSION || (!force && isUpdaterAlive(this.onUpdate))) {
      return false;
    }

    await callHook('onWindowNeeded');

    return true;
  }
}

// =============================================================================
// Factory
// =============================================================================

let adapterInstance: WalletConnectAdapter | undefined;

/**
 * Get or create the WalletConnect adapter instance.
 */
export function getWalletConnectAdapter(): DappProtocolAdapter {
  if (!adapterInstance) {
    adapterInstance = new WalletConnectAdapter();
  }
  return adapterInstance;
}

/**
 * Create a new WalletConnect adapter instance (for testing).
 */
export function createWalletConnectAdapter(): DappProtocolAdapter {
  return new WalletConnectAdapter();
}

async function getCurrentAccountOrFail() {
  const accountId = await getCurrentAccountId();
  if (!accountId) {
    throw new Error('No currentAccountFound');
  }
  return accountId;
}

async function getDappByTopic(topic: string, mode: 'default' | 'pairing') {
  const dapps = await getDappsState();

  if (!dapps) {
    return;
  }

  for (const byAccId of Object.entries(dapps)) {
    for (const byUrl of Object.values(byAccId[1])) {
      for (const byDappId of Object.values(byUrl)) {
        if (mode === 'pairing'
          ? byDappId.wcPairingTopic === topic
          : byDappId.wcTopic === topic
        ) {
          return { dapp: byDappId, accountId: byAccId[0] };
        }
      }
    }
  }
}

async function ensureRequestParams(
  request: ApiDappRequest,
): Promise<ApiDappRequest & { url: string; accountId: string }> {
  if (!request.url) {
    throw new Error('Missing `url` in request');
  }

  if (request.accountId) {
    return request as ApiDappRequest & { url: string; accountId: string };
  }

  const { network } = parseAccountId(await getCurrentAccountIdOrFail());
  const lastAccountId = await findLastConnectedAccount(network, request.url);
  if (!lastAccountId) {
    throw new Error('The connection is outdated, try relogin');
  }

  return {
    ...request,
    accountId: lastAccountId,
  } as ApiDappRequest & { url: string; accountId: string };
}

function formatConnectError(id: number, error: unknown): {
  success: false;
  error: DappProtocolError;
} {
  let code = 0;
  let message = 'Unhandled error';

  if (error instanceof ApiUserRejectsError) {
    code = 300;
    message = error.message;
  }

  return {
    success: false,
    error: {
      code,
      message,
    },
  };
}
