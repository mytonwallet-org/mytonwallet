/**
 * TON Connect Protocol Adapter
 *
 * Implements DappProtocolAdapter for TON Connect protocol.
 * This adapter wraps the existing TON Connect implementation to conform
 * to the unified dApp protocol interface.
 *
 * Key responsibilities:
 * - Handle TON Connect connection requests
 * - Process sendTransaction and signData requests
 * - Manage SSE bridge connections
 * - Convert between TON Connect types and unified types
 */

import { Cell } from '@ton/core';
import type {
  AppRequest,
  ConnectEvent,
  ConnectRequest,
  DisconnectEvent,
  RpcMethod,
  RpcRequests,
  TonProofItemReplySuccess,
} from '@tonconnect/protocol';
import { type ConnectItemReply } from '@tonconnect/protocol';
import nacl, { randomBytes } from 'tweetnacl';

import type {
  ApiCheckMultiTransactionDraftResult,
  ApiEmulationWithFallbackResult,
  TonTransferParams,
} from '../../../chains/ton/types';
import type {
  confirmDappRequestSendTransaction,
  confirmDappRequestSignData,
} from '../../../methods';
import type {
  ApiAnyDisplayError,
  ApiDappConnectionType,
  ApiDappTransfer,
  ApiNetwork,
  ApiParsedPayload,
  ApiSseOptions,
} from '../../../types';
import type { DappProtocolError } from '../../errors';
import type { StoredDappConnection } from '../../storage';
import type {
  DappConnectionRequest,
  DappConnectionResult,
  DappDisconnectRequest,
  DappMetadata,
  DappMethodResult,
  DappProtocolAdapter,
  DappProtocolConfig,
  DappSignDataRequest,
  DappTransactionRequest,
} from '../../types';
import type { TonConnectProof, TonConnectTransactionMessage } from './types';
import {
  ApiCommonError,
  type ApiDappRequest,
  type ApiTonWallet,
  ApiTransactionDraftError,
  ApiTransactionError,
  type OnApiUpdate,
} from '../../../types';
import { DappProtocolType } from '../../types';
import { CHAIN } from './types';

import { IS_CAPACITOR, IS_EXTENSION, SSE_BRIDGE_URL, TONCOIN } from '../../../../config';
import { parseAccountId } from '../../../../util/account';
import { areDeepEqual } from '../../../../util/areDeepEqual';
import { bigintDivideToNumber } from '../../../../util/bigint';
import {
  TONCONNECT_PROTOCOL,
  TONCONNECT_PROTOCOL_SELF,
  TONCONNECT_UNIVERSAL_URL,
} from '../../../../util/deeplink/constants';
import { fetchJsonWithProxy, handleFetchErrors } from '../../../../util/fetch';
import { getDappConnectionUniqueId } from '../../../../util/getDappConnectionUniqueId';
import { extractKey, pick } from '../../../../util/iteratees';
import { logDebug, logDebugError } from '../../../../util/logs';
import safeExec from '../../../../util/safeExec';
import { getMaxMessagesInTransaction } from '../../../../util/ton/transfer';
import { tonConnectGetDeviceInfo } from '../../../../util/tonConnectEnvironment';
import { checkMultiTransactionDraft, sendSignedTransactions } from '../../../chains/ton/transfer';
import { parsePayloadBase64 } from '../../../chains/ton/util/metadata';
import { getIsRawAddress, getWalletPublicKey, toBase64Address, toRawAddress } from '../../../chains/ton/util/tonCore';
import { getContractInfo, getWalletStateInit } from '../../../chains/ton/wallet';
import {
  fetchStoredChainAccount,
  getCurrentAccountId,
  getCurrentAccountIdOrFail,
  getCurrentNetwork,
  waitLogin,
} from '../../../common/accounts';
import { getKnownAddressInfo } from '../../../common/addresses';
import { createDappPromise } from '../../../common/dappPromises';
import { isUpdaterAlive } from '../../../common/helpers';
import { bytesToHex, hexToBytes } from '../../../common/utils';
import { ApiServerError, ApiUserRejectsError } from '../../../errors';
import { callHook } from '../../../hooks';
import {
  type confirmDappRequestConnect,
  createLocalActivitiesFromEmulation,
  createLocalTransactions,
} from '../../../methods';
import {
  addDapp,
  deleteDapp,
  findLastConnectedAccount,
  getDapp,
  getDappsState,
  getSseLastEventId,
  setSseLastEventId,
  updateDapp,
} from '../../../methods/dapps';
import {
  BadRequestError,
  CONNECT_EVENT_ERROR_CODES,
  ManifestContentError,
  SEND_TRANSACTION_ERROR_CODES,
  TonConnectError,
  UnknownAppError,
  UnknownError,
} from './errors';
import {
  getTransferActualToAddress,
  isTransferPayloadDangerous,
  isValidString,
  isValidUrl,
  transformTonConnectMessageToUnified,
  transformUnifiedMethodResponseToTonConnect,
} from './utils';

