import { Wallet } from 'ethers';

import type { ApiNetwork, EVMChain } from '../../../types';
import type { ApiAnyDisplayError } from '../../../types/errors';
import type { PimlicoEip7702Auth } from './pimlico';
import type { EvmBatchSubmitResult, EvmMetaTransaction } from './types';
import { ApiTransactionError, EvmSmartAccountError } from '../../../types';

import { logDebugError } from '../../../../util/logs';
import { getEvmProvider } from '../util/client';
import { getEvmDelegationAddress } from '../approvals';
import { canPayEvmTransactions, getErc20Balance } from '../wallet';
import {
  estimateMaxCostFromPrepareResult,
  prepareAlchemyCalls,
  sendAlchemyPreparedCalls,
  signAlchemyPreparedCalls,
  waitForAlchemyCallsConfirmation,
} from './alchemyWallet';
import {
  ALCHEMY_7702_REQUESTED_DELEGATE_ADDRESS,
  getAlchemyWalletApiUrl,
  getEvmChainId,
  isPimlicoGasToken,
} from './constants';
import {
  resolveBatchDelegation,
  signEip7702Authorization,
  withForeignDelegationResetCall,
} from './delegation';
import {
  estimateEvmGaslessBatch,
  sendEvmGaslessBatch,
} from './evmDieselBackend';
import { buildPimlicoEip7702AuthStub } from './pimlico';
import { isPimlicoUserOperationBound, signPimlicoUserOperation } from './pimlicoBatch';

export type EvmBatchUserOpOptions = {
  needsGasless: boolean;
  /** ERC-20 that pays the Pimlico paymaster; required when `needsGasless` is true */
  gasToken?: string;
  /** The highest maximum cost, in the currency that pays the fee, of an operation that may be signed */
  maxCostLimit?: bigint;
};

type AlchemyBatchPreconditions = {
  apiUrl: string;
  chainId: bigint;
  foreignDelegation?: string;
  shouldDelegate: boolean;
};

type PimlicoBatchPreconditions = {
  gasTokenAddress: string;
  foreignDelegation?: string;
  shouldDelegate: boolean;
};

async function resolveAlchemyBatchPreconditions(
  chain: EVMChain,
  network: ApiNetwork,
  address: string,
): Promise<AlchemyBatchPreconditions | { error: ApiAnyDisplayError }> {
  const apiUrl = getAlchemyWalletApiUrl(network);

  if (!apiUrl) {
    return { error: EvmSmartAccountError.BundlerNotConfigured };
  }

  const chainId = getEvmChainId(network, chain);

  if (chainId === undefined) {
    return { error: ApiTransactionError.WrongNetwork };
  }

  const { foreignDelegation, shouldDelegate } = resolveBatchDelegation(
    await getEvmDelegationAddress(chain, network, address),
  );

  return { apiUrl, chainId, foreignDelegation, shouldDelegate };
}

async function resolvePimlicoBatchPreconditions(
  chain: EVMChain,
  network: ApiNetwork,
  address: string,
  gasToken: string,
): Promise<PimlicoBatchPreconditions | { error: ApiAnyDisplayError }> {
  if (!isPimlicoGasToken(network, chain, gasToken)) {
    return { error: EvmSmartAccountError.BundlerNotConfigured };
  }

  const { foreignDelegation, shouldDelegate } = resolveBatchDelegation(
    await getEvmDelegationAddress(chain, network, address),
  );

  return { gasTokenAddress: gasToken, foreignDelegation, shouldDelegate };
}

async function ensureGasTokenBalance(
  chain: EVMChain,
  network: ApiNetwork,
  address: string,
  gasTokenAddress: string,
  maxCost: bigint,
): Promise<ApiAnyDisplayError | undefined> {
  const tokenBalance = await getErc20Balance(network, chain, address, gasTokenAddress);

  if (tokenBalance < maxCost) {
    return ApiTransactionError.InsufficientBalance;
  }

  return undefined;
}

async function resolvePimlicoAuthorizationNonce(
  network: ApiNetwork,
  chain: EVMChain,
  address: string,
): Promise<bigint> {
  const provider = getEvmProvider(network, chain);

  return BigInt(await provider.getTransactionCount(address, 'pending'));
}

async function resolveEip7702AuthStubForEstimate(
  network: ApiNetwork,
  chain: EVMChain,
  address: string,
  chainId: bigint,
  shouldDelegate: boolean,
): Promise<PimlicoEip7702Auth | undefined> {
  if (!shouldDelegate) {
    return undefined;
  }

  const authorizationNonce = await resolvePimlicoAuthorizationNonce(network, chain, address);

  return buildPimlicoEip7702AuthStub(
    ALCHEMY_7702_REQUESTED_DELEGATE_ADDRESS,
    chainId,
    authorizationNonce,
  );
}

