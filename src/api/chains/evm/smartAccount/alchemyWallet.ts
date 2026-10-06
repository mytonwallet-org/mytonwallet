import { getBytes, Signature, Wallet } from 'ethers';

import type { ApiNetwork } from '../../../types';
import type { EvmMetaTransaction } from './types';

import { fetchJson } from '../../../../util/fetch';
import { signEip712WithPrivateKey } from '../sign';

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

function signRawPayload(privateKey: string, payload: string): string {
  const wallet = new Wallet(privateKey.startsWith('0x') ? privateKey : `0x${privateKey}`);
  const signature = wallet.signingKey.sign(getBytes(payload));

  return Signature.from(signature).serialized;
}

async function signPersonalMessage(privateKey: string, payload: string): Promise<string> {
  const wallet = new Wallet(privateKey.startsWith('0x') ? privateKey : `0x${privateKey}`);

  return wallet.signMessage(getBytes(payload));
}

function isRawSignatureType(type: AlchemySignatureRequest['type']): boolean {
  return type === 'eth_signAuthorization' || type === 'eip7702Auth';
}

function getPersonalSignPayload(signatureRequest: AlchemySignatureRequest): string | undefined {
  if (typeof signatureRequest.data === 'object' && !!signatureRequest.data && 'raw' in signatureRequest.data) {
    return signatureRequest.data.raw;
  }

  return undefined;
}

function getTypedDataPayload(signatureRequest: AlchemySignatureRequest): AlchemyEip712TypedData | undefined {
  if (signatureRequest.type !== 'eth_signTypedData_v4') {
    return undefined;
  }

  const data = signatureRequest.data;
  if (!data || typeof data !== 'object' || !('primaryType' in data)) {
    return undefined;
  }

  return data;
}

async function signSignatureRequest(
  network: ApiNetwork,
  privateKey: string,
  signatureRequest: AlchemySignatureRequest,
): Promise<string> {
  if (isRawSignatureType(signatureRequest.type)) {
    if (!signatureRequest.rawPayload) {
      throw new Error('Alchemy authorization signature request missing rawPayload');
    }

    return signRawPayload(privateKey, signatureRequest.rawPayload);
  }

  if (signatureRequest.type === 'personal_sign') {
    const personalSignPayload = getPersonalSignPayload(signatureRequest);
    if (personalSignPayload) {
      // data.raw is the inner digest; signMessage applies the EIP-191 prefix once.
      return signPersonalMessage(privateKey, personalSignPayload);
    }

    if (signatureRequest.rawPayload) {
      // rawPayload is already keccak256("\x19Ethereum Signed Message:\n32" || data.raw).
      return signRawPayload(privateKey, signatureRequest.rawPayload);
    }

    throw new Error('Alchemy personal_sign request missing payload');
  }

  if (signatureRequest.type === 'eth_signTypedData_v4') {
    const typedData = getTypedDataPayload(signatureRequest);

    if (!typedData) {
      throw new Error('Alchemy eth_signTypedData_v4 request missing typed data');
    }

    return signEip712WithPrivateKey(network, privateKey, typedData);
  }

  throw new Error(`Unsupported Alchemy signature request type: ${signatureRequest.type}`);
}

export async function prepareAlchemyCalls(
  apiUrl: string,
  from: string,
  chainId: bigint,
  transactions: EvmMetaTransaction[],
): Promise<AlchemyPrepareCallsResult> {
  return alchemyWalletRpc<AlchemyPrepareCallsResult>(apiUrl, 'wallet_prepareCalls', [{
    calls: toAlchemyCalls(transactions),
    from,
    chainId: `0x${chainId.toString(16)}`,
    capabilities: {
      eip7702Auth: {
        delegation: 'ModularAccountV2',
        version: 'v1.1.0',
      },
    },
  }]);
}

export async function signAlchemyPreparedCalls(
  prepareResult: AlchemyPrepareCallsResult,
  privateKey: string,
  network: ApiNetwork,
): Promise<AlchemySignedPreparedCalls> {
  if (prepareResult.type === 'array' && Array.isArray(prepareResult.data)) {
    const signedData: AlchemyPreparedCallItem[] = [];

    for (const item of prepareResult.data) {
      if (!item.signatureRequest) {
        throw new Error('Alchemy prepareCalls array item missing signatureRequest');
      }

      signedData.push({
        type: item.type,
        data: item.data,
        chainId: item.chainId,
        signature: {
          type: 'secp256k1',
          data: await signSignatureRequest(network, privateKey, item.signatureRequest),
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
      data: await signSignatureRequest(network, privateKey, prepareResult.signatureRequest),
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
