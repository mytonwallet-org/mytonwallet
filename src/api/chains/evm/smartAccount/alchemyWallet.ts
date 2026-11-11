import {
  getBytes,
  Wallet,
} from 'ethers';

import type { EvmMetaTransaction } from './types';

import { fetchJson } from '../../../../util/fetch';
import { signEip7702AuthorizationSignature } from './delegation';
import {
  hashUserOperationV07,
  isModularAccountCallData,
  type UserOperationV07Data,
} from './userOperation';

type JsonRpcError = {
  code: number;
  message: string;
};

type JsonRpcResponse<T> = {
  jsonrpc: '2.0';
  id: number;
  result?: T;
  error?: JsonRpcError;
};

type AlchemyEip712TypedData = {
  domain: Record<string, unknown>;
  types: Record<string, Array<{ name: string; type: string }>>;
  primaryType: string;
  message: Record<string, unknown>;
};

type AlchemySignatureRequest = {
  type: 'personal_sign' | 'eth_signAuthorization' | 'eip7702Auth' | 'eth_signTypedData_v4';
  data?: { raw?: string } | string | AlchemyEip712TypedData;
  rawPayload?: string;
};

export type AlchemyPreparedCallItem = {
  type: string;
  data: Record<string, string | undefined>;
  chainId?: string;
  signatureRequest?: AlchemySignatureRequest;
  signature?: { type: 'secp256k1'; data: string };
};

export type AlchemyPrepareCallsResult = {
  type: string;
  data?: AlchemyPreparedCallItem[] | Record<string, string | undefined>;
  chainId?: string;
  signatureRequest?: AlchemySignatureRequest;
};

type AlchemySendPreparedCallsResult = {
  id: string;
};

type AlchemyCallsStatusReceipt = {
  status?: string;
  transactionHash?: string;
};

export type AlchemyCallsStatusResult = {
  id: string;
  status: number;
  details?: {
    type?: string;
    data?: {
      hash?: string;
    };
  };
  receipts?: AlchemyCallsStatusReceipt[];
};

export type AlchemySignedPreparedCalls =
  | { type: 'array'; data: AlchemyPreparedCallItem[] }
  | {
    type: string;
    data: Record<string, string | undefined>;
    chainId: string;
    signature: { type: 'secp256k1'; data: string };
  };

async function alchemyWalletRpc<T>(
  apiUrl: string,
  method: string,
  params: unknown[],
): Promise<T> {
  const response = await fetchJson<JsonRpcResponse<T>>(apiUrl, undefined, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      Accept: 'application/json',
    },
    body: JSON.stringify({
      jsonrpc: '2.0',
      id: 1,
      method,
      params,
    }),
  });

  if (response.error) {
    throw new Error(response.error.message || `Alchemy Wallet API error ${response.error.code}`);
  }

  if (response.result === undefined) {
    throw new Error(`Alchemy Wallet API returned empty result for ${method}`);
  }

  return response.result;
}

function toAlchemyCalls(transactions: EvmMetaTransaction[]) {
  return transactions.map(({ to, value = 0n, data = '0x' }) => ({
    to,
    data,
    value: `0x${value.toString(16)}`,
  }));
}

function parseHexBigInt(value: string | undefined): bigint {
  if (!value) return 0n;

  return BigInt(value);
}

function getUserOperationDataFromPrepareResult(result: AlchemyPrepareCallsResult): Record<string, string | undefined> {
  if (result.type === 'array' && Array.isArray(result.data)) {
    const userOperation = result.data.find((item) => item.type.startsWith('user-operation'));

    if (!userOperation) {
      throw new Error('Alchemy prepareCalls response missing user operation');
    }

    return userOperation.data;
  }

  if (!result.data || Array.isArray(result.data)) {
    throw new Error('Alchemy prepareCalls response missing user operation data');
  }

  return result.data;
}

export function estimateMaxCostFromPrepareResult(result: AlchemyPrepareCallsResult): bigint {
  const data = getUserOperationDataFromPrepareResult(result);
  const maxFeePerGas = parseHexBigInt(data.maxFeePerGas);

  const totalGas = parseHexBigInt(data.callGasLimit)
    + parseHexBigInt(data.verificationGasLimit)
    + parseHexBigInt(data.preVerificationGas)
    + parseHexBigInt(data.paymasterVerificationGasLimit)
    + parseHexBigInt(data.paymasterPostOpGasLimit);

  return totalGas * maxFeePerGas;
}

