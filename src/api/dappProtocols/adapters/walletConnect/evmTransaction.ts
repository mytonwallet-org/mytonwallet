import { Transaction } from 'ethers';

import type { ApiNetwork, EVMChain } from '../../../types';
import type { EvmTransactionParams } from './types';

import { logDebugError } from '../../../../util/logs';
import chains from '../../../chains';
import { getEvmProvider } from '../../../chains/evm/util/client';

const WALLET_CONNECT_EVM_FEE_BUMP_PERCENT = 10n;
const WALLET_CONNECT_EVM_GAS_LIMIT_BUMP_PERCENT = 25n;

type EvmFeeData = Awaited<ReturnType<ReturnType<typeof getEvmProvider>['getFeeData']>>;

/**
 * Builds an unsigned serialized hex transaction (EIP-2718 / legacy) for preview/signing,
 * matching `eth_sendTransaction` JSON-RPC field shapes. Fills missing fees, nonce and gas
 * limit from the provider, then bumps fees to improve inclusion odds.
 */
export async function resolveWalletConnectEvmSerializedTx(options: {
  raw: string | EvmTransactionParams;
  chain: EVMChain;
  network: ApiNetwork;
  caip2: string;
  signerAddress: string;
}): Promise<string> {
  const { raw, chain, network, caip2, signerAddress } = options;

  if (typeof raw === 'string') {
    let tx: Transaction;
    try {
      tx = Transaction.from(normalizeHexTxForEvm(raw));
    } catch (err) {
      logDebugError('walletConnect:resolveWalletConnectEvmSerializedTx:parse', err);

      throw new Error('Invalid transaction fields');
    }

    if (tx.isSigned()) {
      return raw;
    }

    const fromAddr = chains['ethereum'].normalizeAddress(signerAddress);
    const updated = tx.clone();
    let provider: ReturnType<typeof getEvmProvider> | undefined;

    try {
      provider = getEvmProvider(network, chain);

      const fallbackFee = await provider.getFeeData();

      fillWalletConnectEvmTransactionFees(updated, fallbackFee);
    } catch (err) {
      logDebugError('walletConnect:resolveWalletConnectEvmSerializedTx:fee', err);
    }

    bumpWalletConnectEvmTransactionFees(updated);

    try {
      provider ??= getEvmProvider(network, chain);

      const pendingNonce = await provider.getTransactionCount(fromAddr, 'pending');

      if (updated.nonce === 0 && pendingNonce > 0) {
        updated.nonce = pendingNonce;
      }
    } catch (err) {
      logDebugError('walletConnect:resolveWalletConnectEvmSerializedTx:nonce', err);
    }

    if (updated.gasLimit === 0n) {
      try {
        provider ??= getEvmProvider(network, chain);

        const estimated = await provider.estimateGas({
          from: fromAddr,
          to: updated.to ?? undefined,
          value: updated.value,
          data: updated.data,
        });

        updated.gasLimit = (estimated * (100n + WALLET_CONNECT_EVM_GAS_LIMIT_BUMP_PERCENT)) / 100n;
      } catch (err) {
        logDebugError('walletConnect:resolveWalletConnectEvmSerializedTx:gas', err);
      }
    }

    return updated.unsignedSerialized;
  }

  let txParamsForHex = raw;
  let provider: ReturnType<typeof getEvmProvider> | undefined;

  try {
    provider = getEvmProvider(network, chain);

    const fallbackFee = await provider.getFeeData();

    txParamsForHex = fillWalletConnectEvmTransactionParamsFees(txParamsForHex, fallbackFee);
  } catch (err) {
    logDebugError('walletConnect:resolveWalletConnectEvmSerializedTx:fee', err);
  }

  txParamsForHex = bumpWalletConnectEvmTransactionParamsFees(txParamsForHex);

  if (txParamsForHex.nonce === undefined || txParamsForHex.nonce === '') {
    try {
      provider ??= getEvmProvider(network, chain);
      const pendingNonce = await provider.getTransactionCount(txParamsForHex.from, 'pending');

      txParamsForHex = {
        ...txParamsForHex,
        nonce: `0x${pendingNonce.toString(16)}`,
      };
    } catch (err) {
      logDebugError('walletConnect:resolveWalletConnectEvmSerializedTx:nonce', err);
    }
  }

  if (!hasHexValue(txParamsForHex.gas) && !hasHexValue(txParamsForHex.gasLimit)) {
    try {
      provider ??= getEvmProvider(network, chain);

      const estimated = await provider.estimateGas({
        from: txParamsForHex.from,
        to: txParamsForHex.to && txParamsForHex.to.length > 0 ? txParamsForHex.to : undefined,
        value: parseOptionalHexBigInt(txParamsForHex.value) ?? 0n,
        data: txParamsForHex.data && txParamsForHex.data.length > 0 ? txParamsForHex.data : '0x',
      });

      txParamsForHex = {
        ...txParamsForHex,
        gas: bigintToHex((estimated * (100n + WALLET_CONNECT_EVM_GAS_LIMIT_BUMP_PERCENT)) / 100n),
      };
    } catch (err) {
      logDebugError('walletConnect:resolveWalletConnectEvmSerializedTx:gas', err);
    }
  }

  try {
    return evmTransactionParamsToUnsignedSerializedHex(txParamsForHex, caip2);
  } catch (err) {
    logDebugError('walletConnect:evmTransactionParamsToUnsignedSerializedHex', err);
    throw new Error('Invalid transaction fields');
  }
}

