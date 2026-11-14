import type { TransactionRequest } from 'ethers';

import type { EvmProvider } from './util/client';

import { raceWithAbortSignal } from '../../../util/abortSignal';

export async function estimateEvmFee(
  provider: EvmProvider,
  txRequest: TransactionRequest,
  signal?: AbortSignal,
): Promise<bigint> {
  const { fee } = await estimateEvmGas(provider, txRequest, signal);

  return fee;
}

export async function estimateEvmGas(
  provider: EvmProvider,
  txRequest: TransactionRequest,
  signal?: AbortSignal,
): Promise<{ gasLimit: bigint; fee: bigint }> {
  const [gasLimit, feeData] = await raceWithAbortSignal(() => Promise.all([
    provider.estimateGas(txRequest),
    provider.getFeeData(),
  ]), signal);

  // Prefer EIP-1559 maxFeePerGas for a conservative upper-bound estimate or use fallback to legacy gasPrice.
  const gasPrice = feeData.maxFeePerGas ?? feeData.gasPrice ?? 0n;

  return { gasLimit, fee: gasLimit * gasPrice };
}
