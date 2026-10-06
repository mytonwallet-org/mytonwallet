import { Interface, type TransactionRequest } from 'ethers';

import type {
  ApiAnyDisplayError,
  ApiNetwork,
  ApiSwapActivity,
  EVMChain,
  OnApiUpdate,
} from '../../types';
import type {
  ApiBuildOnchainSwapTransferOptions,
  ApiBuildOnchainSwapTransferResult,
  ApiSubmitOnchainSwapTransferOptions,
  ApiSubmitOnchainSwapTransferResult,
} from '../../types/swap';
import type { EvmMetaTransaction } from './smartAccount/types';
import { ApiCommonError, ApiTransactionError } from '../../types';

import { parseAccountId } from '../../../util/account';
import { bigintMax, bigintMultiplyToNumber } from '../../../util/bigint';
import { logDebugError } from '../../../util/logs';
import { fetchEvmWallet } from './util/account';
import { getEvmProvider } from './util/client';
import { fetchStoredChainAccount, fetchStoredWallet } from '../../common/accounts';
import { patchSwapItem } from '../../common/swap';
import {
  estimateBatchUserOpFee,
  submitBatchUserOp,
  validateEvmSwapCalls,
} from './smartAccount/batch';
import { normalizeAddress } from './address';
import { fetchPrivateKeyString, getSignerFromPrivateKey } from './auth';
import { EVM_MAX_TRANSFER_FEE_MULTIPLIER, UNISWAP_PERMIT2_ADDRESS } from './constants';
import { signEip712WithPrivateKey } from './sign';
import { serializeEvmSwapCalls } from './swapCalls';
import { getWalletBalance } from './wallet';

const erc20ApproveInterface = new Interface(['function approve(address spender, uint256 amount) returns (bool)']);
const permit2AllowanceInterface = new Interface([
  'function approve(address token, address spender, uint160 amount, uint48 expiration)',
]);
const permit2PermitInterface = new Interface([
  // eslint-disable-next-line @stylistic/max-len
  'function permit(address owner, ((address token, uint160 amount, uint48 expiration, uint48 nonce) details, address spender, uint256 sigDeadline) permitSingle, bytes signature)',
]);

const MAX_PERMIT2_AMOUNT = (1n << 160n) - 1n;
const MAX_PERMIT2_EXPIRATION = (1n << 48n) - 1n;

type UniswapPermitDetails = {
  token: string;
  amount: string;
  expiration: string;
  nonce: string;
};

type UniswapPermitSingleValues = {
  details: UniswapPermitDetails;
  spender: string;
  sigDeadline: string;
};

type UniswapPermitData = {
  domain: Record<string, unknown>;
  types: Record<string, Array<{ name: string; type: string }>>;
  values: UniswapPermitSingleValues;
};

type UniswapTransactionRequest = {
  to: string;
  from: string;
  data: string;
  value: string;
  chainId: number;
  gasLimit?: string;
  maxFeePerGas?: string;
  maxPriorityFeePerGas?: string;
  gasPrice?: string;
};

type UniswapEvmTransactionPayload = {
  routing: string;
  swap?: UniswapTransactionRequest;
  approval?: UniswapTransactionRequest;
  permitData?: UniswapPermitData | null;
  requiresPermitSignature: boolean;
};

export function parseUniswapTransactionPayload(transaction: string): UniswapEvmTransactionPayload {
  const payload = JSON.parse(transaction) as UniswapEvmTransactionPayload;

  if (typeof payload.requiresPermitSignature !== 'boolean') {
    throw new Error('Invalid Uniswap swap payload');
  }

  return payload;
}

function uniswapTxToMetaTransaction(tx: UniswapTransactionRequest): EvmMetaTransaction {
  return {
    to: tx.to,
    value: BigInt(tx.value || '0'),
    data: tx.data,
  };
}

function isPermit2Address(address: string): boolean {
  return normalizeAddress(address) === UNISWAP_PERMIT2_ADDRESS;
}

function tryParseErc20ApproveSpender(data: string): string | undefined {
  try {
    const [spender] = erc20ApproveInterface.decodeFunctionData('approve', data);
    return typeof spender === 'string' ? normalizeAddress(spender) : undefined;
  } catch {
    return undefined;
  }
}

export function hasUniswapPermitData(payload: UniswapEvmTransactionPayload): payload is UniswapEvmTransactionPayload & {
  permitData: UniswapPermitData;
} {
  return !!payload.permitData?.domain && !!payload.permitData.types && !!payload.permitData.values;
}