const BLANK_GIF_DATA_URL = 'data:image/gif;base64,R0lGODlhAQABAAAAACH5BAEKAAEALAAAAAABAAEAAAICTAEAOw==';

// The `empty` strategy - a trick to solve the problem of long network connection initialization
// in the Capacitor version of the app when it resumes from the background.
// In this case, the client should show a loader, and once the real SSE connection starts,
// the loader will be hidden.
type ReturnStrategy = 'back' | 'none' | 'empty' | (string & {});
const ALLOWED_SSE_METHODS = new Set<RpcMethod>(['sendTransaction', 'disconnect', 'signData']);

const TTL_SEC = 300;
const NONCE_SIZE = 24;
const MAX_CONFIRM_DURATION = 60 * 1000;
const SHOULD_SHOW_LOADER_ON_SSE_START = IS_CAPACITOR;

type SseDapp = {
  accountId: string;
  url: string;
} & ApiSseOptions;

/**
 * TON Connect protocol adapter.
 */
class TonConnectAdapter implements DappProtocolAdapter<DappProtocolType.TonConnect> {
  readonly protocolType = DappProtocolType.TonConnect;

  private onUpdate!: OnApiUpdate;

  private resolveInit!: AnyFunction;
  private initPromise: Promise<unknown>;

  private initialized = false;

  private sseEventSource?: EventSource;

  private delayedReturnParams: {
    validUntil: number;
    url: string;
    isFromInAppBrowser?: boolean;
  } | undefined;

  private sseDapps: SseDapp[] = [];

  constructor() {
    this.initPromise = new Promise((resolve) => {
      this.resolveInit = resolve;
    });
  }

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  async init(config: DappProtocolConfig) {
    if (this.initialized) {
      return;
    }

    this.onUpdate = config.onUpdate;

    this.resolveInit();

    if (config.env.isSseSupported) {
      await this.resetupRemoteConnection();
    }

    this.initialized = true;
  }

  async destroy() {
    if (!this.sseEventSource) return;

    safeExec(() => {
      this.sseEventSource!.close();
    });
    this.sseEventSource = undefined;

    this.initialized = false;

    // emulate async method
    return Promise.resolve();
  }

  // ---------------------------------------------------------------------------
  // Connection Handling
  // ---------------------------------------------------------------------------

