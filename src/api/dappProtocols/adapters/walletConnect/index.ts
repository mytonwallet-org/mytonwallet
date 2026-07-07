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
import { isPaymentLink, WalletKit } from '@reown/walletkit';
import { Core } from '@walletconnect/core';
import type { PaymentInfo, PaymentOption, WalletRpcAction } from '@walletconnect/pay';
import type { AuthTypes, SessionTypes } from '@walletconnect/types';
import { buildApprovedNamespaces, buildAuthObject, getSdkError, populateAuthPayload } from '@walletconnect/utils';

import type {
  confirmDappRequestConnect,
  confirmDappRequestSendTransaction,
  confirmDappRequestSignData,
} from '../../../methods';
import type {
  ApiChain,
  ApiDappRequest,
  ApiNetwork,
  EVMChain,
  OnApiUpdate,
} from '../../../types';
import type { StoredDappConnection } from '../../storage';
import type {
  DappDisconnectRequest,
  UnifiedSignDataPayload } from '../../types';
import {
  type DappConnectionRequest,
  type DappConnectionResult,
  type DappEvmRpcProxyRequest,
  type DappEvmRpcProxyResult,
  type DappMethodResult,
  type DappProtocolAdapter,
  type DappProtocolConfig,
  DappProtocolType,
  type DappSignDataRequest,
  type DappTransactionRequest,
} from '../../types';
import {
  CHAIN_IDS,
  type ChainId,
  type EthSignParams,
  type EthSignTypedDataParams,
  EVM_CHAIN_IDS,
  type EvmTransactionParams,
  type PersonalSignParams,
  type WalletCapabilities,
  type WcPayContext,
  type WcPayMerchant,
} from './types';

import {
  APP_ICON_URL,
  APP_NAME,
  APP_WEBSITE_URL,
  IS_EXTENSION,
  WALLET_CONNECT_PAY_APP_ID,
  WALLET_CONNECT_PROJECT_ID,
} from '../../../../config';
import { parseAccountId } from '../../../../util/account';
import { getDappConnectionUniqueId } from '../../../../util/getDappConnectionUniqueId';
import { logDebug, logDebugError } from '../../../../util/logs';
import safeExec from '../../../../util/safeExec';
import { pause } from '../../../../util/schedulers';
import {
  checkIsKycUrlAllowed,
  isWalletConnectPayAccountSwitch,
  isWalletConnectPayUserCancellation,
} from '../../../../util/walletConnectPay';
import chains from '../../../chains';
import { getEvmProvider } from '../../../chains/evm/util/client';
import {
  fetchStoredChainAccount,
  getAccountIdByAddress,
  getCurrentAccountIdOrFail,
} from '../../../common/accounts';
import { createDappPromise } from '../../../common/dappPromises';
import { isUpdaterAlive } from '../../../common/helpers';
import { ApiUserRejectsError } from '../../../errors';
import { callHook } from '../../../hooks';
import {
  addDapp,
  deleteDapp,
  getDapp,
  updateDapp,
} from '../../../methods/dapps';
import { resolveWalletConnectEvmSerializedTx } from './evmTransaction';
import {
  ensureRequestParams,
  formatConnectError,
  getCurrentAccountOrFail,
  getDappByTopic,
  parseWalletConnectTypedData,
  safeHost,
  urlTrustStatusStatusFromWalletConnectVerify,
} from './helpers';
import {
  authPayloadChainsToSessionChains,
  buildSessionAuthenticateProtocolData,
  caip2ToHexChainId,
  getAccountChains,
  getEip155Caip2ForEvmChain,
  getRequestedChainsForApproval,
  hexToEip155Caip2,
  namespacesToSessionChains,
  normalizeEip155HexChainId,
  WALLET_CONNECT_SUPPORTED_AUTH_METHODS,
} from './namespaces';
import {
  buildPayAccounts,
  buildPayMerchant,
  buildPayPaymentAmount,
  buildPayPaymentInfo,
  mapPayPaymentOption,
  parsePayOptionChain,
  trimPayContextToSigning,
} from './payMapping';
import { READONLY_EVM_RPC_METHODS } from './readonlyMethods';

// WalletConnect deep link patterns
const WALLET_CONNECT_DEEP_LINK_PREFIXES = [
  'wc:',
  'https://walletconnect.com/wc',
];

const EVM_TX_FINALIZATION_POLL_MS = 2000;
const EVM_TX_FINALIZATION_TIMEOUT_MS = 5 * 60 * 1000;

// Derive the EVM chain name set from the same EVM_CHAIN_IDS map the rest of the
// adapter uses; hardcoding here would silently drift when a new chain joins the
// CAIP map (multichain rule §7: chain enumerations live in declared points only).
const EVM_CHAIN_NAMES: ReadonlySet<ApiChain> = new Set(
  Object.values(EVM_CHAIN_IDS).map((entry) => entry.chain),
);

/**
 * WalletConnect v2 protocol adapter.
 */
class WalletConnectAdapter implements DappProtocolAdapter<DappProtocolType.WalletConnect> {
  readonly protocolType = DappProtocolType.WalletConnect;

  private onUpdate!: OnApiUpdate;

  private initialized = false;

  private walletKit!: IWalletKit;

  private chainDappSupports: NonNullable<DappProtocolConfig['chainDappSupports']> = {};

  // Worker-side coalescer for concurrent reconnects to the same dapp (multiple tabs/iframes of
  // one dapp converging on the worker once their per-page TTL caches expire). Page-side and
  // worker-side dedup are not redundant — they cover different fan-in points.
  private inFlightReconnects = new Map<string, Promise<DappConnectionResult<typeof this.protocolType>>>();

