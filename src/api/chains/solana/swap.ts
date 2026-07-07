import {
  getBase64Decoder,
  getBase64Encoder,
  getCompiledTransactionMessageDecoder,
  getTransactionDecoder,
} from '@solana/kit';

import type {
  ApiAnyDisplayError,
  ApiNetwork,
  ApiSwapActivity,
  ApiSwapHistoryItem,
  OnApiUpdate,
} from '../../types';
import type {
  ApiBuildOnchainSwapTransferOptions,
  ApiBuildOnchainSwapTransferResult,
  ApiSubmitOnchainSwapTransferOptions,
} from '../../types/swap';
import type { SolanaTransactionEmulationResult } from './types';
import { ApiCommonError, ApiSwapError } from '../../types';

import { Big } from '../../../lib/big.js';
import { parseAccountId } from '../../../util/account';
import { logDebugError } from '../../../util/logs';
import { parseTokenOperation } from './util/programParsers';
import { fetchStoredWallet } from '../../common/accounts';
import { patchSwapItem } from '../../common/swap';
import { callHook } from '../../hooks';
import { fetchPrivateKeyString } from './auth';
import { emulateTransaction } from './emulation';
import { partiallySignTransaction } from './sign';
import { estimateTransactionFee } from './transfer';

const SWAP_AMOUNT_TOLERANCE = 0.05;

function assertSwapAmountWithinTolerance(actual: string, expected: string, label: string) {
  const expectedAmount = Big(expected);
  const actualAmount = Big(actual);
  const maxDiff = expectedAmount.abs().mul(SWAP_AMOUNT_TOLERANCE);

  // FIXME: calculate net amount & fees in `parseTokenOperation`
  if (expectedAmount.lte(0.003) && actualAmount.lte(0.003)) {
    return; // Ignore tiny amounts with complicated fee calculations
  }
  if (expectedAmount.minus(actualAmount).abs().lt(0.004)) {
    return; // Ignore small differences
  }

  if (actualAmount.minus(expectedAmount).abs().gt(maxDiff)) {
    throw new Error(
      `Swap ${label} amount ${actual} is outside of expected range (${expected})`,
    );
  }
}

export async function buildOnchainSwapTransfer(
  options: ApiBuildOnchainSwapTransferOptions,
): Promise<ApiBuildOnchainSwapTransferResult | { error: ApiAnyDisplayError }> {
  const { accountId, transaction, swapId, authToken } = options;

  if (!transaction) {
    throw new Error('Transaction is required');
  }

  const { network } = parseAccountId(accountId);
  const { address: historyAddress } = await fetchStoredWallet(accountId, 'ton');

  try {
    let result: { fee: bigint } | { error: ApiAnyDisplayError } | undefined;
    try {
      result = await estimateTransactionFee({ network, serializedB64Transaction: transaction });
    } catch (error) {
      logDebugError('buildOnchainSwapTransfer:estimateTransactionFee failed', error);

      await patchSwapItem({
        address: historyAddress, swapId, authToken, error: ApiSwapError.SlippageError,
      });
      return { error: ApiSwapError.SlippageError };
    }

    if ('error' in result) {
      await patchSwapItem({
        address: historyAddress, swapId, authToken, error: result.error,
      });
      return result;
    }

    return {
      id: swapId,
      chain: 'solana',
      transaction,
    };
  } catch (err: any) {
    await patchSwapItem({
      address: historyAddress, swapId, authToken, error: errorToString(err),
    });
    throw err;
  }
}