export function shouldIncludePermit2AllowanceCall(payload: UniswapEvmTransactionPayload) {
  if (hasUniswapPermitData(payload) || !payload.approval || !payload.swap) {
    return false;
  }

  const approvalSpender = tryParseErc20ApproveSpender(payload.approval.data);
  return !!approvalSpender && isPermit2Address(approvalSpender);
}

function buildPermit2AllowanceCall(token: string, spender: string): EvmMetaTransaction {
  return {
    to: UNISWAP_PERMIT2_ADDRESS,
    value: 0n,
    data: permit2AllowanceInterface.encodeFunctionData('approve', [
      token,
      spender,
      MAX_PERMIT2_AMOUNT,
      MAX_PERMIT2_EXPIRATION,
    ]),
  };
}

export function buildPermit2PermitCall(
  owner: string,
  permitData: UniswapPermitData,
  signature: string,
): EvmMetaTransaction {
  const { details, spender, sigDeadline } = permitData.values;

  return {
    to: UNISWAP_PERMIT2_ADDRESS,
    value: 0n,
    data: permit2PermitInterface.encodeFunctionData('permit', [
      owner,
      {
        details: {
          token: details.token,
          amount: BigInt(details.amount),
          expiration: Number(details.expiration),
          nonce: Number(details.nonce),
        },
        spender,
        sigDeadline: BigInt(sigDeadline),
      },
      signature,
    ]),
  };
}

export async function signUniswapPermit2(
  network: ApiNetwork,
  privateKey: string,
  permitData: UniswapPermitData,
): Promise<string> {
  return signEip712WithPrivateKey(network, privateKey, {
    domain: permitData.domain,
    types: permitData.types,
    message: permitData.values,
  });
}

function resolveUniswapBatchOwner(payload: UniswapEvmTransactionPayload): string {
  const owner = payload.swap?.from ?? payload.approval?.from;

  if (!owner) {
    throw new Error('Missing swap owner for Permit2 permit');
  }

  return owner;
}

export function buildUniswapBatchCalls(
  payload: UniswapEvmTransactionPayload,
  permitSignature?: string,
): EvmMetaTransaction[] {
  const calls: EvmMetaTransaction[] = [];

  if (payload.approval) {
    calls.push(uniswapTxToMetaTransaction(payload.approval));
  }

  if (hasUniswapPermitData(payload)) {
    if (!permitSignature) {
      throw new Error('Missing Permit2 EIP-712 signature');
    }

    calls.push(buildPermit2PermitCall(
      resolveUniswapBatchOwner(payload),
      payload.permitData,
      permitSignature,
    ));
  } else if (shouldIncludePermit2AllowanceCall(payload)) {
    calls.push(buildPermit2AllowanceCall(payload.approval!.to, payload.swap!.to));
  }

  if (payload.swap) {
    calls.push(uniswapTxToMetaTransaction(payload.swap));
  }

  return calls;
}

async function buildSignedUniswapBatchCalls(
  network: ApiNetwork,
  privateKey: string,
  payload: UniswapEvmTransactionPayload,
): Promise<EvmMetaTransaction[]> {
  let permitSignature: string | undefined;

  if (hasUniswapPermitData(payload)) {
    permitSignature = await signUniswapPermit2(network, privateKey, payload.permitData);
  }

  return buildUniswapBatchCalls(payload, permitSignature);
}

export function getUniswapAllowedTargets(payload: UniswapEvmTransactionPayload) {
  const targets = new Set<string>();

  if (payload.approval?.to) {
    targets.add(payload.approval.to.toLowerCase());
  }

  if (payload.swap?.to) {
    targets.add(payload.swap.to.toLowerCase());
  }

  if (hasUniswapPermitData(payload) || shouldIncludePermit2AllowanceCall(payload)) {
    targets.add(UNISWAP_PERMIT2_ADDRESS.toLowerCase());
  }

  return targets;
}

function errorToString(err: unknown): string {
  return err instanceof Error ? err.message : String(err);
}

async function fetchSwapHistoryAddress(accountId: string) {
  const { address } = await fetchStoredWallet(accountId, 'ton');
  return address;
}

function assertUniswapPayloadReady(
  payload: UniswapEvmTransactionPayload,
): ApiAnyDisplayError | undefined {
  if (!payload.swap) {
    return ApiTransactionError.UnsuccesfulTransfer;
  }

  if (payload.requiresPermitSignature && !hasUniswapPermitData(payload)) {
    return ApiTransactionError.UnsuccesfulTransfer;
  }

  return undefined;
}

function toTransactionRequest(
  address: string,
  tx: UniswapTransactionRequest,
): TransactionRequest {
  return {
    from: address,
    to: tx.to,
    data: tx.data,
    value: BigInt(tx.value || '0'),
  };
}

