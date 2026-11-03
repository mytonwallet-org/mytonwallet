import type { ApiNetwork, EVMChain } from '../../../types';
import type { ApiAnyDisplayError } from '../../../types/errors';
import type { EvmBatchSubmitResult, EvmMetaTransaction } from './types';
import { ApiTransactionError, EvmSmartAccountError } from '../../../types';

import { logDebugError } from '../../../../util/logs';
import { getEvmDelegationAddress } from '../approvals';
import { canPayEvmTransactions } from '../wallet';
import {
  estimateMaxCostFromPrepareResult,
  prepareAlchemyCalls,
  sendAlchemyPreparedCalls,
  signAlchemyPreparedCalls,
  waitForAlchemyCallsConfirmation,
} from './alchemyWallet';
import { ALCHEMY_7702_REQUESTED_DELEGATE_ADDRESS, getAlchemyWalletApiUrl, getEvmChainId } from './constants';
import { resolveBatchDelegation, withForeignDelegationResetCall } from './delegation';

async function resolveBatchPreconditions(
  chain: EVMChain,
  network: ApiNetwork,
  address: string,
): Promise<{
  apiUrl: string;
  chainId: bigint;
  foreignDelegation?: string;
  shouldDelegate: boolean;
} | { error: ApiAnyDisplayError }> {
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

export async function estimateBatchUserOpFee(
  chain: EVMChain,
  network: ApiNetwork,
  address: string,
  transactions: EvmMetaTransaction[],
): Promise<{ maxCost: bigint } | { error: ApiAnyDisplayError }> {
  const preconditions = await resolveBatchPreconditions(chain, network, address);

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
    logDebugError(`evm:${chain}:estimateBatchUserOpFee`, err);

    return { error: ApiTransactionError.UnsuccesfulTransfer };
  }
}

export async function submitBatchUserOp(
  chain: EVMChain,
  network: ApiNetwork,
  address: string,
  privateKey: string,
  transactions: EvmMetaTransaction[],
): Promise<EvmBatchSubmitResult | { error: ApiAnyDisplayError }> {
  const preconditions = await resolveBatchPreconditions(chain, network, address);

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
    logDebugError(`evm:${chain}:submitBatchUserOp`, err);

    return { error: ApiTransactionError.UnsuccesfulTransfer };
  }
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