async function validateSwapTransaction(
  transaction: string,
  walletAddress: string,
  network: ApiNetwork,
  expected: ApiSwapHistoryItem,
): Promise<ApiAnyDisplayError | undefined> {
  if (expected.fromAddress !== walletAddress) {
    throw new Error(
      `Swap fromAddress ${expected.fromAddress} does not match wallet address ${walletAddress}`,
    );
  }

  const txBytes = getBase64Encoder().encode(transaction);
  const decoded = getTransactionDecoder().decode(txBytes);
  const compiled = getCompiledTransactionMessageDecoder().decode(decoded.messageBytes);
  let emulated: SolanaTransactionEmulationResult | undefined;

  try {
    emulated = await emulateTransaction(transaction, network);
  } catch (error) {
    logDebugError('validateSwapTransaction:emulation failed', error);

    return ApiSwapError.SlippageError;
  }

  if (!emulated || emulated.err) {
    throw new Error(`Swap transaction simulation failed: ${JSON.stringify(emulated?.err)}`);
  }

  const tokenOperation = await parseTokenOperation(
    network,
    emulated as any,
    walletAddress,
    compiled.staticAccounts,
  );

  if (!tokenOperation?.isSwap) {
    throw new Error('Swap transaction must perform a token swap');
  }

  const { swap } = tokenOperation;

  if (swap.fromAddress !== walletAddress) {
    throw new Error(
      `Swap initiator ${swap.fromAddress} does not match wallet address ${walletAddress}`,
    );
  }

  if (swap.from !== expected.from) {
    throw new Error(`Swap from asset ${swap.from} does not match expected ${expected.from}`);
  }

  if (swap.to !== expected.to) {
    throw new Error(`Swap to asset ${swap.to} does not match expected ${expected.to}`);
  }

  assertSwapAmountWithinTolerance(swap.fromAmount, expected.fromAmount, 'input');
  assertSwapAmountWithinTolerance(swap.toAmount, expected.toAmount, 'output');
}

export async function submitOnchainSwapTransfer(
  options: ApiSubmitOnchainSwapTransferOptions,
  onUpdate: OnApiUpdate,
): Promise<{ activityId: string } | { error: string }> {
  const {
    accountId,
    password,
    transaction,
    authToken,
    localSwap,
    swapId,
    executeSwap,
  } = options;

  if (!transaction) {
    throw new Error('Transaction is required');
  }

  if (!executeSwap) {
    throw new Error('executeSwap callback is required for Solana on-chain swaps');
  }

  const { network } = parseAccountId(accountId);
  const { address } = await fetchStoredWallet(accountId, 'solana');
  const { address: historyAddress } = await fetchStoredWallet(accountId, 'ton');

  onUpdate({
    type: 'newLocalActivities',
    accountId,
    activities: [localSwap],
  });

  try {
    const privateKey = await fetchPrivateKeyString(accountId, password);

    if (!privateKey) {
      return { error: ApiCommonError.InvalidPassword };
    }

    const validationError = await validateSwapTransaction(transaction, address, network, localSwap);

    if (validationError) {
      onUpdate({
        type: 'newLocalActivities',
        accountId,
        activities: [{ ...localSwap, status: 'failed' }],
      });

      await patchSwapItem({
        address: historyAddress,
        swapId,
        authToken,
        error: validationError,
      });

      return { error: validationError };
    }

    const { signedBytes } = partiallySignTransaction(network, privateKey, transaction);
    const signedTransaction = getBase64Decoder().decode(signedBytes);

    const executeResult = await executeSwap(signedTransaction);

    if (!executeResult.success) {
      onUpdate({
        type: 'newLocalActivities',
        accountId,
        activities: [{ ...localSwap, status: 'failed' }],
      });

      await patchSwapItem({
        address: historyAddress,
        swapId,
        authToken,
        error: executeResult.error ?? `Execution failed (${executeResult.code})`,
      });

      return { error: executeResult.error ?? 'Swap execution failed' };
    }

    const updatedSwap: ApiSwapActivity = {
      ...localSwap,
      externalMsgHashNorm: executeResult.signature,
      hashes: [executeResult.signature],
      transactionIds: { outgoing: { hash: executeResult.signature, chain: 'solana' } },
    };

    onUpdate({
      type: 'newLocalActivities',
      accountId,
      activities: [updatedSwap],
    });

    await patchSwapItem({
      address: historyAddress, swapId, authToken, msgHash: executeResult.signature,
    });

    void callHook('onSwapCreated', accountId, updatedSwap.timestamp - 1);

    return { activityId: updatedSwap.id };
  } catch (err: any) {
    onUpdate({
      type: 'newLocalActivities',
      accountId,
      activities: [{ ...localSwap, status: 'failed' }],
    });

    await patchSwapItem({
      address: historyAddress, swapId, authToken, error: errorToString(err),
    });
    throw err;
  }
}

function errorToString(err: Error | string) {
  return typeof err === 'string' ? err : err.stack ?? err.message;
}
