import { getAddress, Transaction } from 'ethers';

import type { ApiDappTransfer, ApiEmulationResult, ApiNetwork, EVMChain } from '../../types';
import type { AlchemyAssetChange, AlchemyAssetChangesResponse, EvmTokenOperation } from './types';
import { EVM_CHAIN_IDS } from '../../dappProtocols/adapters/walletConnect/types';

import { getChainConfig } from '../../../util/chain';
import { toDecimal } from '../../../util/decimals';
import { fetchJson } from '../../../util/fetch';
import { logDebugError } from '../../../util/logs';
import { getEvmProvider } from './util/client';
import { updateTokensMetadataByAddress } from './util/metadata';
import { updateActivityMetadata } from '../../common/helpers';
import { getTokenBySlug } from '../../common/tokens';
import { buildTokenSlug } from '../../methods';
import { EVM_RPC_URLS } from './constants';

function normalizeHexTx(rawTx: string): string {
  const trimmed = rawTx.trim();
  return trimmed.startsWith('0x') ? trimmed : `0x${trimmed}`;
}

function getFakeTransfer(chain: EVMChain, rawTx: string, isDangerous: boolean): ApiDappTransfer {
  return {
    chain,
    toAddress: '',
    amount: 0n,
    rawPayload: normalizeHexTx(rawTx),
    isDangerous,
    normalizedAddress: '',
    displayedToAddress: '',
    networkFee: 0n,
  };
}

function maxFeeFromSerializedTx(tx: Transaction): bigint {
  const { gasLimit } = tx;
  if (gasLimit === undefined || gasLimit === 0n) {
    return 0n;
  }
  const maxFeePerGas = tx.maxFeePerGas ?? undefined;
  if (maxFeePerGas !== undefined) {
    return gasLimit * maxFeePerGas;
  }
  const gasPrice = tx.gasPrice ?? undefined;
  if (gasPrice !== undefined) {
    return gasLimit * gasPrice;
  }
  return 0n;
}

async function estimateNetworkFee(
  chain: EVMChain,
  network: ApiNetwork,
  tx: Transaction,
  accountAddress: string,
): Promise<bigint> {
  const fromSerialized = maxFeeFromSerializedTx(tx);
  if (fromSerialized > 0n) {
    return fromSerialized;
  }

  try {
    const provider = getEvmProvider(network, chain);
    const from = resolveFromAddress(tx, accountAddress);
    const gasLimit = await provider.estimateGas({
      from,
      to: tx.to ?? undefined,
      data: tx.data ?? undefined,
      value: tx.value ?? 0n,
    });
    const feeData = await provider.getFeeData();
    const gasPrice = tx.type === 2
      ? (feeData.maxFeePerGas ?? 0n)
      : (feeData.gasPrice ?? 0n);
    return gasLimit * gasPrice;
  } catch {
    return 0n;
  }
}

function isWrongChain(tx: Transaction, chain: EVMChain, network: ApiNetwork): boolean {
  const chainId = tx.chainId ? `eip155:${tx.chainId.toString()}` : undefined;

  if (!chainId) {
    return false;
  }

  const expected = EVM_CHAIN_IDS[chainId];

  return chain !== expected.chain || network !== expected.network;
}

function isWrongSigner(tx: Transaction, accountAddress: string): boolean {
  const from = tx.from ?? undefined;
  if (from === undefined) {
    return false;
  }
  try {
    return getAddress(from) !== getAddress(accountAddress);
  } catch {
    return true;
  }
}

function resolveFromAddress(tx: Transaction, accountAddress: string): string {
  const raw = tx.from ?? undefined;
  if (raw === undefined) {
    return getAddress(accountAddress);
  }
  return getAddress(raw);
}

function isPlainNativeTransfer(tx: Transaction): boolean {
  return Boolean(tx.to && (!tx.data || tx.data === '0x'));
}