function parseOptionalHexBigInt(value: string | undefined): bigint | undefined {
  if (value === undefined || value === '') {
    return undefined;
  }

  return BigInt(value);
}

function bumpWalletConnectEvmFeePerGas(value: bigint): bigint {
  return (value * (100n + WALLET_CONNECT_EVM_FEE_BUMP_PERCENT) + 99n) / 100n;
}

function bumpOptionalHexFeePerGas(value: string | undefined): string | undefined {
  const parsed = parseOptionalHexBigInt(value);
  if (parsed === undefined) {
    return value;
  }

  return `0x${bumpWalletConnectEvmFeePerGas(parsed).toString(16)}`;
}

function bigintToHex(value: bigint): string {
  return `0x${value.toString(16)}`;
}

function hasHexValue(value: string | undefined): boolean {
  return value !== undefined && value !== '';
}

function fillWalletConnectEvmTransactionParamsFees(
  txParams: EvmTransactionParams,
  feeData: EvmFeeData,
): EvmTransactionParams {
  if (hasHexValue(txParams.gasPrice)) {
    return txParams;
  }

  const maxFeePerGas = feeData.maxFeePerGas ?? undefined;
  const maxPriorityFeePerGas = feeData.maxPriorityFeePerGas ?? undefined;
  const gasPrice = feeData.gasPrice ?? undefined;

  if (
    hasHexValue(txParams.maxFeePerGas)
    || hasHexValue(txParams.maxPriorityFeePerGas)
    || (maxFeePerGas !== undefined && maxPriorityFeePerGas !== undefined)
  ) {
    return {
      ...txParams,
      maxFeePerGas: hasHexValue(txParams.maxFeePerGas)
        ? txParams.maxFeePerGas
        : (maxFeePerGas !== undefined ? bigintToHex(maxFeePerGas) : undefined),
      maxPriorityFeePerGas: hasHexValue(txParams.maxPriorityFeePerGas)
        ? txParams.maxPriorityFeePerGas
        : (maxPriorityFeePerGas !== undefined ? bigintToHex(maxPriorityFeePerGas) : undefined),
    };
  }

  if (gasPrice !== undefined) {
    return {
      ...txParams,
      gasPrice: bigintToHex(gasPrice),
    };
  }

  return txParams;
}