  private activePayContext?: WcPayContext;

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  async init(config: DappProtocolConfig): Promise<void> {
    this.onUpdate = config.onUpdate;
    this.chainDappSupports = config.chainDappSupports ?? {};

    if (this.initialized) {
      return;
    }

    if (!WALLET_CONNECT_PROJECT_ID) {
      logDebugError('WalletConnectAdapter', 'No project ID provided');
      return;
    }

    if (typeof globalThis.indexedDB === 'undefined') {
      throw new Error('WalletConnect is unavailable: indexedDB is not supported');
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
        url: APP_WEBSITE_URL,
        icons: [APP_ICON_URL],
      },
      payConfig: {
        appId: WALLET_CONNECT_PAY_APP_ID,
      },
    });

    this.walletKit.on('session_proposal', this.handleSessionProposal);
    this.walletKit.on('session_request', this.handleSessionRequest);
    this.walletKit.on('session_delete', this.handleSessionDelete);
    this.walletKit.on('session_authenticate', this.handleSessionAuthenticate);

    this.initialized = true;
  }

  async destroy(): Promise<void> {
    if (this.walletKit) {
      this.walletKit.off('session_proposal', this.handleSessionProposal);
      this.walletKit.off('session_request', this.handleSessionRequest);
      this.walletKit.off('session_delete', this.handleSessionDelete);
      this.walletKit.off('session_authenticate', this.handleSessionAuthenticate);
    }

    this.initialized = false;
    return Promise.resolve();
  }

  // ---------------------------------------------------------------------------
  // WalletConnect Event Handlers (internal)
  // ---------------------------------------------------------------------------

  /**
   * Handle session authenticate (1clickAuth) request from dApp.
   * https://docs.walletconnect.network/wallet-sdk/web/one-click-auth
   */
  private handleSessionAuthenticate = async (payload: WalletKitTypes.SessionAuthenticate) => {
    let dappUniqueId = '';
    let dappAccountId = '';
    let dappUrl = '';

    try {
      const { id, params, verifyContext, topic } = payload;
      const { requester, authPayload } = params;

      const populatedAuthPayload = populateAuthPayload({
        authPayload,
        chains: Object.keys(CHAIN_IDS),
        methods: WALLET_CONNECT_SUPPORTED_AUTH_METHODS,
      });

      if (!populatedAuthPayload.chains?.length) {
        await this.walletKit.rejectSessionAuthenticate({
          id,
          reason: getSdkError('UNSUPPORTED_CHAINS'),
        });
        return;
      }

      const requestedChains = authPayloadChainsToSessionChains(populatedAuthPayload.chains);

      if (!requestedChains.length) {
        await this.walletKit.rejectSessionAuthenticate({
          id,
          reason: getSdkError('UNSUPPORTED_CHAINS'),
        });
        return;
      }

      const connectionRequest: DappConnectionRequest = {
        protocolType: DappProtocolType.WalletConnect,
        transport: 'relay',
        requestedChains,
        permissions: {
          isAddressRequired: true,
          isPasswordRequired: false,
        },
        protocolData: buildSessionAuthenticateProtocolData(
          payload,
          populatedAuthPayload,
          verifyContext,
        ),
      };

      const request: ApiDappRequest = {
        url: requester.metadata.url,
        identifier: String(id),
      };

      const result = await this.connect(request, connectionRequest, id);

      if (!result.success) {
        return;
      }

      dappUniqueId = getDappConnectionUniqueId(result.session.dapp);
      dappAccountId = result.session.accountId;
      dappUrl = result.session.dapp.url;

      const auths = await this.signSessionAuthenticate(
        topic,
        populatedAuthPayload,
        result.session.accountId,
        dappUrl,
        id,
        result.session.chains,
      );

      const { session } = await this.walletKit.approveSessionAuthenticate({
        id,
        auths,
      });

      if (session) {
        await updateDapp(
          result.session.accountId,
          result.session.dapp.url,
          dappUniqueId,
          { wcTopic: session.topic },
        );
      }
    } catch (err) {
      logDebugError('walletConnect:handleSessionAuthenticate', err);

      try {
        await this.walletKit.rejectSessionAuthenticate({
          id: payload.id,
          reason: getSdkError('USER_REJECTED'),
        });
      } catch (rejectErr) {
        logDebugError('walletConnect:handleSessionAuthenticate:reject', rejectErr);
      }

      await deleteDapp(
        dappAccountId,
        dappUrl,
        dappUniqueId,
      );
    }
  };

  private async signSessionAuthenticate(
    topic: string,
    authPayload: AuthTypes.PayloadParams,
    accountId: string,
    dappUrl: string,
    requestId: number,
    sessionChains: { chain: ApiChain; network: ApiNetwork; address: string }[],
  ): Promise<AuthTypes.Cacao[]> {
    const chainCaip2 = authPayload.chains.find((caip2) => {
      const chainId = CHAIN_IDS[caip2];

      if (!chainId) {
        return false;
      }

      return sessionChains.some(
        (sessionChain) => sessionChain.chain === chainId.chain && sessionChain.network === chainId.network,
      );
    });

    if (!chainCaip2) {
      throw new Error('No supported chain for authentication');
    }

    const chainEntry = CHAIN_IDS[chainCaip2];
    const account = await fetchStoredChainAccount(accountId, chainEntry.chain);
    const address = account.byChain[chainEntry.chain].address;
    const iss = `${chainCaip2}:${address}`;

    const message = this.walletKit.formatAuthMessage({
      request: authPayload,
      iss,
    });

    const signResult = await this.signData(
      { url: dappUrl, accountId },
      {
        id: String(requestId),
        chain: chainEntry.chain,
        payload: {
          url: dappUrl,
          address,
          data: message,
          topic,
          isSessionAuthenticate: true,
          isEthSign: true,
        },
      },
    );

    if (!signResult.success) {
      throw new ApiUserRejectsError();
    }

    return [
      buildAuthObject(
        authPayload,
        { t: 'eip191', s: signResult.result.result },
        iss,
      ),
    ];
  };

  /**
   * Handle incoming session proposal from dApp.
   * This is called when a dApp scans QR code or follows deep link.
   */
  private handleSessionProposal = async (proposal: WalletKitTypes.SessionProposal) => {
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
    tx: string | EvmTransactionParams,
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
      case 'eth_signTransaction': {
        const paramsList = request.params as EvmTransactionParams[];
        const txParams = paramsList[0];

        if (!txParams) {
          await this.walletKit.respondSessionRequest({
            topic,
            response: {
              id,
              jsonrpc: '2.0',
              error: {
                code: -32602,
                message: 'Invalid params: missing transaction object',
              },
            },
          });
          return;
        }

        if (request.method === 'eth_signTransaction') {
          const response = await this.requestTransactionSign(
            id,
            namespace.chain,
            topic,
            byTopic.dapp.url,
            txParams,
          );

          if (!response.success) {
            return;
          }

          await this.walletKit.respondSessionRequest({
            topic,
            response: {
              id,
              jsonrpc: '2.0',
              result: response.result.result,
            },
          });
        } else {
          const message: DappTransactionRequest<typeof this.protocolType> = {
            id: String(id),
            chain: namespace.chain,
            payload: {
              topic,
              data: txParams,
            },
          };

          const response = await this.sendTransaction({ url: byTopic.dapp.url }, message);

          if (response?.success) {
            await this.walletKit.respondSessionRequest({
              topic,
              response: {
                id,
                jsonrpc: '2.0',
                result: response.result.result,
              },
            });
          }
        }
        break;
      }
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

      case 'personal_sign': {
        const [messageHex, from] = request.params as PersonalSignParams;

        const account = await fetchStoredChainAccount(byTopic.accountId, namespace.chain);
        const walletAddress = account.byChain[namespace.chain].address;

        if (chains['ethereum'].normalizeAddress(from) !== walletAddress) {
          await this.walletKit.respondSessionRequest({
            topic,
            response: {
              id,
              jsonrpc: '2.0',
              error: {
                code: 4100,
                message: 'Unauthorized',
              },
            },
          });
          break;
        }

        const message: DappSignDataRequest<typeof this.protocolType> = {
          id: String(id),
          chain: namespace.chain,
          payload: {
            topic,
            data: messageHex,
            isEthSign: true,
          },
        };

        await this.signData({ url: byTopic.dapp.url }, message);
        break;
      }

      case 'eth_sign': {
        const [from, dataHex] = request.params as EthSignParams;

        const account = await fetchStoredChainAccount(byTopic.accountId, namespace.chain);
        const walletAddress = account.byChain[namespace.chain].address;

        if (chains['ethereum'].normalizeAddress(from) !== walletAddress) {
          await this.walletKit.respondSessionRequest({
            topic,
            response: {
              id,
              jsonrpc: '2.0',
              error: {
                code: 4100,
                message: 'Unauthorized',
              },
            },
          });
          break;
        }

        const message: DappSignDataRequest<typeof this.protocolType> = {
          id: String(id),
          chain: namespace.chain,
          payload: {
            topic,
            data: dataHex,
            isEthSign: true,
          },
        };

        await this.signData({ url: byTopic.dapp.url }, message);
        break;
      }

      case 'eth_signTypedData':
      case 'eth_signTypedData_v4': {
        const [from, typedRaw] = request.params as EthSignTypedDataParams;

        const account = await fetchStoredChainAccount(byTopic.accountId, namespace.chain);
        const walletAddress = account.byChain[namespace.chain].address;

        if (chains['ethereum'].normalizeAddress(from) !== walletAddress) {
          await this.walletKit.respondSessionRequest({
            topic,
            response: {
              id,
              jsonrpc: '2.0',
              error: {
                code: 4100,
                message: 'Unauthorized',
              },
            },
          });
          break;
        }

        const eip712 = parseWalletConnectTypedData(typedRaw);

        if (!eip712) {
          await this.walletKit.respondSessionRequest({
            topic,
            response: {
              id,
              jsonrpc: '2.0',
              error: {
                code: -32602,
                message: 'Invalid typed data',
              },
            },
          });
          break;
        }

        const message: DappSignDataRequest<typeof this.protocolType> = {
          id: String(id),
          chain: namespace.chain,
          payload: {
            topic,
            eip712,
            isEthSign: true,
          },
        };

        await this.signData({ url: byTopic.dapp.url }, message);
        break;
      }

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

      case 'wallet_getCapabilities': {
        const capabilityParams = request.params as string[];

        await this.getWalletCapabilities(
          id,
          capabilityParams,
          byTopic.accountId,
          topic,
          namespace,
          chainId,
        );
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

      logDebug('walletConnect:connect:enter', {
        host: safeHost(message.protocolData.params.proposer.metadata.url),
        transport: message.transport,
      });

      await this.openExtensionPopup(true);

      this.onUpdate({
        type: 'dappLoading',
        connectionType: 'connect',
      });

      let accountId = await getCurrentAccountOrFail();
      let { network } = parseAccountId(accountId);

      const { promiseId, promise } = createDappPromise();

      let chains = getRequestedChainsForApproval(message, network);

      const urlTrustStatus = request.urlTrustStatus
        ?? (message.transport === 'relay'
          ? urlTrustStatusStatusFromWalletConnectVerify(message.protocolData.verifyContext)
          : 'verified');

      let dapp: StoredDappConnection = {
        name: message.protocolData.params.proposer.metadata.name,
        iconUrl: message.protocolData.params.proposer.metadata.icons[0],
        protocolType: this.protocolType,
        chains,
        url: message.protocolData.params.proposer.metadata.url,
        connectedAt: Date.now(),
        wcPairingTopic: message.protocolData.params.pairingTopic,
        urlTrustStatus,
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

      // Recalculate chains in case of account change from modal
      if (promiseResult.accountId !== accountId) {
        accountId = promiseResult.accountId;
        request.accountId = accountId;
      }

      network = parseAccountId(accountId).network;
      chains = await getAccountChains(message, network, accountId, message.requestedChains);
      dapp = {
        ...dapp,
        chains,
      };

      await addDapp(accountId, dapp, uniqueId);

      this.onUpdate({ type: 'updateDapps' });
      this.onUpdate({ type: 'dappConnectComplete' });

      const namespaces = Object.entries({
        ...message.protocolData.params.requiredNamespaces,
        ...message.protocolData.params.optionalNamespaces,
      }).map((namespace) => ([
        [namespace[0]],
        {
          ...namespace[1],
          chains: namespace[1].chains || [],
          accounts: (namespace[1].chains || [])
            .map((chain) =>
              `${chain}:${chains.find((c) => CHAIN_IDS[chain]?.chain === c.chain)?.address}`,
            ),
        },
      ]));

      const approvedNamespaces = buildApprovedNamespaces({
        proposal: message.protocolData.params,
        supportedNamespaces: Object.fromEntries(namespaces),
      });

      logDebug('walletConnect:connect:done', { host: safeHost(dapp.url), chains: chains.length });

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
        if (message.protocolData.isSessionAuthenticate) {
          await this.walletKit.rejectSessionAuthenticate({
            id: message.protocolData.id,
            reason: getSdkError('USER_REJECTED'),
          });
        } else {
          await this.walletKit.rejectSession({
            id: message.protocolData.id,
            reason: getSdkError('USER_REJECTED'),
          });
        }
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
    let key: string | undefined;
    try {
      // WalletConnect sessions are automatically restored by the SDK, but injected are not

      const { url, accountId } = await ensureRequestParams(request);
      const uniqueId = getDappConnectionUniqueId(request);
      key = `${accountId} ${url} ${uniqueId}`;

      const inFlight = this.inFlightReconnects.get(key);
      if (inFlight) {
        logDebug('walletConnect:reconnect:coalesced', { host: safeHost(url) });
        return await inFlight;
      }

      const promise = this.reconnectInner(url, accountId, uniqueId, requestId);
      this.inFlightReconnects.set(key, promise);
      try {
        return await promise;
      } finally {
        this.inFlightReconnects.delete(key);
      }
    } catch (err) {
      if (key) this.inFlightReconnects.delete(key);
      logDebugError('walletConnect:reconnect', err);
      return formatConnectError(requestId, err);
    }
  }

  private async reconnectInner(
    url: string,
    accountId: string,
    uniqueId: string,
    requestId: number,
  ): Promise<DappConnectionResult<typeof this.protocolType>> {
    logDebug('walletConnect:reconnect:enter', { host: safeHost(url) });

    const currentDapp = await getDapp(accountId, url, uniqueId);

    if (!currentDapp) {
      logDebug('walletConnect:reconnect:nodapp', { host: safeHost(url) });
      return {
        success: false,
        error: {
          code: 0,
          message: 'No dApp found',
        },
      };
    }

    await updateDapp(accountId, url, uniqueId, { connectedAt: Date.now() });

    logDebug('walletConnect:reconnect:done', { host: safeHost(url), chains: currentDapp.chains?.length ?? 0 });

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
  }

  async disconnect(
    request: ApiDappRequest,
    message: DappDisconnectRequest,
  ): Promise<DappMethodResult<typeof this.protocolType>> {
    let dapp: StoredDappConnection | undefined = undefined;

    const uniqueId = getDappConnectionUniqueId(request);

    logDebug('walletConnect:disconnect:enter', {
      host: safeHost(request.url),
      requestId: message.requestId,
      // Heuristic, not a contract: solanaConnectBridgeApi resets its counter to 0 before
      // sending disconnect, while the EVM bridge increments from a counter that starts at 0
      // (so its first disconnect is '1'). Breaks if either bridge's id scheme changes.
      source: message.requestId === '0' ? 'solana-standard' : 'evm-or-other',
    });

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

    logDebug('walletConnect:disconnect:done', {
      host: safeHost(request.url),
      requestId: message.requestId,
      hadDapp: !!dapp,
    });

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

        accountId = request.accountId
          ?? await getAccountIdByAddress(
            chains[message.chain].normalizeAddress(accountAddress),
            message.chain,
          );

        dapp = (await getDapp(accountId, message.payload.url!, uniqueId))!;
      }

      logDebug('walletConnect:sendTransaction:enter', {
        host: safeHost(dapp?.url),
        chain: message.chain,
        isSignOnly: !!message.payload.isSignOnly,
        hasTopic: !!message.payload.topic,
      });

      const { network } = parseAccountId(accountId);

      let serializedTxForPreview: string;

      if (message.chain !== 'solana') {
        const caip2 = getEip155Caip2ForEvmChain(message.chain as EVMChain, network);

        if (!caip2) {
          throw new Error('Unknown EVM chain/network');
        }

        const raw = message.payload.data;

        if (raw === undefined) {
          throw new Error('Invalid params: missing transaction data');
        }

        serializedTxForPreview = await resolveWalletConnectEvmSerializedTx({
          raw,
          chain: message.chain as EVMChain,
          network,
          caip2,
          signerAddress: accountAddress,
        });
      } else {
        const raw = message.payload.data;

        if (typeof raw !== 'string') {
          throw new Error('Invalid transaction data');
        }

        serializedTxForPreview = raw;
      }

      await this.openExtensionPopup(true);

      this.onUpdate({
        type: 'dappLoading',
        connectionType: 'sendTransaction',
        accountId,
      });

      const { transfers, emulation } = await this.chainDappSupports[message.chain]!.parseTransactionForPreview!(
        serializedTxForPreview,
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

      if (!Array.isArray(signedTransactions)) {
        throw new Error('MFA confirmation is not supported for WalletConnect transactions');
      }

      if (!message.payload.isSignOnly) {
        const sentTransaction = await this.chainDappSupports[message.chain]!.sendSignedTransaction!(
          signedTransactions[0].payload.signedTx,
          network,
        );

        this.onUpdate({
          type: 'dappTransferComplete',
          accountId,
        });

        logDebug('walletConnect:sendTransaction:done', { host: safeHost(dapp?.url), chain: message.chain, sent: true });

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
        : signedTransactions[0].payload.signedTx;

      logDebug('walletConnect:sendTransaction:done', { host: safeHost(dapp?.url), chain: message.chain, sent: false });

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
        const byTopic = (await getDappByTopic(
          message.payload.topic,
          message.payload.isSessionAuthenticate ? 'pairing' : 'default',
        ));

        if (!byTopic) {
          throw new Error(`No dApp found for topic ${message.payload.topic}`);
        }

        dapp = byTopic.dapp;
        accountId = byTopic.accountId;
      } else {
        const uniqueId = getDappConnectionUniqueId(request);

        // For inApp browser flow, accountId comes from the request (the wallet active in the browser session).
        // Falling back to getAccountIdByAddress would return the first wallet that owns the address, which
        // for users with multiple wallets sharing the same EVM key would resolve to the wrong account and
        // break the dapp lookup below.
        accountId = request.accountId
          ?? await getAccountIdByAddress(
            chains[message.chain].normalizeAddress(message.payload.address!),
            message.chain,
          );

        dapp = await getDapp(accountId, message.payload.url!, uniqueId);

        if (!dapp) {
          const url = message.payload.url || request.url || '';
          dapp = {
            protocolType: this.protocolType,
            url,
            name: safeHost(url),
            iconUrl: '',
            connectedAt: Date.now(),
            chains: [],
          };
        }
      }

      if (!dapp || !accountId) {
        throw new Error('walletConnect:signData: no dapp/accountId resolved');
      }

      logDebug('walletConnect:signData:enter', {
        host: safeHost(dapp.url),
        chain: message.chain,
        isEthSign: message.payload.isEthSign,
        hasEip712: !!message.payload.eip712,
        hasTopic: !!message.payload.topic,
      });

      this.onUpdate({
        type: 'dappLoading',
        connectionType: 'signData',
        accountId,
        isSse: false,
      });

      const { promiseId, promise } = createDappPromise();

      let simplePaloadToSign: UnifiedSignDataPayload;

      if (!message.payload.eip712) {
        simplePaloadToSign = {
          type: 'binary',
          bytes: message.payload.data as string,
        };
      }

      const payloadToSign: UnifiedSignDataPayload = message.payload.eip712
        ? {
          type: 'eip712',
          domain: message.payload.eip712.domain,
          types: message.payload.eip712.types,
          primaryType: message.payload.eip712.primaryType,
          message: message.payload.eip712.message,
        }
        : simplePaloadToSign!;

      logDebug('walletConnect:signData:request', {
        host: safeHost(dapp.url),
        chain: message.chain,
        isEthSign: !!message.payload.isEthSign,
        eip712Domain: message.payload.eip712?.domain?.name,
        eip712PrimaryType: message.payload.eip712?.primaryType,
        msgId: message.id,
        hasTopic: !!message.payload.topic,
      });

      this.onUpdate({
        type: 'dappSignData',
        operationChain: message.chain,
        promiseId,
        accountId,
        dapp,
        payloadToSign,
      });

      const result: Parameters<typeof confirmDappRequestSignData<typeof this.protocolType>>[1] = await promise;

      logDebug('walletConnect:signData:signed', {
        host: safeHost(dapp.url),
        chain: message.chain,
        msgId: message.id,
        signatureLength: result?.result?.signature?.length,
      });

      this.onUpdate({
        type: 'dappSignDataComplete',
        accountId,
      });

      if (message.payload.topic && !message.payload.isSessionAuthenticate) {
        // EVM personal_sign/eth_sign/eth_signTypedData* expect a plain signature hex string.
        // Solana signMessage expects { signature }.
        const signatureResult = message.payload.isEthSign
          ? result.result.signature
          : { signature: result.result.signature };

        const response = {
          id: Number(message.id),
          jsonrpc: '2.0',
          result: signatureResult,
        };

        await this.walletKit.respondSessionRequest({ topic: message.payload.topic, response });
      }

      logDebug('walletConnect:signData:done', { host: safeHost(dapp.url), chain: message.chain });

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

  async proxyEvmRpc(
    request: ApiDappRequest,
    message: DappEvmRpcProxyRequest,
  ): Promise<DappEvmRpcProxyResult> {
    if (!READONLY_EVM_RPC_METHODS.has(message.method)) {
      return {
        success: false,
        error: { code: -32601, message: `Method not in readonly proxy whitelist: ${message.method}` },
      };
    }
    if (!EVM_CHAIN_NAMES.has(message.chain)) {
      return {
        success: false,
        error: { code: -32602, message: `Not an EVM chain: ${message.chain}` },
      };
    }
    try {
      const { accountId } = await ensureRequestParams(request);
      const { network } = parseAccountId(accountId);
      const provider = getEvmProvider(network, message.chain as EVMChain);
      const params = Array.isArray(message.params) ? message.params : [];
      const result = await provider.send(message.method, params);
      return { success: true, result };
    } catch (err) {
      logDebugError('walletConnect:proxyEvmRpc', err);
      const code = (err as { code?: number })?.code ?? -32603;
      const errMessage = (err as { message?: string })?.message ?? 'RPC error';
      return { success: false, error: { code, message: errMessage } };
    }
  }

  async getWalletCapabilities(
    id: number,
    params: string[],
    accountId: string,
    topic: string,
    namespace: ChainId,
    chainId: string,
  ): Promise<void> {
    const requestedAddress = params[0];

    const account = await fetchStoredChainAccount(accountId, namespace.chain);

    const walletAddress = account.byChain[namespace.chain].address;

    if (requestedAddress.toLowerCase() !== walletAddress.toLowerCase()) {
      await this.walletKit.respondSessionRequest({
        topic,
        response: {
          id,
          jsonrpc: '2.0',
          error: {
            code: 4100,
            message: 'Unauthorized',
          },
        },
      });
      return;
    }

    const chainIdHexList = params[1];
    let queriedHexChainIds: string[];

    if (Array.isArray(chainIdHexList) && chainIdHexList.length > 0) {
      try {
        queriedHexChainIds = chainIdHexList.map((e) => {
          if (typeof e !== 'string') {
            throw new Error('invalid');
          }
          return normalizeEip155HexChainId(e);
        });
      } catch {
        await this.walletKit.respondSessionRequest({
          topic,
          response: {
            id,
            jsonrpc: '2.0',
            error: {
              code: -32602,
              message: 'Invalid params: invalid chain id',
            },
          },
        });
        return;
      }
    } else {
      queriedHexChainIds = [caip2ToHexChainId(chainId)];
    }

    // TODO: set actual capabilities
    const result: Record<string, WalletCapabilities> = {};

    for (const hex of queriedHexChainIds) {
      const caip2 = hexToEip155Caip2(hex);
      if (!EVM_CHAIN_IDS[caip2]) {
        continue;
      }
      result[hex] = {
        atomic: { status: 'unsupported' },
      };
    }

    await this.walletKit.respondSessionRequest({
      topic,
      response: {
        id,
        jsonrpc: '2.0',
        result,
      },
    });
  }

  // ---------------------------------------------------------------------------
  // DappProtocolAdapter: Deep Link Handling
  // ---------------------------------------------------------------------------

  canHandleDeepLink(url: string): boolean {
    return WALLET_CONNECT_DEEP_LINK_PREFIXES.some((prefix) => url.startsWith(prefix))
      || isPaymentLink(url);
  }

  async handleDeepLink(url: string): Promise<string | undefined> {
    try {
      if (isPaymentLink(url)) {
        await this.processPayment(url);
      } else {
        await this.walletKit.pair({ uri: url });
      }
    } catch (err) {
      logDebugError('walletConnect:handleDeepLink', err);
    }
    return undefined;
  }

  async processPayment(paymentLink: string, accountId?: string) {
    try {
      const resolvedAccountId = accountId ?? await getCurrentAccountIdOrFail();
      await this.openExtensionPopup(true);

      const payAccounts = await buildPayAccounts(resolvedAccountId);
      let selectedOption: PaymentOption;
      let paymentId: string;

      if (payAccounts.length === 0) {
        const fakePayAccounts = await buildPayAccounts(resolvedAccountId, true);

        const previewOptions = await this.walletKit.pay.getPaymentOptions({
          paymentLink,
          accounts: fakePayAccounts,
          includePaymentInfo: true,
        });

        if ('resultInfo' in previewOptions && previewOptions.resultInfo) {
          logDebug('walletConnect:processPayment:alreadyCompleted', { paymentId: previewOptions.paymentId });

          return previewOptions;
        }

        ({ option: selectedOption, paymentId } = await this.showPayOptionSelection(
          paymentLink,
          resolvedAccountId,
          previewOptions.paymentId,
          [],
          buildPayMerchant(previewOptions.info?.merchant),
          previewOptions.info,
          true,
        ));
      } else {
        const options = await this.walletKit.pay.getPaymentOptions({
          paymentLink,
          accounts: payAccounts,
          includePaymentInfo: true,
        });

        if ('resultInfo' in options && options.resultInfo) {
          logDebug('walletConnect:processPayment:alreadyCompleted', { paymentId: options.paymentId });

          return options;
        }

        if (options.info?.expiresAt && options.info.expiresAt * 1000 < Date.now()) {
          throw new Error('Payment has expired');
        }

        ({ option: selectedOption, paymentId } = await this.showPayOptionSelection(
          paymentLink,
          resolvedAccountId,
          options.paymentId,
          options.options,
          buildPayMerchant(options.info?.merchant),
          options.info,
        ));
      }

      const payAccountId = this.activePayContext!.accountId;

      const isOptionExpired = selectedOption?.expiresAt
        && ((selectedOption.expiresAt * 1000) + 10_000) < Date.now();

      // If the option is expired, we need to refetch the options and find the same option.
      // Take 10 seconds of safety margin to avoid expiration during requests/signing
      if (isOptionExpired) {
        const refetchedPayAccounts = await buildPayAccounts(payAccountId);
        const refetchedOptions = await this.walletKit.pay.getPaymentOptions({
          paymentLink,
          accounts: refetchedPayAccounts,
          includePaymentInfo: true,
        });

        selectedOption = refetchedOptions.options
          .find((option) =>
            option.amount.unit === selectedOption.amount.unit
            && option.account === selectedOption.account,
          )!;

        if (!selectedOption) {
          throw new Error('No payment option found after refetch');
        }

        paymentId = refetchedOptions.paymentId;
      }

      const actions = await this.walletKit.pay.getRequiredPaymentActions({
        paymentId,
        optionId: selectedOption.id,
      });

      const containsApprove = actions.some((action) =>
        action.walletRpc.method === 'eth_sendTransaction' && actions.length > 1,
      );

      const operationChain = parsePayOptionChain(selectedOption.account);

      if (!operationChain) {
        throw new Error('Unsupported payment chain');
      }

      try {
        let signatures: string[];

        if (containsApprove) {
          signatures = await this.signPayActionsWithApprove(actions, operationChain);
        } else {
          signatures = [];

          for (const action of actions) {
            signatures.push(await this.signPayAction(action.walletRpc));
          }

          this.onUpdate({
            type: 'walletConnectPayProcessing',
            accountId: payAccountId,
            merchant: this.activePayContext!.merchant,
            operationChain,
          });
        }

        let result = await this.walletKit.pay.confirmPayment({
          paymentId,
          optionId: selectedOption.id,
          signatures,
        });

        while (!result.isFinal) {
          await pause(result.pollInMs ?? 2000);

          result = await this.walletKit.pay.confirmPayment({
            paymentId,
            optionId: selectedOption.id,
            signatures,
          });
        }

        if (result.status !== 'succeeded') {
          this.onUpdate({ type: 'walletConnectPayCloseLoading' });

          this.onUpdate({
            type: 'showError',
            error: `Payment ${result.status}`,
          });

          throw new Error(`Payment ${result.status}`);
        }

        this.onUpdate({
          type: 'walletConnectPayPaymentComplete',
          accountId: payAccountId,
          merchant: this.activePayContext!.merchant,
          operationChain,
          txId: result.info?.txId,
          paymentAmount: result.info?.optionAmount
            ? buildPayPaymentAmount(result.info.optionAmount)
            : undefined,
        });

        logDebug('walletConnect:processPayment:done', {
          paymentId,
          status: result.status,
          txId: result.info?.txId,
        });

        return result;
      } finally {
        this.activePayContext = undefined;
      }
    } catch (error) {
      logDebugError('walletConnect:processPayment', error);

      this.activePayContext = undefined;
      this.onUpdate({ type: 'walletConnectPayCloseLoading' });

      if (!isWalletConnectPayUserCancellation(error) && !isWalletConnectPayAccountSwitch(error)) {
        this.onUpdate({
          type: 'showError',
          error: error instanceof Error ? error.message : String(error),
        });
      }

      throw error;
    }
  }

  private async signPayAction(action: WalletRpcAction) {
    const { chainId, method, params } = action;
    const chainEntry = CHAIN_IDS[chainId];

    if (!chainEntry) {
      throw new Error(`Unsupported Pay chain: ${chainId}`);
    }

    const parsedParams = JSON.parse(params) as unknown;
    const namespace = chainId.split(':')[0];

    switch (namespace) {
      case 'eip155':
        return this.signPayEvmAction(chainEntry.chain, method, parsedParams);
      case 'solana':
        return this.signPaySolanaAction(method, parsedParams);
      default:
        throw new Error(`Unsupported Pay namespace: ${namespace}`);
    }
  }

  private async signPayActionsWithApprove(
    actions: Awaited<ReturnType<IWalletKit['pay']['getRequiredPaymentActions']>>,
    operationChain: ApiChain,
  ): Promise<string[]> {
    const signDataAction = actions.find((action) => action.walletRpc.method === 'eth_signTypedData_v4');
    const approveAction = actions.find((action) => action.walletRpc.method === 'eth_sendTransaction');

    if (!signDataAction || !approveAction) {
      throw new Error('Invalid approve payment actions');
    }

    const signDataChainEntry = CHAIN_IDS[signDataAction.walletRpc.chainId];
    const approveChainEntry = CHAIN_IDS[approveAction.walletRpc.chainId];

    if (!signDataChainEntry || !approveChainEntry) {
      throw new Error('Unsupported Pay chain');
    }

    const signDataParams = JSON.parse(signDataAction.walletRpc.params) as unknown;
    const approveParams = JSON.parse(approveAction.walletRpc.params) as EvmTransactionParams[];

    const { signDataSignature, approveTxHash } = await this.processPaySignDataWithApprove(
      signDataChainEntry.chain,
      signDataParams,
      approveChainEntry.chain,
      approveParams[0],
      operationChain,
    );

    return actions.map((action) => {
      switch (action.walletRpc.method) {
        case 'eth_signTypedData_v4':
          return signDataSignature;
        case 'eth_sendTransaction':
          return approveTxHash;
        default:
          throw new Error(`Unsupported Pay action in approve flow: ${action.walletRpc.method}`);
      }
    });
  }

  private async signPayEvmAction(
    chain: ApiChain,
    method: string,
    parsedParams: unknown,
  ) {
    switch (method) {
      case 'personal_sign':
      case 'eth_sign':
      case 'eth_signTypedData_v4':
        return this.processPaySignData(chain, parsedParams, method);
      case 'eth_signTransaction': {
        const txParams = parsedParams as EvmTransactionParams[];

        return this.processPayTransaction(
          chain,
          txParams[0],
          true,
        );
      }

      case 'eth_sendTransaction': {
        const txParams = parsedParams as EvmTransactionParams[];

        return this.processPayTransaction(
          chain,
          txParams[0],
          false,
        );
      }

      default:
        throw new Error(`Unsupported Pay EVM RPC method: ${method}`);
    }
  }

  private async signPaySolanaAction(
    method: string,
    parsedParams: unknown,
  ) {
    switch (method) {
      case 'solana_signTransaction': {
        const paramsList = parsedParams as Array<{ transaction: string }>;
        const transaction = paramsList[0]?.transaction;

        if (!transaction) {
          throw new Error('Invalid params: missing transaction');
        }

        return this.processPaySolanaTransaction(transaction);
      }

      default:
        throw new Error(`Unsupported Pay Solana RPC method: ${method}`);
    }
  }

  private async processPaySignDataWithApprove(
    signDataChain: ApiChain,
    signDataParams: unknown,
    approveChain: ApiChain,
    approveTxParams: EvmTransactionParams,
    operationChain: ApiChain,
  ): Promise<{ signDataSignature: string; approveTxHash: string }> {
    const ctx = this.activePayContext;

    if (!ctx) {
      throw new Error('walletConnect:processPaySignDataWithApprove: no active pay context');
    }

    const { accountId, merchant } = ctx;
    const account = await fetchStoredChainAccount(accountId, signDataChain);

    const walletAddress = account.byChain[signDataChain].address;
    const { network } = parseAccountId(accountId);

    const payloadToSign = this.buildPaySignDataPayload(
      signDataParams,
      walletAddress,
      'eth_signTypedData_v4',
    );

    const approveAccount = await fetchStoredChainAccount(accountId, approveChain);
    const approveWalletAddress = approveAccount.byChain[approveChain].address;
    const caip2 = getEip155Caip2ForEvmChain(approveChain as EVMChain, network);

    if (!caip2) {
      throw new Error('Unknown EVM chain/network');
    }

    const serializedTxForPreview = await resolveWalletConnectEvmSerializedTx({
      raw: approveTxParams,
      chain: approveChain as EVMChain,
      network,
      caip2,
      signerAddress: approveWalletAddress,
    });

    const { transfers: approveTransactions } = await this.chainDappSupports[approveChain]!.parseTransactionForPreview!(
      serializedTxForPreview,
      approveWalletAddress,
      network,
    );

    try {
      await this.openExtensionPopup(true);

      this.onUpdate({
        type: 'walletConnectPayLoading',
        accountId,
      });

      const { promiseId, promise } = createDappPromise();
      const approveValidUntil = Math.floor(Date.now() / 1000 + 60 * 5);

      this.onUpdate({
        type: 'walletConnectPaySignData',
        promiseId,
        accountId,
        merchant,
        operationChain: signDataChain,
        payloadToSign,
        paymentInfo: ctx.paymentInfo,
        paymentOption: ctx.paymentOption,
        containsApprove: true,
        approveOperationChain: approveChain,
        approveTransactions,
        approveValidUntil,
      });

      const result = await promise as {
        signDataSignature: string;
        signedApproveTransactions: Parameters<
          typeof confirmDappRequestSendTransaction<DappProtocolType.WalletConnect>
        >[1];
      };

      if (!Array.isArray(result.signedApproveTransactions)) {
        throw new Error('MFA confirmation is not supported for WalletConnect Pay transactions');
      }

      const signedApproveTx = result.signedApproveTransactions[0].payload.signedTx;
      if (typeof signedApproveTx !== 'string') {
        throw new Error('Invalid signed approve transaction');
      }

      this.onUpdate({
        type: 'walletConnectPayProcessing',
        accountId,
        merchant,
        operationChain,
      });

      const approveTxHash = await this.chainDappSupports[approveChain]!.sendSignedTransaction!(
        signedApproveTx,
        network,
      );

      const finalizedApproveTxHash = await this.waitForEvmTransactionFinalization(
        network,
        approveChain as EVMChain,
        approveTxHash,
      );

      return {
        signDataSignature: result.signDataSignature,
        approveTxHash: finalizedApproveTxHash,
      };
    } catch (err) {
      logDebugError('walletConnect:processPaySignDataWithApprove', err);
      this.onUpdate({ type: 'walletConnectPayCloseLoading' });

      throw err;
    }
  }

  private buildPaySignDataPayload(
    params: unknown,
    walletAddress: string,
    method: string,
  ): UnifiedSignDataPayload {
    switch (method) {
      case 'eth_signTypedData_v4': {
        const [from, typedRaw] = params as EthSignTypedDataParams;

        if (chains['ethereum'].normalizeAddress(from) !== walletAddress) {
          throw new ApiUserRejectsError('Unauthorized signer address');
        }

        const eip712 = parseWalletConnectTypedData(typedRaw);

        if (!eip712) {
          throw new Error('Invalid typed data');
        }

        return {
          type: 'eip712',
          domain: eip712.domain,
          types: eip712.types,
          primaryType: eip712.primaryType,
          message: eip712.message,
        };
      }

      case 'personal_sign': {
        const [messageHex, from] = params as PersonalSignParams;

        if (chains['ethereum'].normalizeAddress(from) !== walletAddress) {
          throw new ApiUserRejectsError('Unauthorized signer address');
        }

        return {
          type: 'binary',
          bytes: messageHex,
        };
      }

      case 'eth_sign': {
        const [from, dataHex] = params as EthSignParams;

        if (chains['ethereum'].normalizeAddress(from) !== walletAddress) {
          throw new ApiUserRejectsError('Unauthorized signer address');
        }

        return {
          type: 'binary',
          bytes: dataHex,
        };
      }

      default:
        throw new Error(`Unsupported Pay sign method: ${method}`);
    }
  }

  private async waitForEvmTransactionFinalization(
    network: ApiNetwork,
    chain: EVMChain,
    txHash: string,
  ): Promise<string> {
    const provider = getEvmProvider(network, chain);
    const startedAt = Date.now();

    while (Date.now() - startedAt < EVM_TX_FINALIZATION_TIMEOUT_MS) {
      const transaction = await provider.getTransaction(txHash);

      if (transaction?.blockNumber) {
        return txHash;
      }

      await pause(EVM_TX_FINALIZATION_POLL_MS);
    }

    throw new Error('Transaction finalization timeout');
  }

  private async processPaySignData(
    chain: ApiChain,
    params: unknown,
    method: string,
  ): Promise<string> {
    const ctx = this.activePayContext;

    if (!ctx) {
      throw new Error('walletConnect:processPaySignData: no active pay context');
    }

    const { accountId, merchant } = ctx;
    const account = await fetchStoredChainAccount(accountId, chain);
    const walletAddress = account.byChain[chain].address;
    const payloadToSign = this.buildPaySignDataPayload(params, walletAddress, method);

    try {
      await this.openExtensionPopup(true);

      this.onUpdate({
        type: 'walletConnectPayLoading',
        accountId,
      });

      const { promiseId, promise } = createDappPromise();

      this.onUpdate({
        type: 'walletConnectPaySignData',
        promiseId,
        accountId,
        merchant,
        operationChain: chain,
        payloadToSign,
        paymentInfo: ctx.paymentInfo,
        paymentOption: ctx.paymentOption,
      });

      const result: Parameters<typeof confirmDappRequestSignData<typeof this.protocolType>>[1] = await promise;

      return result.result.signature;
    } catch (err) {
      logDebugError('walletConnect:processPaySignData', err);

      this.onUpdate({ type: 'walletConnectPayCloseLoading' });

      throw err;
    }
  }

  private async processPayTransaction(
    chain: ApiChain,
    txParams: EvmTransactionParams,
    isSignOnly: boolean,
  ): Promise<string> {
    const ctx = this.activePayContext;

    if (!ctx) {
      throw new Error('walletConnect:processPayTransaction: no active pay context');
    }

    const { accountId, merchant } = ctx;
    const account = await fetchStoredChainAccount(accountId, chain);
    const walletAddress = account.byChain[chain].address;
    const { network } = parseAccountId(accountId);

    try {
      const caip2 = getEip155Caip2ForEvmChain(chain as EVMChain, network);

      if (!caip2) {
        throw new Error('Unknown EVM chain/network');
      }

      const serializedTxForPreview = await resolveWalletConnectEvmSerializedTx({
        raw: txParams,
        chain: chain as EVMChain,
        network,
        caip2,
        signerAddress: walletAddress,
      });

      await this.openExtensionPopup(true);

      this.onUpdate({
        type: 'walletConnectPayLoading',
        accountId,
      });

      const { transfers, emulation } = await this.chainDappSupports[chain]!.parseTransactionForPreview!(
        serializedTxForPreview,
        walletAddress,
        network,
      );

      const { promiseId, promise } = createDappPromise();

      this.onUpdate({
        type: 'walletConnectPaySignTransaction',
        promiseId,
        accountId,
        merchant,
        operationChain: chain,
        transactions: transfers,
        emulation,
        paymentInfo: ctx.paymentInfo,
        paymentOption: ctx.paymentOption,
        validUntil: Math.floor(Date.now() / 1000 + 60 * 5),
        isSignOnly,
        isLegacyOutput: isSignOnly,
      });

      const signedTransactions: Parameters<
        typeof confirmDappRequestSendTransaction<typeof this.protocolType>
      >[1] = await promise;

      if (!Array.isArray(signedTransactions)) {
        throw new Error('MFA confirmation is not supported for WalletConnect Pay transactions');
      }

      if (!isSignOnly) {
        const sentTransaction = await this.chainDappSupports[chain]!.sendSignedTransaction!(
          signedTransactions[0].payload.signedTx,
          network,
        );

        return sentTransaction;
      }

      return signedTransactions[0].payload.signature;
    } catch (err) {
      logDebugError('walletConnect:processPayTransaction', err);
      this.onUpdate({ type: 'walletConnectPayCloseLoading' });
      throw err;
    }
  }

  private async processPaySolanaTransaction(
    transaction: string,
  ): Promise<string> {
    const ctx = this.activePayContext;

    if (!ctx) {
      throw new Error('walletConnect:processPaySolanaTransaction: no active pay context');
    }

    const { accountId, merchant } = ctx;
    const chain: ApiChain = 'solana';
    const account = await fetchStoredChainAccount(accountId, chain);
    const walletAddress = account.byChain[chain].address;
    const { network } = parseAccountId(accountId);

    try {
      await this.openExtensionPopup(true);

      this.onUpdate({
        type: 'walletConnectPayLoading',
        accountId,
      });

      const { transfers, emulation } = await this.chainDappSupports[chain]!.parseTransactionForPreview!(
        transaction,
        walletAddress,
        network,
      );

      const { promiseId, promise } = createDappPromise();

      this.onUpdate({
        type: 'walletConnectPaySignTransaction',
        promiseId,
        accountId,
        merchant,
        operationChain: chain,
        transactions: transfers,
        emulation,
        paymentInfo: ctx.paymentInfo,
        paymentOption: ctx.paymentOption,
        validUntil: Math.floor(Date.now() / 1000 + 60 * 5),
        isSignOnly: true,
        isLegacyOutput: false,
        shouldHideTransfers: true,
      });

      const signedTransactions: Parameters<
        typeof confirmDappRequestSendTransaction<typeof this.protocolType>
      >[1] = await promise;

      if (!Array.isArray(signedTransactions)) {
        throw new Error('MFA confirmation is not supported for WalletConnect Pay transactions');
      }

      return signedTransactions[0].payload.signedTx;
    } catch (err) {
      logDebugError('walletConnect:processPaySolanaTransaction', err);
      this.onUpdate({ type: 'walletConnectPayCloseLoading' });

      throw err;
    }
  }

  async refreshPayOptionSelection(paymentLink: string, accountId: string, promiseId: string) {
    if (this.activePayContext?.promiseId !== promiseId) {
      return;
    }

    this.activePayContext.accountId = accountId;

    const payAccounts = await buildPayAccounts(accountId);

    if (payAccounts.length === 0) {
      this.activePayContext.paymentOptions = [];

      this.onUpdate({
        type: 'walletConnectPayOptionSelection',
        promiseId,
        paymentLink,
        accountId,
        merchant: this.activePayContext.merchant,
        paymentInfo: this.activePayContext.paymentInfo,
        options: [],
        isLoading: false,
        shouldSwitchWallet: true,
      });

      return;
    }

    const options = await this.walletKit.pay.getPaymentOptions({
      paymentLink,
      accounts: payAccounts,
      includePaymentInfo: true,
    });

    if ('resultInfo' in options && options.resultInfo) {
      logDebug('walletConnect:processPayment:alreadyCompleted', { paymentId: options.paymentId });
      return;
    }

    this.activePayContext.paymentId = options.paymentId;
    this.activePayContext.paymentOptions = options.options;
    this.activePayContext.merchant = buildPayMerchant(options.info?.merchant);
    this.activePayContext.paymentInfo = buildPayPaymentInfo(options.info);

    this.onUpdate({
      type: 'walletConnectPayOptionSelection',
      promiseId,
      paymentLink,
      accountId,
      merchant: this.activePayContext.merchant,
      paymentInfo: this.activePayContext.paymentInfo,
      options: options.options.map((option) => mapPayPaymentOption(option)),
      isLoading: false,
      shouldSwitchWallet: false,
    });
  }

  private async showPayOptionSelection(
    paymentLink: string,
    accountId: string,
    paymentId: string,
    paymentOptions: PaymentOption[],
    merchant: WcPayMerchant,
    paymentInfo?: Pick<PaymentInfo, 'expiresAt' | 'amount'>,
    shouldSwitchWallet = false,
  ): Promise<{ option: PaymentOption; paymentId: string }> {
    const { promiseId, promise } = createDappPromise();

    const normalizedPaymentInfo = buildPayPaymentInfo(paymentInfo);

    this.activePayContext = {
      accountId,
      paymentId,
      merchant,
      paymentInfo: normalizedPaymentInfo,
      promiseId,
      paymentLink,
      paymentOptions,
    };

    this.onUpdate({
      type: 'walletConnectPayOptionSelection',
      promiseId,
      paymentLink,
      accountId,
      merchant,
      paymentInfo: normalizedPaymentInfo,
      options: paymentOptions.map((option) => mapPayPaymentOption(option)),
      isLoading: false,
      shouldSwitchWallet,
    });

    try {
      const optionId = await promise;
      const selectedOption = this.activePayContext.paymentOptions?.find((option) => option.id === optionId);

      if (!selectedOption) {
        throw new Error('Invalid payment option selected');
      }

      this.activePayContext = trimPayContextToSigning(this.activePayContext, selectedOption);

      if (selectedOption.collectData?.url) {
        await this.showPayDataCollection(selectedOption.collectData.url);
      }

      return {
        option: selectedOption,
        paymentId: this.activePayContext.paymentId,
      };
    } catch (error) {
      this.activePayContext = undefined;

      throw error;
    } finally {
      this.onUpdate({ type: 'walletConnectPayOptionSelectionComplete' });
    }
  }

  private async showPayDataCollection(url: string): Promise<void> {
    if (!checkIsKycUrlAllowed(url)) {
      throw new Error('Invalid WalletConnect Pay collect URL');
    }

    const { promiseId, promise } = createDappPromise();

    this.onUpdate({ type: 'walletConnectPayDataCollection', promiseId, url });

    try {
      await promise;
    } finally {
      this.onUpdate({ type: 'walletConnectPayDataCollectionComplete' });
    }
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