/** What the prepared calls must execute; every digest the key signs is recomputed from it. */
export type AlchemyPreparedCallsBinding = {
  chainId: bigint;
  sender: string;
  calls: EvmMetaTransaction[];
  /** Set only when the prepare request asked for a delegation. */
  delegate?: string;
};

const GLOBAL_OWNER_VALIDATION_LOCATOR = 1n;

const AUTHORIZATION_SIGNATURE_TYPES = new Set<AlchemySignatureRequest['type']>([
  'eip7702Auth',
  'eth_signAuthorization',
]);

function createWallet(privateKey: string) {
  return new Wallet(privateKey.startsWith('0x') ? privateKey : `0x${privateKey}`);
}

function getPersonalSignPayload(signatureRequest: AlchemySignatureRequest): string | undefined {
  if (typeof signatureRequest.data === 'object' && !!signatureRequest.data && 'raw' in signatureRequest.data) {
    return signatureRequest.data.raw;
  }

  return undefined;
}

/** ModularAccountV2 picks the validation from bits 64-103 of the nonce; 1 is the account's own key, global. */
function getValidationLocator(nonce: string) {
  return (BigInt(nonce) >> 64n) & 0xFFFFFFFFFFn;
}

function signAuthorization(wallet: Wallet, item: AlchemyPreparedCallItem, binding: AlchemyPreparedCallsBinding) {
  const { signatureRequest, data: { address, nonce } } = item;

  if (!signatureRequest || !AUTHORIZATION_SIGNATURE_TYPES.has(signatureRequest.type)) {
    throw new Error('Alchemy authorization has an unexpected signature request');
  }

  if (!address || !nonce || !binding.delegate || address.toLowerCase() !== binding.delegate.toLowerCase()) {
    throw new Error('Alchemy authorization delegates to a contract the wallet did not request');
  }

  return signEip7702AuthorizationSignature(
    wallet,
    binding.chainId,
    BigInt(nonce),
    address,
  );
}

function signUserOperation(wallet: Wallet, item: AlchemyPreparedCallItem, binding: AlchemyPreparedCallsBinding) {
  const { signatureRequest, data } = item;

  if (signatureRequest?.type !== 'personal_sign') {
    throw new Error('Alchemy user operation has an unexpected signature request');
  }

  if (!data.sender || data.sender.toLowerCase() !== binding.sender.toLowerCase()) {
    throw new Error('Alchemy user operation has another sender');
  }

  if (data.factory || data.factoryData) {
    throw new Error('Alchemy user operation carries an init call');
  }

  if (data.paymaster || data.paymasterData) {
    throw new Error('Alchemy user operation names a paymaster the wallet did not request');
  }

  if (!data.callData || !isModularAccountCallData(data.callData, binding.calls)) {
    throw new Error('Alchemy user operation calls differ from the requested calls');
  }

  if (!data.nonce || getValidationLocator(data.nonce) !== GLOBAL_OWNER_VALIDATION_LOCATOR) {
    throw new Error('Alchemy user operation selects another validation');
  }

  const digest = hashUserOperationV07(data as UserOperationV07Data, binding.chainId);
  const requestedDigest = getPersonalSignPayload(signatureRequest);

  if (requestedDigest && requestedDigest.toLowerCase() !== digest.toLowerCase()) {
    throw new Error('Alchemy signature request does not match the locally computed digest');
  }

  return wallet.signMessage(getBytes(digest));
}

/** A second user operation with the same calls would execute the swap twice. */
function assertSingleOperation(items: AlchemyPreparedCallItem[]) {
  const countOf = (type: string) => items.filter((item) => item.type === type).length;

  if (countOf('user-operation-v070') !== 1 || countOf('authorization') > 1) {
    throw new Error('Alchemy prepareCalls response must hold one user operation');
  }
}

async function signPreparedCallItem(
  wallet: Wallet,
  item: AlchemyPreparedCallItem,
  binding: AlchemyPreparedCallsBinding,
): Promise<string> {
  if (!item.chainId || BigInt(item.chainId) !== binding.chainId) {
    throw new Error('Alchemy prepared call targets another chain');
  }

  switch (item.type) {
    case 'authorization':
      return signAuthorization(wallet, item, binding);
    case 'user-operation-v070':
      return signUserOperation(wallet, item, binding);
    default:
      throw new Error(`Unsupported Alchemy prepared call type: ${item.type}`);
  }
}