export async function parseTransactionForPreview(
  chain: EVMChain,
  rawTx: string,
  address: string,
  network: ApiNetwork,
): Promise<{ transfers: ApiDappTransfer[]; emulation: ApiEmulationResult | undefined }> {
  let tx: Transaction;

  try {
    tx = Transaction.from(normalizeHexTx(rawTx));
  } catch {
    return {
      transfers: [getFakeTransfer(chain, rawTx, true)],
      emulation: undefined,
    };
  }

  const nativeSlug = getChainConfig(chain).nativeToken.slug;
  const wrongSigner = isWrongSigner(tx, address);
  const wrongChain = isWrongChain(tx, chain, network);
  const isDangerousMeta = wrongSigner || wrongChain || !tx.to;

  let emulation: ApiEmulationResult | undefined = undefined;
  const transfers: ApiDappTransfer[] = [];

  const networkFee = await estimateNetworkFee(chain, network, tx, address);
  const fromAddr = resolveFromAddress(tx, address);
  const feeForActivity = networkFee > 0n ? networkFee : maxFeeFromSerializedTx(tx);

  if (!isDangerousMeta && isPlainNativeTransfer(tx)) {
    const toAddr = getAddress(tx.to!);
    const amount = tx.value ?? 0n;

    transfers.push(getFakeTransfer(chain, rawTx, false));

    emulation = {
      networkFee,
      received: 0n,
      traceOutputs: [],
      activities: [updateActivityMetadata({
        id: '',
        kind: 'transaction',
        timestamp: 0,
        comment: undefined,
        fromAddress: fromAddr,
        toAddress: toAddr,
        amount,
        slug: nativeSlug,
        isIncoming: false,
        normalizedAddress: toAddr,
        fee: feeForActivity,
        status: 'completed',
      })],
      realFee: feeForActivity,
    };

    return { transfers, emulation };
  }

  try {
    const emulated = await emulateTransaction(chain, network, address, tx);

    const tokenOperation = await parseTokenOperation(network, chain, emulated, address);

    if (tokenOperation?.assets) {
      transfers.push(getFakeTransfer(chain, rawTx, false));

      if (tokenOperation?.isSwap) {
        const { swap } = tokenOperation;

        emulation = {
          networkFee,
          received: 0n,
          traceOutputs: [],
          activities: [updateActivityMetadata({
            id: '',
            kind: 'swap',
            fromAddress: address,
            timestamp: 0,
            from: swap.from,
            fromAmount: swap.fromAmount,
            to: swap.to,
            toAmount: swap.toAmount,
            networkFee: swap.networkFee,
            swapFee: '0',
            status: 'completed',
            hashes: [],
          })],
          realFee: feeForActivity,
        };
      } else {
        const { transfer } = tokenOperation;

        emulation = {
          networkFee,
          received: 0n,
          traceOutputs: [],
          // We need to pass TON-like structure, but it's not actual emulation,
          // so we don't have all the fields, but have essential
          activities: [updateActivityMetadata({
            id: '',
            kind: 'transaction',
            timestamp: 0,
            comment: undefined,
            fromAddress: fromAddr,
            toAddress: transfer.toAddress,
            amount: transfer.amount,
            slug: transfer.slug,
            isIncoming: false,
            normalizedAddress: transfer.toAddress,
            fee: transfer.fee,
            status: 'completed',
          })],
          realFee: transfer.fee,
        };
      }
    }
  } catch (error) {
    logDebugError(`parseTransactionForPreview:${chain} Failed to emulate transaction`, error);
  }

  if (!transfers.length) {
    transfers.push(getFakeTransfer(chain, rawTx, true));
  }

  return { transfers, emulation };
}

async function emulateTransaction(
  chain: EVMChain,
  network: ApiNetwork,
  address: string,
  tx: Transaction,
) {
  const payload = {
    method: 'POST',
    body: JSON.stringify({
      jsonrpc: '2.0',
      id: 1,
      method: 'alchemy_simulateAssetChanges',
      params: [
        {
          from: address,
          to: tx.to,
          data: tx.data,
          gas: '0x' + tx.gasLimit.toString(16),
          gasPrice: '0x' + (tx.gasPrice?.toString(16) ?? '0'),
          value: '0x' + (tx.value?.toString(16) ?? '0'),
        },
      ],
    }),
    headers: {
      'Content-Type': 'application/json',
    },
  };

  const response = await fetchJson<AlchemyAssetChangesResponse>(
    `${EVM_RPC_URLS[network](chain)}/v2`,
    undefined,
    payload,
  );

  return response.result;
}