  async connect(
    request: ApiDappRequest,
    message: DappConnectionRequest<typeof this.protocolType>,
    requestId: number,
  ): Promise<DappConnectionResult<typeof this.protocolType>> {
    try {
      await this.openExtensionPopup(true);

      this.onUpdate({
        type: 'dappLoading',
        connectionType: 'connect',
        isSse: request && 'sseOptions' in request,
      });

      const dappMetadata = await fetchDappMetadata(message.protocolData.manifestUrl);
      const url = request.url || dappMetadata.url;
      const addressItem = message.protocolData.items.find(({ name }) => name === 'ton_addr');
      const proofItem = message.protocolData.items.find(({ name }) => name === 'ton_proof');

      const proof = proofItem ? {
        timestamp: Math.round(Date.now() / 1000),
        domain: new URL(url).host,
        payload: proofItem.name === 'ton_proof' ? proofItem.payload : '',
      } : undefined;

      if (!addressItem) {
        throw new BadRequestError('Missing \'ton_addr\'');
      }

      if (proof && !proof.domain.includes('.')) {
        throw new BadRequestError('Invalid domain');
      }

      let accountId = await getCurrentAccountOrFail();
      const { network } = parseAccountId(accountId);
      const account = await fetchStoredChainAccount(accountId, 'ton');

      const { promiseId, promise } = createDappPromise();

      const dapp: StoredDappConnection = {
        ...dappMetadata,
        protocolType: this.protocolType,
        chains: [{
          chain: 'ton',
          network,
          address: account.byChain.ton.address,
        }],
        url,
        connectedAt: Date.now(),
        ...(request.isUrlEnsured && { isUrlEnsured: true }),
        ...('sseOptions' in request && {
          sse: request.sseOptions,
        }),
      };

      const uniqueId = getDappConnectionUniqueId(dapp);

      this.onUpdate({
        type: 'dappConnect',
        identifier: String(requestId),
        promiseId,
        accountId,
        dapp,
        permissions: {
          address: true,
          proof: !!proof,
        },
        proof,
      });

      const promiseResult: Parameters<typeof confirmDappRequestConnect>[1] = await promise;

      accountId = promiseResult.accountId;
      request.accountId = accountId;
      await addDapp(accountId, dapp, uniqueId);

      const deviceInfo = tonConnectGetDeviceInfo(account);
      const items: ConnectItemReply[] = [
        buildTonAddressReplyItem(accountId, account.byChain.ton),
      ];

      if (proof) {
        items.push(buildTonProofReplyItem(proof, promiseResult.proofSignatures![0]));
      }

      this.onUpdate({ type: 'updateDapps' });
      this.onUpdate({ type: 'dappConnectComplete' });

      return {
        success: true,
        session: {
          id: String(requestId),
          protocolType: this.protocolType,
          accountId,
          dapp,
          chains: [{
            chain: 'ton',
            address: accountId,
            network,
          }],
          connectedAt: new Date().getTime(),
          protocolData: {
            event: 'connect',
            id: requestId,
            payload: {
              items,
              device: deviceInfo,
            },
          },
        },
      };
    } catch (err) {
      logDebugError('tonConnect:connect', err);

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
      const { url, accountId } = await ensureRequestParams(request);

      const uniqueId = getDappConnectionUniqueId(request);
      const currentDapp = await getDapp(accountId, url, uniqueId);
      if (!currentDapp) {
        throw new UnknownAppError();
      }

      await updateDapp(accountId, url, uniqueId, { connectedAt: Date.now() });

      const { network } = parseAccountId(accountId);

      const account = await fetchStoredChainAccount(accountId, 'ton');

      const deviceInfo = tonConnectGetDeviceInfo(account);
      const items: ConnectItemReply[] = [
        buildTonAddressReplyItem(accountId, account.byChain.ton),
      ];

      return {
        success: true,
        session: {
          id: String(requestId),
          protocolType: this.protocolType,
          accountId,
          dapp: currentDapp,
          chains: [{
            chain: 'ton',
            address: accountId,
            network,
          }],
          connectedAt: new Date().getTime(),
          protocolData: {
            event: 'connect',
            id: requestId,
            payload: {
              items,
              device: deviceInfo,
            },
          },
        },
      };
    } catch (err) {
      logDebugError('tonConnect:reconnect', err);
      return formatConnectError(requestId, err);
    }
  }

  async disconnect(
    request: ApiDappRequest,
    message: DappDisconnectRequest,
  ): Promise<DappMethodResult<typeof this.protocolType>> {
    try {
      const { url, accountId } = await ensureRequestParams(request);

      const uniqueId = getDappConnectionUniqueId(request);

      await deleteDapp(accountId, url, uniqueId);

      this.onUpdate({ type: 'updateDapps' });
    } catch (err) {
      logDebugError('tonConnect:disconnect', err);
    }

    return {
      success: true,
      result: {
        result: {},
        id: message.requestId,
      },
    };
  }

  // ---------------------------------------------------------------------------
  // Request Handling
  // ---------------------------------------------------------------------------

