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

import { IS_AIR_APP, IS_EXTENSION, SSE_BRIDGE_URL, TONCOIN } from '../../../../config';
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
import { generateUuidV7 } from '../../../../util/random';
import safeExec from '../../../../util/safeExec';
import { pause } from '../../../../util/schedulers';
import { getMaxMessagesInTransaction } from '../../../../util/ton/transfer';
import { tonConnectGetDeviceInfo } from '../../../../util/tonConnectEnvironment';
import { fetchExternalMessageBocByHashNormalized } from '../../../chains/ton/toncenter/messages';
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
import { getMfaRequest } from '../../../common/mfa';
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
  clearTonConnectFlowContext,
  finishTonConnectFlow,
  recordTonConnectEvent,
  setTonConnectFlowContext,
  toTonConnectNetworkId,
  toTonConnectRequestType,
} from './analytics';
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

type ReturnStrategy = 'back' | 'none' | (string & {});
const ALLOWED_SSE_METHODS = new Set<RpcMethod>(['sendTransaction', 'disconnect', 'signData']);

const TTL_SEC = 300;
const NONCE_SIZE = 24;
const MAX_CONFIRM_DURATION = 60 * 1000;
const SHOULD_SHOW_LOADER_ON_SSE_START = IS_AIR_APP;

const MFA_POLL_INTERVAL_START_MS = 1000;
const MFA_POLL_INTERVAL_MAX_MS = 5000;
const MFA_CONFIRMATION_TIMEOUT_MS = 4 * 60 * 1000;

type SseDapp = {
  accountId: string;
  url: string;
} & ApiSseOptions;

async function waitForMfaAndGetSentTransactions(options: {
  accountId: string;
  network: ApiNetwork;
  mfaRequestHash: string;
}): Promise<Array<{ boc: string; msgHashNormalized: string }>> {
  const { accountId, network, mfaRequestHash } = options;

  const startedAt = Date.now();
  let pollInterval = MFA_POLL_INTERVAL_START_MS;

  while (Date.now() - startedAt < MFA_CONFIRMATION_TIMEOUT_MS) {
    const request = await getMfaRequest({ hash: mfaRequestHash }).catch(() => undefined);

    const txHashNormalized = request?.isConfirmed ? request.txHash : '';
    if (txHashNormalized) {
      const message = await fetchExternalMessageBocByHashNormalized({
        network,
        msgHashNormalized: txHashNormalized,
      }).catch(() => undefined);

      if (message?.boc) {
        return [{
          boc: message.boc,
          msgHashNormalized: txHashNormalized,
        }];
      }
    }

    // Keep polling until the mini-app submits the message and the indexer can fetch it.
    await pause(pollInterval);
    pollInterval = Math.min(Math.round(pollInterval * 1.25), MFA_POLL_INTERVAL_MAX_MS);
  }

  logDebug('tonConnect:mfa confirmation timeout', { accountId, mfaRequestHash });
  throw new BadRequestError('MFA confirmation timeout');
}

/**
 * TON Connect protocol adapter.
 */
class TonConnectAdapter implements DappProtocolAdapter<DappProtocolType.TonConnect> {
  readonly protocolType = DappProtocolType.TonConnect;