export async function prepareAlchemyCalls(
  apiUrl: string,
  from: string,
  chainId: bigint,
  transactions: EvmMetaTransaction[],
  shouldDelegate: boolean,
): Promise<AlchemyPrepareCallsResult> {
  return alchemyWalletRpc<AlchemyPrepareCallsResult>(apiUrl, 'wallet_prepareCalls', [{
    calls: toAlchemyCalls(transactions),
    from,
    chainId: `0x${chainId.toString(16)}`,
    ...(shouldDelegate ? {
      capabilities: {
        eip7702Auth: {
          delegation: 'ModularAccountV2',
          version: 'v1.1.0',
        },
      },
    } : undefined),
  }]);
}

export async function signAlchemyPreparedCalls(
  prepareResult: AlchemyPrepareCallsResult,
  privateKey: string,
  binding: AlchemyPreparedCallsBinding,
): Promise<AlchemySignedPreparedCalls> {
  const wallet = createWallet(privateKey);

  if (prepareResult.type === 'array' && Array.isArray(prepareResult.data)) {
    assertSingleOperation(prepareResult.data);

    const signedData: AlchemyPreparedCallItem[] = [];

    for (const item of prepareResult.data) {
      signedData.push({
        type: item.type,
        data: item.data,
        chainId: item.chainId,
        signature: {
          type: 'secp256k1',
          data: await signPreparedCallItem(wallet, item, binding),
        },
      });
    }

    return { type: 'array', data: signedData };
  }

  if (!prepareResult.signatureRequest || !prepareResult.data || Array.isArray(prepareResult.data)) {
    throw new Error('Alchemy prepareCalls response missing signature request');
  }

  if (!prepareResult.chainId) {
    throw new Error('Alchemy prepareCalls response missing chainId');
  }

  return {
    type: prepareResult.type,
    data: prepareResult.data,
    chainId: prepareResult.chainId,
    signature: {
      type: 'secp256k1',
      data: await signPreparedCallItem(wallet, { ...prepareResult, data: prepareResult.data }, binding),
    },
  };
}

export async function sendAlchemyPreparedCalls(
  apiUrl: string,
  signedCalls: AlchemySignedPreparedCalls,
): Promise<AlchemySendPreparedCallsResult> {
  return alchemyWalletRpc<AlchemySendPreparedCallsResult>(apiUrl, 'wallet_sendPreparedCalls', [signedCalls]);
}

export async function getAlchemyCallsStatus(
  apiUrl: string,
  callId: string,
): Promise<AlchemyCallsStatusResult> {
  return alchemyWalletRpc<AlchemyCallsStatusResult>(apiUrl, 'wallet_getCallsStatus', [callId]);
}

const CALLS_STATUS_POLL_MS = 2_000;
const CALLS_STATUS_TIMEOUT_MS = 120_000;

function isPendingCallsStatus(status: number): boolean {
  return status >= 100 && status < 200;
}

function isFailedCallsStatus(status: number): boolean {
  return status >= 400;
}

export async function waitForAlchemyCallsConfirmation(
  apiUrl: string,
  callId: string,
): Promise<{ userOpHash: string; txHash: string; success: boolean }> {
  const startedAt = Date.now();

  while (Date.now() - startedAt < CALLS_STATUS_TIMEOUT_MS) {
    const statusResult = await getAlchemyCallsStatus(apiUrl, callId);

    if (isPendingCallsStatus(statusResult.status)) {
      await new Promise((resolve) => setTimeout(resolve, CALLS_STATUS_POLL_MS));
      continue;
    }

    if (isFailedCallsStatus(statusResult.status)) {
      return {
        userOpHash: statusResult.details?.data?.hash ?? callId,
        txHash: statusResult.receipts?.[0]?.transactionHash ?? '',
        success: false,
      };
    }

    const receipt = statusResult.receipts?.[0];
    const success = receipt?.status === '0x1';

    return {
      userOpHash: statusResult.details?.data?.hash ?? callId,
      txHash: receipt?.transactionHash ?? '',
      success: Boolean(success),
    };
  }

  throw new Error('Timed out waiting for Alchemy calls confirmation');
}