  async sendTransaction(
    request: ApiDappRequest,
    message: DappTransactionRequest<typeof this.protocolType>,
  ): Promise<DappMethodResult<typeof this.protocolType>> {
    try {
      const { url, accountId } = await ensureRequestParams(request);
      const { network } = parseAccountId(accountId);

      const txPayload = message.payload;

      const { messages, network: dappNetworkRaw } = txPayload;

      const account = await fetchStoredChainAccount(accountId, message.chain);
      const {
        type,
        byChain: {
          ton: {
            address,
            publicKey: publicKeyHex,
          },
        },
      } = account;

      const maxMessages = getMaxMessagesInTransaction(account);

      if (messages.length > maxMessages) {
        throw new BadRequestError(`Payload contains more than ${maxMessages} messages, which exceeds limit`);
      }

      const dappNetwork = dappNetworkRaw
        ? (dappNetworkRaw === CHAIN.MAINNET ? 'mainnet' : 'testnet')
        : undefined;
      let validUntil = txPayload.valid_until;

      if (validUntil && validUntil > 10 ** 10) {
        // If milliseconds were passed instead of seconds
        validUntil = Math.round(validUntil / 1000);
      }

      const isLedger = type === 'ledger';

      let vestingAddress: string | undefined;

      if (txPayload.from && toBase64Address(txPayload.from) !== toBase64Address(address)) {
        const publicKey = hexToBytes(publicKeyHex!);
        if (isLedger && await checkIsHisVestingWallet(network, publicKey, txPayload.from)) {
          vestingAddress = txPayload.from;
        } else {
          throw new BadRequestError(undefined, ApiTransactionError.WrongAddress);
        }
      }

      if (dappNetwork && network !== dappNetwork) {
        throw new BadRequestError(undefined, ApiTransactionError.WrongNetwork);
      }

      await this.openExtensionPopup(true);

      this.onUpdate({
        type: 'dappLoading',
        connectionType: 'sendTransaction',
        accountId,
        isSse: Boolean('sseOptions' in request && request.sseOptions),
      });

      const checkResult = await checkTransactionMessages(accountId, messages, network);

      if ('error' in checkResult) {
        throw new BadRequestError(checkResult.error, checkResult.error);
      }

      const uniqueId = getDappConnectionUniqueId(request);
      const dapp = (await getDapp(accountId, url, uniqueId))!;
      const transactionsForRequest = await prepareTransactionForRequest(
        network,
        messages,
        checkResult.emulation,
        checkResult.parsedPayloads,
      );

      const { promiseId, promise } = createDappPromise();

      this.onUpdate({
        type: 'dappSendTransactions',
        promiseId,
        accountId,
        dapp,
        operationChain: 'ton',
        transactions: transactionsForRequest,
        emulation: checkResult.emulation.isFallback
          ? undefined
          : pick(checkResult.emulation, ['activities', 'realFee']),
        validUntil,
        vestingAddress,
      });

      const signedTransactions: Parameters<
        typeof confirmDappRequestSendTransaction<typeof this.protocolType>
      >[1] = await promise;

      if (validUntil && validUntil < (Date.now() / 1000)) {
        throw new BadRequestError('The confirmation timeout has expired');
      }

      const sentTransactions = await sendSignedTransactions(accountId, signedTransactions);

      if ('error' in sentTransactions) {
        throw new UnknownError(sentTransactions.error, sentTransactions.error);
      }

      if (sentTransactions.length === 0) {
        throw new UnknownError('Failed transfers');
      }

      if (sentTransactions.length < signedTransactions.length) {
        this.onUpdate({
          type: 'showError',
          error: ApiTransactionError.PartialTransactionFailure,
        });
      }

      const externalMsgHashNorm = sentTransactions[0].msgHashNormalized;

      if (!checkResult.emulation.isFallback && checkResult.emulation.activities?.length > 0) {
        // Use rich emulation activities for optimistic UI
        createLocalActivitiesFromEmulation(
          accountId,
          externalMsgHashNorm, // This is not always correct for Ledger, because in that case the messages are split into individual transactions which have different message hashes. Though, this appears not to cause problems.
          checkResult.emulation.activities,
        );
      } else {
        // Fallback to basic local transactions when emulation is not available
        createLocalTransactions(accountId, 'ton', transactionsForRequest.map((transaction) => {
          const { amount, normalizedAddress, payload, networkFee } = transaction;
          const comment = payload?.type === 'comment' ? payload.comment : undefined;
          return {
            id: externalMsgHashNorm,
            amount,
            fromAddress: address,
            toAddress: normalizedAddress,
            comment,
            fee: networkFee,
            slug: TONCOIN.slug,
            externalMsgHashNorm, // This is not always correct for Ledger, because in that case the messages are split into individual transactions which have different message hashes. Though, this appears not to cause problems.
          };
        }));
      }

      // Notify that dapp transfer is complete after successful blockchain submission
      this.onUpdate({
        type: 'dappTransferComplete',
        accountId,
      });

      return {
        success: true,
        result: {
          result: sentTransactions[0].boc,
          id: message.id,
        },
      };
    } catch (err) {
      logDebugError('tonConnect:sendTransaction', err);

      return this.handleMethodError(err, message.id, 'sendTransaction');
    }
  }