  private hasWarnedAboutUpdateBeforeInit = false;
  private onUpdate: OnApiUpdate;

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
    this.onUpdate = this.handleUpdateBeforeInit;
    this.initPromise = new Promise((resolve) => {
      this.resolveInit = resolve;
    });
  }

  private handleUpdateBeforeInit = () => {
    if (this.hasWarnedAboutUpdateBeforeInit) {
      return;
    }

    this.hasWarnedAboutUpdateBeforeInit = true;
    logDebugError('tonConnect:init', 'onUpdate called before adapter init');
  };

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  async init(config: DappProtocolConfig) {
    this.onUpdate = config.onUpdate;

    if (this.initialized) {
      return;
    }

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
    let promiseId: string | undefined;

    try {
      const addressItem = message.protocolData.items.find(({ name }) => name === 'ton_addr');
      const proofItem = message.protocolData.items.find(({ name }) => name === 'ton_proof');
      const traceId = generateUuidV7();
      const sse = 'sseOptions' in request ? request.sseOptions : undefined;
      // Record the request the moment it arrives, before the popup and the manifest fetch (per analytics-spec
      // `wallet-connect-request-received` = "when the wallet receives a connection request"), so a request that
      // fails the manifest fetch or validation is still counted. Per the spec this event carries only the manifest
      // and addr/proof fields (not dapp_name/origin_url, which need the fetched manifest); the flow context below
      // reuses `traceId` and adds the dapp fields for the later events.
      void recordTonConnectEvent({
        event_name: 'wallet-connect-request-received',
        trace_id: traceId,
        client_id: sse?.appClientId,
        wallet_id: sse?.clientId,
        manifest_json_url: message.protocolData.manifestUrl,
        is_ton_addr: Boolean(addressItem),
        is_ton_proof: Boolean(proofItem),
        // `payload` is dapp-supplied; guard against a non-string before measuring it.
        proof_payload_size: proofItem?.name === 'ton_proof' && typeof proofItem.payload === 'string'
          ? Buffer.byteLength(proofItem.payload)
          : undefined,
      });

      await this.openExtensionPopup(true);

      this.onUpdate({
        type: 'dappLoading',
        connectionType: 'connect',
        isSse: request && 'sseOptions' in request,
      });

      const dappMetadata = await fetchDappMetadata(message.protocolData.manifestUrl);
      const url = request.url || dappMetadata.url;

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

      const dappPromise = createDappPromise();
      promiseId = dappPromise.promiseId;
      const { promise } = dappPromise;

      let account = await fetchStoredChainAccount(accountId, 'ton');
      let dapp = buildDappConnection(
        this.protocolType,
        dappMetadata,
        url,
        accountId,
        account.byChain.ton.address,
        request,
      );

      const uniqueId = getDappConnectionUniqueId(dapp);

      setTonConnectFlowContext(promiseId, {
        trace_id: traceId,
        network_id: toTonConnectNetworkId(network),
        client_id: sse?.appClientId,
        wallet_id: sse?.clientId,
        manifest_json_url: message.protocolData.manifestUrl,
        origin_url: url,
        dapp_name: dappMetadata.name,
      });

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

      if (promiseResult.accountId !== accountId) {
        accountId = promiseResult.accountId;
        request.accountId = accountId;
        account = await fetchStoredChainAccount(accountId, 'ton');
        dapp = buildDappConnection(
          this.protocolType,
          dappMetadata,
          url,
          accountId,
          account.byChain.ton.address,
          request,
        );
      } else {
        request.accountId = accountId;
      }

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

      finishTonConnectFlow(promiseId, 'wallet-connect-response-sent');

      return {
        success: true,
        session: {
          id: String(requestId),
          protocolType: this.protocolType,
          accountId,
          dapp,
          chains: [{
            chain: 'ton',
            address: account.byChain.ton.address,
            network: parseAccountId(accountId).network,
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
    } finally {
      if (promiseId) {
        clearTonConnectFlowContext(promiseId);
      }
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
            address: account.byChain.ton.address,
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
    let promiseId: string | undefined;

    try {
      await this.assertDappConnected(request);
      const { url, accountId } = await ensureRequestParams(request);
      const { network } = parseAccountId(accountId);

      const traceId = generateUuidV7();
      const sse = 'sseOptions' in request ? request.sseOptions : undefined;
      const uniqueId = getDappConnectionUniqueId(request);
      const dapp = (await getDapp(accountId, url, uniqueId))!;
      // Record the request on arrival, before validation/emulation/UI (per analytics-spec
      // `wallet-transaction-request-received` = "when the wallet receives a transaction request"), so requests
      // rejected before the prompt are still counted. The flow context below reuses `traceId` to correlate the rest.
      void recordTonConnectEvent({
        event_name: 'wallet-transaction-request-received',
        trace_id: traceId,
        network_id: toTonConnectNetworkId(network),
        client_id: sse?.appClientId,
        wallet_id: sse?.clientId,
        manifest_json_url: dapp.manifestUrl,
        origin_url: url,
        dapp_name: dapp.name,
      });

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

      const transactionsForRequest = await prepareTransactionForRequest(
        network,
        messages,
        checkResult.emulation,
        checkResult.parsedPayloads,
      );

      const dappPromise = createDappPromise();
      promiseId = dappPromise.promiseId;
      const { promise } = dappPromise;

      setTonConnectFlowContext(promiseId, {
        trace_id: traceId,
        network_id: toTonConnectNetworkId(network),
        client_id: sse?.appClientId,
        wallet_id: sse?.clientId,
        manifest_json_url: dapp.manifestUrl,
        origin_url: url,
        dapp_name: dapp.name,
      });

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

      const sentTransactions = Array.isArray(signedTransactions)
        ? await sendSignedTransactions(accountId, signedTransactions)
        : await waitForMfaAndGetSentTransactions({
          accountId,
          network,
          mfaRequestHash: signedTransactions.mfaRequestHash,
        });

      if ('error' in sentTransactions) {
        throw new UnknownError(sentTransactions.error, sentTransactions.error);
      }

      if (sentTransactions.length === 0) {
        throw new UnknownError('Failed transfers');
      }

      if (Array.isArray(signedTransactions) && sentTransactions.length < signedTransactions.length) {
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

      finishTonConnectFlow(promiseId, 'wallet-transaction-sent', { normalized_hash: externalMsgHashNorm });

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
    } finally {
      if (promiseId) {
        clearTonConnectFlowContext(promiseId);
      }
    }
  }

  async signData(
    request: ApiDappRequest,
    message: DappSignDataRequest<typeof this.protocolType>,
  ): Promise<DappMethodResult<typeof this.protocolType>> {
    let promiseId: string | undefined;

    try {
      await this.assertDappConnected(request);
      const { url, accountId } = await ensureRequestParams(request);

      const traceId = generateUuidV7();
      const sse = 'sseOptions' in request ? request.sseOptions : undefined;
      const uniqueId = getDappConnectionUniqueId(request);
      const dapp = (await getDapp(accountId, url, uniqueId))!;
      // Record the request on arrival, before the UI (per analytics-spec `wallet-sign-data-request-received` =
      // "when the wallet receives a sign-data request"). The flow context below reuses `traceId` to correlate.
      void recordTonConnectEvent({
        event_name: 'wallet-sign-data-request-received',
        trace_id: traceId,
        network_id: toTonConnectNetworkId(parseAccountId(accountId).network),
        client_id: sse?.appClientId,
        wallet_id: sse?.clientId,
        manifest_json_url: dapp.manifestUrl,
        origin_url: url,
        dapp_name: dapp.name,
      });

      await this.openExtensionPopup(true);

      this.onUpdate({
        type: 'dappLoading',
        connectionType: 'signData',
        accountId,
        isSse: Boolean('sseOptions' in request && request.sseOptions),
      });

      const dappPromise = createDappPromise();
      promiseId = dappPromise.promiseId;
      const { promise } = dappPromise;
      const payloadToSign = message.payload;

      setTonConnectFlowContext(promiseId, {
        trace_id: traceId,
        network_id: toTonConnectNetworkId(parseAccountId(accountId).network),
        client_id: sse?.appClientId,
        wallet_id: sse?.clientId,
        manifest_json_url: dapp.manifestUrl,
        origin_url: url,
        dapp_name: dapp.name,
      });

      this.onUpdate({
        type: 'dappSignData',
        operationChain: 'ton',
        promiseId,
        accountId,
        dapp,
        payloadToSign,
      });

      const signedResponse: Parameters<typeof confirmDappRequestSignData<typeof this.protocolType>>[1] = await promise;

      this.onUpdate({
        type: 'dappSignDataComplete',
        accountId,
      });

      finishTonConnectFlow(promiseId, 'wallet-sign-data-sent');

      return {
        success: true,
        result: {
          result: signedResponse.result,
          id: message.id,
        },
      };
    } catch (err) {
      logDebugError('tonConnect:signData', err);

      return this.handleMethodError(err, message.id, 'signData');
    } finally {
      if (promiseId) {
        clearTonConnectFlowContext(promiseId);
      }
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
      if (appClientId && !(await hasStoredSseConnection(appClientId))) {
        logDebug('tonConnect: Request for a disconnected client', appClientId);
        this.onUpdate({ type: 'dappDisconnected', url: shouldOpenUrl ? ret : undefined });
        return undefined;
      }

      if (shouldOpenUrl) {
        this.delayedReturnParams = {
          validUntil: Date.now() + MAX_CONFIRM_DURATION,
          url: ret,
          isFromInAppBrowser,
        };
      }

      if (SHOULD_SHOW_LOADER_ON_SSE_START) {
        // Open the placeholder request modal; the SSE request event types it (fill or swap) and clears its timer
        this.onUpdate({
          type: 'dappLoading',
          connectionType: 'sendTransaction',
          isSse: true,
          isWaitingForRequest: true,
          returnUrl: shouldOpenUrl ? ret : undefined,
        });
      }

      return undefined;
    }

    if (await hasStoredSseConnection(appClientId)) {
      logDebug('tonConnect: Ignoring repeated connect for already connected client', appClientId);
      this.onUpdate({ type: 'dappAlreadyConnected', url: shouldOpenUrl ? ret : undefined });
      return undefined;
    }

    const connectRequest: ConnectRequest | null = safeExec(() => JSON.parse(r)) || JSON.parse(decodeURIComponent(r));

    logDebug('tonConnect: SSE Start connection:', {
      version, appClientId, connectRequest, ret, connectionOrigin, requestId,
    });

    const { secretKey: secretKeyArray, publicKey: publicKeyArray } = nacl.box.keyPair();
    const secretKey = bytesToHex(secretKeyArray);
    const walletClientId = bytesToHex(publicKeyArray);

    const lastOutputId = 0;
    const request: ApiDappRequest = {
      url: undefined,
      identifier: requestId,
      sseOptions: {
        clientId: walletClientId,
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
      walletClientId,
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

    const walletClientIds = extractKey(this.sseDapps, 'clientId').filter(Boolean);
    if (!walletClientIds.length) {
      return;
    }

    await this.destroy();

    const bridgeTraceId = generateUuidV7();
    // Restarted on each disconnect (in `onerror`) so a reconnect's `onopen` reports the reconnect handshake
    // duration, not the time since the original setup, which the native EventSource auto-reconnect would inflate.
    let connectStartedAt = Date.now();
    // The SSE bridge is a single connection multiplexing every dapp; emitting the joined set of all
    // wallet-side session client ids here would hand the collector a stable cross-dapp fingerprint of the
    // user. Per-message events carry their own single client id, so connection-level events omit it.
    void recordTonConnectEvent({
      event_name: 'bridge-client-connect-started',
      trace_id: bridgeTraceId,
      bridge_url: SSE_BRIDGE_URL,
    });

    const eventSource = this.openEventSource(walletClientIds, lastEventId);
    this.sseEventSource = eventSource;
    this.initialized = true;

    // A native EventSource auto-reconnects and fires `onerror` on every failed attempt; report only the
    // first error of each disconnection episode (reset on the next successful open) so a flapping bridge
    // does not flood the collector with identical events.
    let hasReportedConnectError = false;

    eventSource.onopen = () => {
      hasReportedConnectError = false;
      void recordTonConnectEvent({
        event_name: 'bridge-client-connect-established',
        trace_id: bridgeTraceId,
        bridge_url: SSE_BRIDGE_URL,
        bridge_connect_duration: Date.now() - connectStartedAt,
      });
      if (SHOULD_SHOW_LOADER_ON_SSE_START) {
        this.onUpdate({
          type: 'tonConnectOnline',
        });
      }
      logDebug('tonConnect:resetupRemoteConnection: EventSource opened');
    };

    eventSource.onerror = (e) => {
      if (!hasReportedConnectError) {
        hasReportedConnectError = true;
        // Mark the start of this disconnection episode so the next successful `onopen` measures the reconnect from here.
        connectStartedAt = Date.now();
        void recordTonConnectEvent({
          event_name: 'bridge-client-connect-error',
          trace_id: bridgeTraceId,
          bridge_url: SSE_BRIDGE_URL,
          // `e.type` on an EventSource error is always the literal `'error'`; readyState carries the signal. Read it
          // from the source that errored, not `this.sseEventSource`, which a concurrent reconnect may have replaced.
          error_message: `readyState=${eventSource.readyState}`,
        });
      }
      logDebugError('tonConnect:resetupRemoteConnection', e.type);
    };

    eventSource.onmessage = async (event) => {
      const { from, message: encryptedMessage } = JSON.parse(event.data);

      const sseDapp = this.sseDapps.find(({ appClientId }) => appClientId === from);
      if (!sseDapp) {
        logDebug(`tonConnect:resetupRemoteConnection: Dapp with appClientId ${from} not found`);
        return;
      }

      const {
        accountId, clientId: walletClientId, appClientId, secretKey, url, lastOutputId,
      } = sseDapp;

      const messageTraceId = generateUuidV7();
      let message: AppRequest<keyof RpcRequests>;
      try {
        message = decryptMessage(encryptedMessage, appClientId, secretKey) as AppRequest<keyof RpcRequests>;
      } catch (err) {
        void recordTonConnectEvent({
          event_name: 'bridge-client-message-decode-error',
          trace_id: messageTraceId,
          bridge_url: SSE_BRIDGE_URL,
          client_id: appClientId,
          wallet_id: walletClientId,
          error_message: err instanceof Error ? err.message : String(err),
        });
        logDebugError('tonConnect:resetupRemoteConnection: decode error', err);
        return;
      }

      void recordTonConnectEvent({
        event_name: 'bridge-client-message-received',
        trace_id: messageTraceId,
        bridge_url: SSE_BRIDGE_URL,
        client_id: appClientId,
        wallet_id: walletClientId,
        message_id: message.id !== undefined ? String(message.id) : undefined,
        request_type: toTonConnectRequestType(message.method),
      });

      logDebug('tonConnect:resetupRemoteConnection: SSE Event:', message);

      await setSseLastEventId(event.lastEventId);
      const sseOptions = {
        clientId: walletClientId,
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
        transformUnifiedMethodResponseToTonConnect(result, message.id),
        secretKey,
        walletClientId,
        appClientId,
      );

      void recordTonConnectEvent({
        event_name: 'bridge-client-message-sent',
        trace_id: messageTraceId,
        bridge_url: SSE_BRIDGE_URL,
        client_id: appClientId,
        wallet_id: walletClientId,
        message_id: message.id !== undefined ? String(message.id) : undefined,
        request_type: toTonConnectRequestType(message.method),
      });

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

    const { secretKey, clientId: walletClientId, appClientId } = sseDapp;
    const lastOutputId = sseDapp.lastOutputId + 1;

    const response: DisconnectEvent = {
      event: 'disconnect',
      id: lastOutputId,
      payload: {},
    };

    await sendMessage(response, secretKey, walletClientId, appClientId);
  }

  // Verifies that the dapp issuing the request is still connected. For non-SSE flows (in-app browser and
  // injected extension) a disconnected dapp must surface the "Dapp Disconnected" dialog rather than a generic
  // error, mirroring the SSE deeplink handling in `handleDeepLink`.
  private async assertDappConnected(request: ApiDappRequest) {
    const { url } = request;
    let { accountId } = request;

    if (url && !accountId) {
      const { network } = parseAccountId(await getCurrentAccountIdOrFail());
      accountId = (await findLastConnectedAccount(network, url)) ?? undefined;
    }

    const uniqueId = getDappConnectionUniqueId(request);
    if (url && accountId && (await getDapp(accountId, url, uniqueId))) {
      return;
    }

    logDebug('tonConnect: Request for a disconnected dapp', url);
    this.onUpdate({ type: 'dappDisconnected' });
    throw new UnknownAppError();
  }

  private async openExtensionPopup(force?: boolean) {
    if (!IS_EXTENSION || (!force && isUpdaterAlive(this.onUpdate))) {
      return false;
    }

    await callHook('onWindowNeeded');
    await this.initPromise;

    return true;
  }

  private openEventSource(walletClientIds: string[], lastEventId?: string) {
    const url = new URL(`${SSE_BRIDGE_URL}events`);
    url.searchParams.set('client_id', walletClientIds.join(','));
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

function buildDappConnection(
  protocolType: DappProtocolType.TonConnect,
  dappMetadata: DappMetadata,
  url: string,
  accountId: string,
  address: string,
  request: ApiDappRequest,
): StoredDappConnection {
  const { network } = parseAccountId(accountId);

  return {
    ...dappMetadata,
    protocolType,
    chains: [{
      chain: 'ton',
      network,
      address,
    }],
    url,
    connectedAt: Date.now(),
    urlTrustStatus: request.urlTrustStatus ?? 'unknown',
    ...('sseOptions' in request && {
      sse: request.sseOptions,
    }),
  };
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

async function hasStoredSseConnection(appClientId: string): Promise<boolean> {
  const dappsState = await getDappsState();
  if (!dappsState) {
    return false;
  }

  for (const dappsByUrl of Object.values(dappsState)) {
    for (const byUniqueId of Object.values(dappsByUrl)) {
      for (const dapp of Object.values(byUniqueId)) {
        if (dapp.sse?.appClientId === appClientId) {
          return true;
        }
      }
    }
  }

  return false;
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
  message: AnyLiteral, secretKey: string, walletClientId: string, appClientId: string,
  topic?: 'signTransaction' | 'signData',
) {
  const buffer = Buffer.from(JSON.stringify(message));
  const encryptedMessage = encryptMessage(buffer, appClientId, secretKey);
  return sendRawMessage(encryptedMessage, walletClientId, appClientId, topic);
}

async function sendRawMessage(
  body: string, walletClientId: string, appClientId: string, topic?: 'signTransaction' | 'signData',
) {
  const url = new URL(`${SSE_BRIDGE_URL}message`);
  url.searchParams.set('client_id', walletClientId);
  url.searchParams.set('to', appClientId);
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
  let message = 'Unknown error.';

  if (error instanceof ApiUserRejectsError) {
    code = CONNECT_EVENT_ERROR_CODES.USER_REJECTS_ERROR;
    message = error.message;
  } else if (error instanceof TonConnectError) {
    code = error.code;
    message = error.message;
  } else if (error instanceof Error) {
    message = error.message || message;
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