export function resolveSwapGasLimit(estimatedGasLimit: bigint, backendGasLimit?: string) {
  let gasLimit = bigintMultiplyToNumber(estimatedGasLimit, EVM_MAX_TRANSFER_FEE_MULTIPLIER);

  if (backendGasLimit) {
    gasLimit = bigintMax(gasLimit, BigInt(backendGasLimit));
  }

  return gasLimit;
}

async function estimateRegularSwapFee(
  chain: EVMChain,
  network: ApiNetwork,
  address: string,
  payload: UniswapEvmTransactionPayload,
  useBatching: boolean,
): Promise<{ error: ApiAnyDisplayError } | undefined> {
  const provider = getEvmProvider(network, chain);
  const transactions: Array<{ request: TransactionRequest; backendGasLimit?: string }> = [];

  if (!useBatching && payload.approval) {
    transactions.push({
      request: toTransactionRequest(address, payload.approval),
      backendGasLimit: payload.approval.gasLimit,
    });
  }

  if (payload.swap) {
    transactions.push({
      request: toTransactionRequest(address, payload.swap),
      backendGasLimit: payload.swap.gasLimit,
    });
  }

  let totalFee = 0n;

  const feeData = await provider.getFeeData();
  const gasPrice = feeData.maxFeePerGas ?? feeData.gasPrice ?? 0n;

  for (const { request, backendGasLimit } of transactions) {
    const estimatedGasLimit = await provider.estimateGas(request);
    const gasLimit = resolveSwapGasLimit(estimatedGasLimit, backendGasLimit);
    totalFee += gasLimit * gasPrice;
  }

  const nativeBalance = await getWalletBalance(chain, network, address);
  if (nativeBalance < totalFee) {
    return { error: ApiTransactionError.InsufficientBalance };
  }

  return undefined;
}

async function sendUniswapTransaction(
  chain: EVMChain,
  network: ApiNetwork,
  address: string,
  privateKey: string,
  tx: UniswapTransactionRequest,
) {
  const provider = getEvmProvider(network, chain);
  const signer = getSignerFromPrivateKey(network, privateKey).connect(provider);
  const transaction = toTransactionRequest(address, tx);
  const estimatedGasLimit = await provider.estimateGas(transaction);
  const gasLimit = resolveSwapGasLimit(estimatedGasLimit, tx.gasLimit);

  const response = await signer.sendTransaction({ ...transaction, gasLimit });

  return response.hash;
}

export async function buildOnchainSwapTransfer(
  chain: EVMChain,
  options: ApiBuildOnchainSwapTransferOptions,
): Promise<ApiBuildOnchainSwapTransferResult | { error: ApiAnyDisplayError }> {
  const { accountId, request, transaction, swapId, authToken, enclaveToken } = options;
  const { network } = parseAccountId(accountId);

  if (!transaction) {
    return { error: ApiTransactionError.UnsuccesfulTransfer };
  }

  const historyAddress = await fetchSwapHistoryAddress(accountId);

  try {
    const { address } = await fetchEvmWallet(accountId, chain);
    const payload = parseUniswapTransactionPayload(transaction);
    const payloadError = assertUniswapPayloadReady(payload);

    if (payloadError) {
      await patchSwapItem({ address: historyAddress, swapId, authToken, error: payloadError });
      return { error: payloadError };
    }

    if (request.needsApprove) {
      const account = await fetchStoredChainAccount(accountId, chain);

      if (account.type === 'ledger' || account.type === 'view') {
        return { error: ApiTransactionError.UnsuccesfulTransfer };
      }

      const privateKey = await fetchPrivateKeyString(chain, accountId, enclaveToken, account);

      if (!privateKey) {
        return { error: ApiCommonError.InvalidPassword };
      }

      const calls = await buildSignedUniswapBatchCalls(network, privateKey, payload);

      if (!calls.length) {
        return { error: ApiTransactionError.UnsuccesfulTransfer };
      }

      const feeResult = await estimateBatchUserOpFee(chain, network, address, calls);

      if ('error' in feeResult) {
        await patchSwapItem({ address: historyAddress, swapId, authToken, error: feeResult.error });
        return feeResult;
      }

      return {
        id: swapId,
        chain,
        transaction,
        calls: serializeEvmSwapCalls(calls),
        isBatchTx: true,
      };
    }

    const feeError = await estimateRegularSwapFee(chain, network, address, payload, !!request.needsApprove);

    if (feeError) {
      await patchSwapItem({ address: historyAddress, swapId, authToken, error: feeError.error });
      return feeError;
    }

    return {
      id: swapId,
      chain,
      transaction,
    };
  } catch (err) {
    await patchSwapItem({
      address: historyAddress, swapId, authToken, error: errorToString(err),
    });

    throw err;
  }
}