export async function parseTokenOperation(
  network: ApiNetwork,
  chain: EVMChain,
  tx: AlchemyAssetChange,
  userAddress: string,
): Promise<EvmTokenOperation | undefined> {
  const changes = new Map<string, bigint>();
  const assets: string[] = [];

  const nativeSlug = getChainConfig(chain).nativeToken.slug;

  tx.changes.forEach((change) => {
    if (!['NATIVE', 'ERC20'].includes(change.assetType)) {
      return;
    }

    assets.push(change.contractAddress || nativeSlug);

    const isIncoming = getAddress(change.to) === userAddress;
    const isOutgoing = getAddress(change.from) === userAddress;

    if (isIncoming) {
      const current = changes.get(change.contractAddress || nativeSlug) || 0n;
      changes.set(change.contractAddress || nativeSlug, current + BigInt(change.rawAmount));
    }
    if (isOutgoing) {
      const current = changes.get(change.contractAddress || nativeSlug) || 0n;
      changes.set(change.contractAddress || nativeSlug, current - BigInt(change.rawAmount));
    }
  });

  const sent = new Map<string, bigint>();
  const received = new Map<string, bigint>();

  changes.forEach((change, mint) => {
    if (change < 0n) {
      sent.set(mint, change < 0n ? -change : change);
    }

    if (change > 0n) {
      received.set(mint, change);
    }
  });

  const isSentOnly = !received.size && sent.size;

  const isReceivedOnly = !sent.size && received.size;

  if (isSentOnly || isReceivedOnly) {
    const asset = isSentOnly ? [...sent][0][0] : [...received][0][0];

    let slug = '';
    if (asset === nativeSlug) {
      slug = nativeSlug;
    } else {
      slug = buildTokenSlug(chain, asset);
    }

    // if no from/to address - consider to be mint or burn(?) - use transaction initiator as fallback
    const fromAddress = isSentOnly
      ? userAddress
      : tx.changes.find((e) => e.from !== userAddress)?.from || tx.changes[0].from;

    const toAddress = !isSentOnly
      ? userAddress
      : tx.changes.find((e) => e.to !== userAddress)?.to || tx.changes[0].to;

    const amount = isSentOnly ? sent.get(asset) || 0n : received.get(asset) || 0n;

    const isIncoming = toAddress === userAddress;

    return {
      assets,
      isSwap: false,
      transfer: {
        amount: isIncoming ? amount : -amount,
        fromAddress,
        toAddress,
        slug,
        isIncoming,
        normalizedAddress: isIncoming ? fromAddress : toAddress,
        fee: BigInt(tx.gasUsed),
      },
    };
  }

  const firstSentAsset = [...sent]?.[0]?.[0] || '';
  const firstReceivedAsset = [...received]?.[0]?.[0] || '';

  if (!firstSentAsset && !firstReceivedAsset) {
    return;
  }

  await updateTokensMetadataByAddress(
    network,
    chain,
    [firstSentAsset, firstReceivedAsset].filter((e) => e && e !== nativeSlug),
  );

  const assetTo = firstReceivedAsset === nativeSlug
    ? getChainConfig(chain).nativeToken
    : getTokenBySlug(buildTokenSlug(chain, firstReceivedAsset));

  const assetFrom = firstSentAsset === nativeSlug
    ? getChainConfig(chain).nativeToken
    : getTokenBySlug(buildTokenSlug(chain, firstSentAsset));

  return {
    assets,
    isSwap: true,
    swap: {
      fromAddress: userAddress,
      from: assetFrom?.slug || '',
      fromAmount: toDecimal(sent.get([...sent][0][0])!, assetFrom?.decimals || 18),
      to: assetTo?.slug || '',
      toAmount: toDecimal(received.get([...received][0][0])!, assetTo?.decimals || 18),
      networkFee: BigInt(tx.gasUsed).toString(10),
      swapFee: '0',
    },
  };
}