async function resolveEip7702AuthForSend(
  network: ApiNetwork,
  chain: EVMChain,
  address: string,
  privateKey: string,
  chainId: bigint,
  shouldDelegate: boolean,
): Promise<PimlicoEip7702Auth | undefined> {
  if (!shouldDelegate) {
    return undefined;
  }

  const authorizationNonce = await resolvePimlicoAuthorizationNonce(network, chain, address);
  const wallet = new Wallet(privateKey.startsWith('0x') ? privateKey : `0x${privateKey}`);

  return signEip7702Authorization(
    wallet,
    chainId,
    authorizationNonce,
    ALCHEMY_7702_REQUESTED_DELEGATE_ADDRESS,
  );
}

async function estimateAlchemyBatchUserOpFee(
  chain: EVMChain,
  network: ApiNetwork,
  address: string,
  transactions: EvmMetaTransaction[],
): Promise<{ maxCost: bigint } | { error: ApiAnyDisplayError }> {
  const preconditions = await resolveAlchemyBatchPreconditions(chain, network, address);

  if ('error' in preconditions) {
    return preconditions;
  }

  const { apiUrl, chainId, foreignDelegation, shouldDelegate } = preconditions;

  try {
    const calls = withForeignDelegationResetCall(address, transactions, foreignDelegation);
    const prepareResult = await prepareAlchemyCalls(apiUrl, address, chainId, calls, shouldDelegate);
    const maxCost = estimateMaxCostFromPrepareResult(prepareResult);

    if (!await canPayEvmTransactions(chain, network, address, calls, maxCost)) {
      return { error: ApiTransactionError.InsufficientBalance };
    }

    return { maxCost };
  } catch (err) {
    logDebugError(`evm:${chain}:estimateAlchemyBatchUserOpFee`, err);

    return { error: ApiTransactionError.UnsuccesfulTransfer };
  }
}

async function submitAlchemyBatchUserOp(
  chain: EVMChain,
  network: ApiNetwork,
  address: string,
  privateKey: string,
  transactions: EvmMetaTransaction[],
  maxCostLimit?: bigint,
): Promise<EvmBatchSubmitResult | { error: ApiAnyDisplayError }> {
  const preconditions = await resolveAlchemyBatchPreconditions(chain, network, address);

  if ('error' in preconditions) {
    return preconditions;
  }

  const { apiUrl, chainId, foreignDelegation, shouldDelegate } = preconditions;

  try {
    const calls = withForeignDelegationResetCall(address, transactions, foreignDelegation);
    const prepareResult = await prepareAlchemyCalls(apiUrl, address, chainId, calls, shouldDelegate);
    const maxCost = estimateMaxCostFromPrepareResult(prepareResult);

    if (maxCostLimit !== undefined && maxCost > maxCostLimit) {
      return { error: EvmSmartAccountError.UserOperationMismatch };
    }

    if (!await canPayEvmTransactions(chain, network, address, calls, maxCost)) {
      return { error: ApiTransactionError.InsufficientBalance };
    }

    const signedCalls = await signAlchemyPreparedCalls(prepareResult, privateKey, {
      chainId,
      sender: address,
      calls,
      delegate: shouldDelegate ? ALCHEMY_7702_REQUESTED_DELEGATE_ADDRESS : undefined,
    });
    const sendResult = await sendAlchemyPreparedCalls(apiUrl, signedCalls);
    const confirmation = await waitForAlchemyCallsConfirmation(apiUrl, sendResult.id);

    if (!confirmation.success || !confirmation.txHash) {
      return { error: EvmSmartAccountError.UserOperationFailed };
    }

    return {
      userOpHash: confirmation.userOpHash,
      txHash: confirmation.txHash,
      success: true,
    };
  } catch (err) {
    logDebugError(`evm:${chain}:submitAlchemyBatchUserOp`, err);

    return { error: ApiTransactionError.UnsuccesfulTransfer };
  }
}

async function estimatePimlicoBatchUserOpFee(
  chain: EVMChain,
  network: ApiNetwork,
  address: string,
  transactions: EvmMetaTransaction[],
  gasToken: string,
): Promise<{ maxCost: bigint } | { error: ApiAnyDisplayError }> {
  const preconditions = await resolvePimlicoBatchPreconditions(chain, network, address, gasToken);

  if ('error' in preconditions) {
    return preconditions;
  }

  const { gasTokenAddress, foreignDelegation, shouldDelegate } = preconditions;
  const chainId = getEvmChainId(network, chain);

  if (chainId === undefined) {
    return { error: ApiTransactionError.WrongNetwork };
  }

  try {
    const calls = withForeignDelegationResetCall(address, transactions, foreignDelegation);
    const eip7702Auth = await resolveEip7702AuthStubForEstimate(
      network, chain, address, chainId, shouldDelegate,
    );

    const estimate = await estimateEvmGaslessBatch(
      chain, network, address, calls, gasTokenAddress, eip7702Auth,
    );
    const maxCost = BigInt(estimate.maxCost);

    const balanceError = await ensureGasTokenBalance(
      chain,
      network,
      address,
      gasTokenAddress,
      maxCost,
    );

    if (balanceError) {
      return { error: balanceError };
    }

    return { maxCost };
  } catch (err) {
    logDebugError(`evm:${chain}:estimatePimlicoBatchUserOpFee`, err);

    return { error: ApiTransactionError.UnsuccesfulTransfer };
  }
}