async function submitRegularUniswapSwap(
  chain: EVMChain,
  network: ApiNetwork,
  address: string,
  privateKey: string,
  transaction: string,
  useBatching: boolean,
): Promise<{ txHash: string } | { error: ApiAnyDisplayError }> {
  const payload = parseUniswapTransactionPayload(transaction);
  const payloadError = assertUniswapPayloadReady(payload);

  if (payloadError) {
    return { error: payloadError };
  }

  const transactions: UniswapTransactionRequest[] = [];

  if (!useBatching && payload.approval) {
    transactions.push(payload.approval);
  }

  transactions.push(payload.swap!);

  let lastHash = '';

  try {
    for (const tx of transactions) {
      lastHash = await sendUniswapTransaction(chain, network, address, privateKey, tx);
    }

    return { txHash: lastHash };
  } catch (err) {
    logDebugError(`evm:${chain}:submitRegularUniswapSwap`, err);
    return { error: ApiTransactionError.UnsuccesfulTransfer };
  }
}

export async function submitOnchainSwapTransfer(
  chain: EVMChain,
  options: ApiSubmitOnchainSwapTransferOptions,
  onUpdate: OnApiUpdate,
): Promise<ApiSubmitOnchainSwapTransferResult> {
  const {
    accountId,
    enclaveToken,
    authToken,
    localSwap,
    swapId,
    transaction,
    needsApprove,
  } = options;

  const { network } = parseAccountId(accountId);
  const [historyAddress, { address }] = await Promise.all([
    fetchSwapHistoryAddress(accountId),
    fetchEvmWallet(accountId, chain),
  ]);
  const account = await fetchStoredChainAccount(accountId, chain);

  if (account.type === 'ledger' || account.type === 'view') {
    return { error: ApiTransactionError.UnsuccesfulTransfer };
  }

  onUpdate({
    type: 'newLocalActivities',
    accountId,
    activities: [localSwap],
  });

  try {
    const privateKey = await fetchPrivateKeyString(chain, accountId, enclaveToken, account);

    if (!privateKey) {
      return { error: ApiCommonError.InvalidPassword };
    }

    let txHash: string;

    if (needsApprove) {
      if (!transaction) {
        return { error: ApiTransactionError.UnsuccesfulTransfer };
      }

      const payload = parseUniswapTransactionPayload(transaction);
      const payloadError = assertUniswapPayloadReady(payload);

      if (payloadError) {
        return { error: payloadError };
      }

      const calls = await buildSignedUniswapBatchCalls(network, privateKey, payload);

      const validationError = validateEvmSwapCalls(calls, getUniswapAllowedTargets(payload));

      if (validationError) {
        return { error: validationError };
      }

      const result = await submitBatchUserOp(chain, network, address, privateKey, calls);

      if ('error' in result) {
        onUpdate({
          type: 'newLocalActivities',
          accountId,
          activities: [{ ...localSwap, status: 'failed' }],
        });

        await patchSwapItem({ address: historyAddress, swapId, authToken, error: result.error });

        return { error: result.error };
      }

      txHash = result.txHash;
    } else {
      if (!transaction) {
        return { error: ApiTransactionError.UnsuccesfulTransfer };
      }

      const result = await submitRegularUniswapSwap(
        chain, network, address, privateKey, transaction, !!needsApprove,
      );

      if ('error' in result) {
        onUpdate({
          type: 'newLocalActivities',
          accountId,
          activities: [{ ...localSwap, status: 'failed' }],
        });

        await patchSwapItem({ address: historyAddress, swapId, authToken, error: result.error });

        return { error: result.error };
      }

      txHash = result.txHash;
    }

    const updatedSwap: ApiSwapActivity = {
      ...localSwap,
      externalMsgHashNorm: txHash,
      hashes: [txHash],
      transactionIds: { outgoing: { hash: txHash, chain } },
    };

    onUpdate({
      type: 'newLocalActivities',
      accountId,
      activities: [updatedSwap],
    });

    await patchSwapItem({
      address: historyAddress, swapId, authToken, msgHash: txHash, msgHashNormalized: txHash,
    });

    return { activityId: localSwap.id, submittedHashes: [txHash] };
  } catch (err) {
    logDebugError(`evm:${chain}:submitOnchainSwapTransfer`, err);

    onUpdate({
      type: 'newLocalActivities',
      accountId,
      activities: [{ ...localSwap, status: 'failed' }],
    });

    await patchSwapItem({
      address: historyAddress, swapId, authToken, error: errorToString(err),
    });

    return { error: ApiTransactionError.UnsuccesfulTransfer };
  }
}