function bumpWalletConnectEvmTransactionParamsFees(txParams: EvmTransactionParams): EvmTransactionParams {
  return {
    ...txParams,
    gasPrice: bumpOptionalHexFeePerGas(txParams.gasPrice),
    maxFeePerGas: bumpOptionalHexFeePerGas(txParams.maxFeePerGas),
    maxPriorityFeePerGas: bumpOptionalHexFeePerGas(txParams.maxPriorityFeePerGas),
  };
}

function fillWalletConnectEvmTransactionFees(tx: Transaction, feeData: EvmFeeData) {
  const currentGasPrice = tx.gasPrice ?? undefined;
  const currentMaxFeePerGas = tx.maxFeePerGas ?? undefined;
  const currentMaxPriorityFeePerGas = tx.maxPriorityFeePerGas ?? undefined;

  if (currentGasPrice !== undefined) {
    return;
  }

  const maxFeePerGas = feeData.maxFeePerGas ?? undefined;
  const maxPriorityFeePerGas = feeData.maxPriorityFeePerGas ?? undefined;

  if (currentMaxFeePerGas !== undefined || currentMaxPriorityFeePerGas !== undefined) {
    if (currentMaxFeePerGas === undefined && maxFeePerGas !== undefined) {
      tx.maxFeePerGas = maxFeePerGas;
    }

    if (currentMaxPriorityFeePerGas === undefined && maxPriorityFeePerGas !== undefined) {
      tx.maxPriorityFeePerGas = maxPriorityFeePerGas;
    }

    return;
  }

  if (maxFeePerGas !== undefined && maxPriorityFeePerGas !== undefined) {
    tx.maxFeePerGas = maxFeePerGas;
    tx.maxPriorityFeePerGas = maxPriorityFeePerGas;
    return;
  }

  const gasPrice = feeData.gasPrice ?? undefined;
  if (gasPrice !== undefined) {
    tx.gasPrice = gasPrice;
  }
}

function bumpWalletConnectEvmTransactionFees(tx: Transaction) {
  const gasPrice = tx.gasPrice ?? undefined;
  if (gasPrice !== undefined) {
    tx.gasPrice = bumpWalletConnectEvmFeePerGas(gasPrice);
  }

  const maxFeePerGas = tx.maxFeePerGas ?? undefined;
  if (maxFeePerGas !== undefined) {
    tx.maxFeePerGas = bumpWalletConnectEvmFeePerGas(maxFeePerGas);
  }

  const maxPriorityFeePerGas = tx.maxPriorityFeePerGas ?? undefined;
  if (maxPriorityFeePerGas !== undefined) {
    tx.maxPriorityFeePerGas = bumpWalletConnectEvmFeePerGas(maxPriorityFeePerGas);
  }
}

/** `TransactionLike.nonce` is `number` in ethers; JSON-RPC sends hex quantity strings. */
function parseOptionalNonce(value: string | undefined): number | undefined {
  const n = parseOptionalHexBigInt(value);

  if (n === undefined) {
    return undefined;
  }
  return Number(n);
}

function evmTransactionParamsToUnsignedSerializedHex(
  txParams: EvmTransactionParams,
  caip2ChainId: string,
): string {
  const chainId = BigInt(caip2ChainId.replace(/^eip155:/, ''));

  return Transaction.from({
    chainId,
    from: undefined, // tx is abstract and unsigned on serialization step
    to: txParams.to && txParams.to.length > 0 ? txParams.to : undefined,
    nonce: parseOptionalNonce(txParams.nonce),
    gasLimit: parseOptionalHexBigInt(txParams.gasLimit ?? txParams.gas),
    gasPrice: parseOptionalHexBigInt(txParams.gasPrice),
    maxFeePerGas: parseOptionalHexBigInt(txParams.maxFeePerGas),
    maxPriorityFeePerGas: parseOptionalHexBigInt(txParams.maxPriorityFeePerGas),
    value: parseOptionalHexBigInt(txParams.value) ?? 0n,
    data: txParams.data ?? '0x',
  }).unsignedSerialized;
}

function normalizeHexTxForEvm(raw: string): string {
  const trimmed = raw.trim();
  return trimmed.startsWith('0x') ? trimmed : `0x${trimmed}`;
}