async function submitPimlicoBatchUserOp(
  chain: EVMChain,
  network: ApiNetwork,
  address: string,
  privateKey: string,
  transactions: EvmMetaTransaction[],
  gasToken: string,
  maxCostLimit?: bigint,
): Promise<EvmBatchSubmitResult | { error: ApiAnyDisplayError }> {
  const preconditions = await resolvePimlicoBatchPreconditions(chain, network, address, gasToken);

  if ('error' in preconditions) {
    return preconditions;
  }

  const { gasTokenAddress, foreignDelegation, shouldDelegate } = preconditions;
  const chainId = getEvmChainId(network, chain);

  if (chainId === undefined) {
    return { error: ApiTransactionError.WrongNetwork };
  }

  try {
    const calls = withForeignDelegationResetCall(address, transactions, foreignDelegation);

    const estimateEip7702Auth = await resolveEip7702AuthStubForEstimate(
      network, chain, address, chainId, shouldDelegate,
    );

    const estimate = await estimateEvmGaslessBatch(
      chain, network, address, calls, gasTokenAddress, estimateEip7702Auth,
    );

    const maxCost = BigInt(estimate.maxCost);

    if (maxCostLimit !== undefined && maxCost > maxCostLimit) {
      return { error: EvmSmartAccountError.UserOperationMismatch };
    }

    const balanceError = await ensureGasTokenBalance(
      chain,
      network,
      address,
      gasTokenAddress,
      maxCost,
    );

    if (balanceError) {
      return { error: balanceError };
    }

    if (!isPimlicoUserOperationBound(estimate, {
      chainId,
      sender: address,
      calls,
      gasTokenAddress,
      maxTokenCost: maxCost,
    })) {
      return { error: EvmSmartAccountError.UserOperationMismatch };
    }

    const eip7702Auth = await resolveEip7702AuthForSend(
      network,
      chain,
      address,
      privateKey,
      chainId,
      shouldDelegate,
    );

    const signature = await signPimlicoUserOperation(estimate.userOperation, privateKey, chainId);

    const sendResult = await sendEvmGaslessBatch(chain, network, {
      ...estimate.userOperation,
      signature,
      eip7702Auth: eip7702Auth ?? undefined,
    });

    if (!sendResult.success || !sendResult.txHash) {
      return { error: EvmSmartAccountError.UserOperationFailed };
    }

    return {
      userOpHash: sendResult.userOpHash,
      txHash: sendResult.txHash,
      success: true,
    };
  } catch (err) {
    logDebugError(`evm:${chain}:submitPimlicoBatchUserOp`, err);

    return { error: ApiTransactionError.UnsuccesfulTransfer };
  }
}

export async function estimateBatchUserOpFee(
  chain: EVMChain,
  network: ApiNetwork,
  address: string,
  transactions: EvmMetaTransaction[],
  options?: EvmBatchUserOpOptions,
): Promise<{ maxCost: bigint } | { error: ApiAnyDisplayError }> {
  if (options?.needsGasless) {
    if (!options.gasToken) {
      return { error: EvmSmartAccountError.BundlerNotConfigured };
    }

    return estimatePimlicoBatchUserOpFee(chain, network, address, transactions, options.gasToken);
  }

  return estimateAlchemyBatchUserOpFee(chain, network, address, transactions);
}

export async function submitBatchUserOp(
  chain: EVMChain,
  network: ApiNetwork,
  address: string,
  privateKey: string,
  transactions: EvmMetaTransaction[],
  options?: EvmBatchUserOpOptions,
): Promise<EvmBatchSubmitResult | { error: ApiAnyDisplayError }> {
  if (options?.needsGasless) {
    if (!options.gasToken) {
      return { error: EvmSmartAccountError.BundlerNotConfigured };
    }

    return submitPimlicoBatchUserOp(
      chain, network, address, privateKey, transactions, options.gasToken, options.maxCostLimit,
    );
  }

  return submitAlchemyBatchUserOp(chain, network, address, privateKey, transactions, options?.maxCostLimit);
}

export function validateEvmSwapCalls(
  calls: EvmMetaTransaction[],
  allowedTargets: Set<string>,
): ApiAnyDisplayError | undefined {
  if (!calls.length) {
    return ApiTransactionError.UnsuccesfulTransfer;
  }

  for (const call of calls) {
    const normalizedTo = call.to.toLowerCase();
    if (!allowedTargets.has(normalizedTo)) {
      return ApiTransactionError.UnsuccesfulTransfer;
    }

    if (!call.data || call.data === '0x') {
      return ApiTransactionError.UnsuccesfulTransfer;
    }
  }

  return undefined;
}