  async signData(
    request: ApiDappRequest,
    message: DappSignDataRequest<typeof this.protocolType>,
  ): Promise<DappMethodResult<typeof this.protocolType>> {
    try {
      const { url, accountId } = await ensureRequestParams(request);

      await this.openExtensionPopup(true);

      this.onUpdate({
        type: 'dappLoading',
        connectionType: 'signData',
        accountId,
        isSse: Boolean('sseOptions' in request && request.sseOptions),
      });

      const { promiseId, promise } = createDappPromise();
      const uniqueId = getDappConnectionUniqueId(request);
      const dapp = (await getDapp(accountId, url, uniqueId))!;
      const payloadToSign = message.payload;

      this.onUpdate({
        type: 'dappSignData',
        operationChain: 'ton',
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

      return {
        success: true,
        result: {
          result,
          id: message.id,
        },
      };
    } catch (err) {
      logDebugError('tonConnect:signData', err);

      return this.handleMethodError(err, message.id, 'signData');
    }
  }

  // ---------------------------------------------------------------------------
  // Deep Link Handling
  // ---------------------------------------------------------------------------

  canHandleDeepLink(url: string): boolean {
    return url.startsWith(TONCONNECT_PROTOCOL)
      || url.startsWith(TONCONNECT_PROTOCOL_SELF)
      || omitProtocol(url).startsWith(omitProtocol(TONCONNECT_UNIVERSAL_URL));
  }

  async handleDeepLink(
    url: string,
    isFromInAppBrowser?: boolean,
    requestId?: string,
  ): Promise<string | undefined> {
    const { searchParams: params, origin: connectionOrigin } = new URL(url);

    const ret: ReturnStrategy = params.get('ret') || 'back';
    const version = Number(params.get('v') as string);
    const appClientId = params.get('id') as string;
    // `back` strategy cannot be implemented
    const shouldOpenUrl = ret !== 'back' && ret !== 'none';
    const r = params.get('r');

    if (!r) {
      if (shouldOpenUrl) {
        this.delayedReturnParams = {
          validUntil: Date.now() + MAX_CONFIRM_DURATION,
          url: ret,
          isFromInAppBrowser,
        };
      }

      return SHOULD_SHOW_LOADER_ON_SSE_START ? 'empty' : undefined;
    }

    const connectRequest: ConnectRequest | null = safeExec(() => JSON.parse(r)) || JSON.parse(decodeURIComponent(r));

    logDebug('tonConnect: SSE Start connection:', {
      version, appClientId, connectRequest, ret, connectionOrigin, requestId,
    });

    const { secretKey: secretKeyArray, publicKey: publicKeyArray } = nacl.box.keyPair();
    const secretKey = bytesToHex(secretKeyArray);
    const clientId = bytesToHex(publicKeyArray);

    const lastOutputId = 0;
    const request: ApiDappRequest = {
      url: undefined,
      identifier: requestId,
      sseOptions: {
        clientId,
        appClientId,
        secretKey,
        lastOutputId,
      },
    };

    await waitLogin();

    if (!connectRequest) {
      this.onUpdate({
        type: 'showError',
        error: 'Invalid TON Connect link',
      });

      return undefined;
    }

    const result = await this.connect(
      request,
      {
        protocolType: this.protocolType,
        transport: 'sse',
        protocolData: connectRequest,
        // We will rewrite permissions in connect method after parsing payload anyway
        permissions: {
          isPasswordRequired: false,
          isAddressRequired: true,
        },
        requestedChains: [{
          chain: 'ton',
          network: await getCurrentNetwork() ?? 'mainnet',
        }],
      },
      lastOutputId);

    if (!result.success) {
      if ([
        CONNECT_EVENT_ERROR_CODES.MANIFEST_CONTENT_ERROR,
        CONNECT_EVENT_ERROR_CODES.MANIFEST_NOT_FOUND_ERROR,
        CONNECT_EVENT_ERROR_CODES.BAD_REQUEST_ERROR,
        CONNECT_EVENT_ERROR_CODES.UNKNOWN_APP_ERROR,
        CONNECT_EVENT_ERROR_CODES.METHOD_NOT_SUPPORTED,
      ].includes(result.error.code as any)) {
        this.onUpdate({
          type: 'showError',
          error: result.error.message,
        });
      }
    }

    await sendMessage(
      transformUnifiedConnectResultToTonConnect(result),
      secretKey,
      clientId,
      appClientId,
    );

    if (result.success) {
      await this.resetupRemoteConnection();
    }

    if (!shouldOpenUrl) {
      return undefined;
    }

    return ret;
  }

  async resetupRemoteConnection() {
    const [lastEventId, dappsState, network] = await Promise.all([
      getSseLastEventId(),
      getDappsState(),
      getCurrentNetwork(),
    ]);

    if (!dappsState || !network) {
      return;
    }

    this.sseDapps = Object.entries(dappsState).reduce((result, [accountId, dappsByUrl]) => {
      if (parseAccountId(accountId).network !== network) {
        return result;
      }

      for (const byUniqueId of Object.values(dappsByUrl)) {
        for (const dapp of Object.values(byUniqueId)) {
          if (dapp.sse?.clientId) {
            result.push({
              ...dapp.sse,
              accountId,
              url: dapp.url,
            });
          }
        }
      }

      return result;
    }, [] as SseDapp[]);

    const clientIds = extractKey(this.sseDapps, 'clientId').filter(Boolean);
    if (!clientIds.length) {
      return;
    }

    await this.destroy();
    this.sseEventSource = this.openEventSource(clientIds, lastEventId);
    this.initialized = true;

    this.sseEventSource.onopen = () => {
      if (SHOULD_SHOW_LOADER_ON_SSE_START) {
        this.onUpdate({
          type: 'tonConnectOnline',
        });
      }
      logDebug('tonConnect:resetupRemoteConnection: EventSource opened');
    };

    this.sseEventSource.onerror = (e) => {
      logDebugError('tonConnect:resetupRemoteConnection', e.type);
    };

    this.sseEventSource.onmessage = async (event) => {
      const { from, message: encryptedMessage } = JSON.parse(event.data);

      const sseDapp = this.sseDapps.find(({ appClientId }) => appClientId === from);
      if (!sseDapp) {
        logDebug(`tonConnect:resetupRemoteConnection: Dapp with clientId ${from} not found`);
        return;
      }

      const {
        accountId, clientId, appClientId, secretKey, url, lastOutputId,
      } = sseDapp;
      const message = decryptMessage(encryptedMessage, appClientId, secretKey) as AppRequest<keyof RpcRequests>;

      logDebug('tonConnect:resetupRemoteConnection: SSE Event:', message);

      await setSseLastEventId(event.lastEventId);
      const sseOptions = {
        clientId,
        appClientId,
        secretKey,
        lastOutputId,
      };

      if (!ALLOWED_SSE_METHODS.has(message.method)) {
        logDebug(`tonConnect:resetupRemoteConnection: Unsupported SSE method: ${message.method}`);
        return;
      }

      // @ts-ignore
      const handler = this[message.method].bind(this);

      const result = await handler(
        { url, accountId, sseOptions },
        transformTonConnectMessageToUnified(message) as any,
      );

      await sendMessage(
        transformUnifiedMethodResponseToTonConnect(result),
        secretKey,
        clientId,
        appClientId,
      );

      if (this.delayedReturnParams) {
        const { validUntil, url, isFromInAppBrowser } = this.delayedReturnParams;
        if (validUntil > Date.now()) {
          this.onUpdate({ type: 'openUrl', url, isExternal: !isFromInAppBrowser });
        }
        this.delayedReturnParams = undefined;
      }
    };
  }

  async closeRemoteConnection(accountId: string, dapp: StoredDappConnection): Promise<void> {
    const sseDapp = this.sseDapps.find((d) => d.url === dapp.url && d.accountId === accountId);
    if (!sseDapp) return;

    const { secretKey, clientId, appClientId } = sseDapp;
    const lastOutputId = sseDapp.lastOutputId + 1;

    const response: DisconnectEvent = {
      event: 'disconnect',
      id: lastOutputId,
      payload: {},
    };

    await sendMessage(response, secretKey, clientId, appClientId);
  }

  private async openExtensionPopup(force?: boolean) {
    if (!IS_EXTENSION || (!force && isUpdaterAlive(this.onUpdate))) {
      return false;
    }

    await callHook('onWindowNeeded');
    await this.initPromise;

    return true;
  }

  private openEventSource(clientIds: string[], lastEventId?: string) {
    const url = new URL(`${SSE_BRIDGE_URL}events`);
    url.searchParams.set('client_id', clientIds.join(','));
    if (lastEventId) {
      url.searchParams.set('last_event_id', lastEventId);
    }
    return new EventSource(url);
  }

  private handleMethodError(
    err: unknown,
    messageId: string,
    connectionType: ApiDappConnectionType,
  ): {
      success: false;
      error: DappProtocolError;
    } {
    safeExec(() => {
      this.onUpdate({
        type: 'dappCloseLoading',
        connectionType,
      });
    });

    let code = SEND_TRANSACTION_ERROR_CODES.UNKNOWN_ERROR;
    let errorMessage = 'Unhandled error';
    let displayError: ApiAnyDisplayError | undefined;

    if (err instanceof ApiUserRejectsError) {
      code = SEND_TRANSACTION_ERROR_CODES.USER_REJECTS_ERROR;
      errorMessage = err.message;
    } else if (err instanceof TonConnectError) {
      code = err.code;
      errorMessage = err.message;
      displayError = err.displayError;
    } else if (err instanceof ApiServerError) {
      displayError = err.displayError;
    } else {
      displayError = ApiCommonError.Unexpected;
    }

    if (isUpdaterAlive(this.onUpdate) && displayError) {
      this.onUpdate({
        type: 'showError',
        error: displayError,
      });
    }
    return {
      success: false,
      error: {
        code,
        message: errorMessage,
      },
    };
  }
}

// =============================================================================
// Factory
// =============================================================================

let adapterInstance: TonConnectAdapter | undefined;

/**
 * Get or create the TON Connect adapter instance.
 */
export function getTonConnectAdapter(): DappProtocolAdapter {
  if (!adapterInstance) {
    adapterInstance = new TonConnectAdapter();
  }
  return adapterInstance;
}

/**
 * Create a new TON Connect adapter instance (for testing).
 */
export function createTonConnectAdapter(): DappProtocolAdapter {
  return new TonConnectAdapter();
}

async function fetchDappMetadata(manifestUrl: string): Promise<DappMetadata> {
  try {
    const { url, name, iconUrl } = await fetchJsonWithProxy(manifestUrl);
    const safeIconUrl = (iconUrl.startsWith('data:') || iconUrl === '') ? BLANK_GIF_DATA_URL : iconUrl;
    if (!isValidUrl(url) || !isValidString(name) || !isValidUrl(safeIconUrl)) {
      throw new Error('Invalid data');
    }

    return {
      url,
      name,
      iconUrl: safeIconUrl,
      manifestUrl,
    };
  } catch (err) {
    logDebugError('fetchDappMetadata', err);

    throw new ManifestContentError();
  }
}

async function getCurrentAccountOrFail() {
  const accountId = await getCurrentAccountId();
  if (!accountId) {
    throw new BadRequestError('The user is not authorized in the wallet');
  }
  return accountId;
}

async function ensureRequestParams(
  request: ApiDappRequest,
): Promise<ApiDappRequest & { url: string; accountId: string }> {
  if (!request.url) {
    throw new BadRequestError('Missing `url` in request');
  }

  if (request.accountId) {
    return request as ApiDappRequest & { url: string; accountId: string };
  }

  const { network } = parseAccountId(await getCurrentAccountIdOrFail());
  const lastAccountId = await findLastConnectedAccount(network, request.url);
  if (!lastAccountId) {
    throw new BadRequestError('The connection is outdated, try relogin');
  }

  return {
    ...request,
    accountId: lastAccountId,
  } as ApiDappRequest & { url: string; accountId: string };
}

function buildTonAddressReplyItem(accountId: string, wallet: ApiTonWallet): ConnectItemReply {
  const { network } = parseAccountId(accountId);
  const { publicKey, address } = wallet;

  const stateInit = getWalletStateInit(wallet);

  return {
    name: 'ton_addr',
    address: toRawAddress(address),
    network: network === 'mainnet' ? CHAIN.MAINNET : CHAIN.TESTNET,
    publicKey: publicKey!,
    walletStateInit: stateInit
      .toBoc({ idx: true, crc32: true })
      .toString('base64'),
  };
}

function buildTonProofReplyItem(proof: TonConnectProof, signature: string): TonProofItemReplySuccess {
  const { timestamp, domain, payload } = proof;
  const domainBuffer = Buffer.from(domain);

  return {
    name: 'ton_proof',
    proof: {
      timestamp,
      domain: {
        lengthBytes: domainBuffer.byteLength,
        value: domainBuffer.toString('utf8'),
      },
      signature,
      payload,
    },
  };
}

async function checkIsHisVestingWallet(network: ApiNetwork, ownerPublicKey: Uint8Array, address: string) {
  const [info, publicKey] = await Promise.all([
    getContractInfo(network, address),
    getWalletPublicKey(network, address),
  ]);

  return info.contractInfo?.name === 'vesting' && areDeepEqual(ownerPublicKey, publicKey);
}

function sendMessage(
  message: AnyLiteral, secretKey: string, clientId: string, toId: string, topic?: 'signTransaction' | 'signData',
) {
  const buffer = Buffer.from(JSON.stringify(message));
  const encryptedMessage = encryptMessage(buffer, toId, secretKey);
  return sendRawMessage(encryptedMessage, clientId, toId, topic);
}

async function sendRawMessage(body: string, clientId: string, toId: string, topic?: 'signTransaction' | 'signData') {
  const url = new URL(`${SSE_BRIDGE_URL}message`);
  url.searchParams.set('client_id', clientId);
  url.searchParams.set('to', toId);
  url.searchParams.set('ttl', TTL_SEC.toString());
  if (topic) {
    url.searchParams.set('topic', topic);
  }

  const response = await fetch(url, { method: 'POST', body });

  await handleFetchErrors(response);
}

function encryptMessage(message: Uint8Array, publicKey: string, secretKey: string) {
  const nonce = randomBytes(NONCE_SIZE);
  const encrypted = nacl.box(
    message, nonce, Buffer.from(publicKey, 'hex'), Buffer.from(secretKey, 'hex'),
  );
  return Buffer.concat([nonce, encrypted]).toString('base64');
}

function decryptMessage(message: string, publicKey: string, secretKey: string) {
  const fullBuffer = Buffer.from(message, 'base64');
  const nonce = fullBuffer.subarray(0, NONCE_SIZE);
  const encrypted = fullBuffer.subarray(NONCE_SIZE);
  const decrypted = nacl.box.open(
    encrypted,
    nonce,
    Buffer.from(publicKey, 'hex'),
    Buffer.from(secretKey, 'hex'),
  );
  const jsonText = new TextDecoder('utf-8').decode(decrypted!);
  return JSON.parse(jsonText);
}

async function checkTransactionMessages(
  accountId: string,
  messages: TonConnectTransactionMessage[],
  network: ApiNetwork,
) {
  const preparedMessages: TonTransferParams[] = messages.map((msg) => {
    const {
      address: toAddress,
      amount,
      payload,
      stateInit,
    } = msg;

    return {
      toAddress: getIsRawAddress(toAddress)
        ? toBase64Address(toAddress, true, network)
        : toAddress,
      amount: BigInt(amount),
      payload: payload ? Cell.fromBase64(payload) : undefined,
      stateInit: stateInit ? Cell.fromBase64(stateInit) : undefined,
    };
  });

  const checkResult = await checkMultiTransactionDraft(accountId, preparedMessages);

  // Handle insufficient balance error specifically for TON Connect by converting to fallback emulation
  if ('error' in checkResult
    && checkResult.error === ApiTransactionDraftError.InsufficientBalance
    && checkResult.emulation
  ) {
    const fallbackCheckResult: ApiCheckMultiTransactionDraftResult = {
      emulation: {
        isFallback: true,
        networkFee: checkResult.emulation.networkFee,
      },
      parsedPayloads: checkResult.parsedPayloads,
    };
    return fallbackCheckResult;
  }

  return checkResult;
}

function prepareTransactionForRequest(
  network: ApiNetwork,
  messages: TonConnectTransactionMessage[],
  emulation: ApiEmulationWithFallbackResult,
  parsedPayloads?: (ApiParsedPayload | undefined)[],
) {
  return Promise.all(messages.map(
    async ({
      address,
      amount: rawAmount,
      payload: rawPayload,
      stateInit,
    }, index): Promise<ApiDappTransfer> => {
      const amount = BigInt(rawAmount);
      const toAddress = getIsRawAddress(address) ? toBase64Address(address, true, network) : address;
      // Fix address format for `waitTxComplete` to work properly
      const normalizedAddress = toBase64Address(address, undefined, network);
      const payload = parsedPayloads?.[index]
        ?? (rawPayload ? await parsePayloadBase64(network, toAddress, rawPayload) : undefined);
      const { isScam } = getKnownAddressInfo(normalizedAddress) || {};

      return {
        chain: 'ton',
        toAddress,
        amount,
        rawPayload,
        payload,
        stateInit,
        normalizedAddress,
        isScam,
        isDangerous: isTransferPayloadDangerous(payload),
        displayedToAddress: getTransferActualToAddress(toAddress, payload),
        networkFee: emulation.isFallback
          ? bigintDivideToNumber(emulation.networkFee, messages.length)
          : emulation.traceOutputs[index]?.networkFee ?? 0n,
      };
    },
  ));
}

function transformUnifiedConnectResultToTonConnect(
  payload: DappConnectionResult<DappProtocolType.TonConnect>,
): ConnectEvent {
  if (payload.success) {
    return payload.session.protocolData;
  }
  return {
    event: 'connect_error',
    id: 0,
    payload: {
      code: payload.error.code as any,
      message: payload.error.message,
    },
  };
}

function formatConnectError(id: number, error: unknown): {
  success: false;
  error: DappProtocolError;
} {
  let code = CONNECT_EVENT_ERROR_CODES.UNKNOWN_ERROR;
  let message = 'Unhandled error';

  if (error instanceof ApiUserRejectsError) {
    code = CONNECT_EVENT_ERROR_CODES.USER_REJECTS_ERROR;
    message = error.message;
  } else if (error instanceof TonConnectError) {
    code = error.code;
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

function omitProtocol(url: string) {
  return url.replace(/^https?:\/\//, '');
}
