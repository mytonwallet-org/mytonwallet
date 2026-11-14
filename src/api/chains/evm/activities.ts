import type {
  ApiActivity,
  ApiFetchActivitySliceOptions,
  ApiNetwork,
  ApiTransactionType,
  EVMChain,
} from '../../types';
import type { ZerionNftTransfer, ZerionTokenTransfer, ZerionTransaction, ZerionTransactionsResponse } from './types';

import { ARBITRUM_USDC_MAINNET, IS_PERPS_ENABLED } from '../../../config';
import { throwIfAborted } from '../../../util/abortSignal';
import { parseAccountId } from '../../../util/account';
import { findChainConfig, getChainConfig, getIsSupportedChain } from '../../../util/chain';
import { toDecimal } from '../../../util/decimals';
import { fetchJson, isNegativeCacheableStatus } from '../../../util/fetch';
import { compact } from '../../../util/iteratees';
import { logDebugError } from '../../../util/logs';
import { normalizeNftAddress } from '../../../util/nft';
import { getChainBySlug } from '../../../util/tokens';
import { fetchEvmWallet } from './util/account';
import { isUnlimitedEvmAllowance } from './util/allowance';
import { collectZerionApprovals } from './util/approvals';
import { getEvmProvider } from './util/client';
import { updateTokensMetadataByAddress } from './util/metadata';
import { collectZerionTxTokenAddresses, getZerionFungibleTokenSlug } from './util/tokens';
import { untrackableRegistry } from './util/untrackable';
import { getIsNegVerdictCacheEnabled } from '../../common/cache';
import { updateActivityMetadata } from '../../common/helpers';
import {
  PERPS_CCTP_DEPOSIT_CHAIN,
  PERPS_CCTP_EXTENSION_ADDRESS,
  PERPS_CCTP_FORWARD_FEE_USDC_BASE_UNITS,
  PERPS_HYPERCORE_BRIDGE_RELAYER,
} from '../../common/perps';
import { getTokenBySlug } from '../../common/tokens';
import { SEC } from '../../constants';
import { ApiServerError } from '../../errors';
import { PIMLICO_SINGLETON_PAYMASTER_ADDRESS } from './smartAccount/constants';
import { normalizeAddress } from './address';
import { getApiChainByZerionChain, getEvmApiUrl, getZerionChainByApiChain } from './constants';

export async function fetchActivitySlice(
  chain: EVMChain,
  {
    accountId,
    tokenSlug,
    toTimestamp,
    fromTimestamp,
    limit,
    signal,
  }: ApiFetchActivitySliceOptions,
): Promise<ApiActivity[]> {
  const { network } = parseAccountId(accountId);
  const { address } = await fetchEvmWallet(accountId, chain);

  const { activities } = await getTokenActivitySlice(
    chain,
    network,
    address,
    tokenSlug,
    toTimestamp,
    fromTimestamp,
    limit,
    undefined,
    signal,
  );

  return activities;
}

export async function getTokenActivitySlice(
  chain: EVMChain,
  network: ApiNetwork,
  address: string,
  slug?: string,
  toTimestamp?: number,
  fromTimestamp?: number,
  limit?: number,
  isCrossChain?: boolean,
  signal?: AbortSignal,
): Promise<{ activities: ApiActivity[]; hasMore: boolean }> {
  const checksumAddress = normalizeAddress(address);

  const txs = await fetchEvmTxs({
    chain,
    network,
    address: checksumAddress,
    slug,
    toTimestamp,
    fromTimestamp,
    limit,
    isCrossChain,
    signal,
  });

  // hasMore is computed from the raw API response length, not the post-transform `activities`.
  // `transformEvmTxToUnified` returns undefined for unsupported tx shapes, and `compact` drops
  // those - so a length check on the returned activities would underreport remaining pages.
  const hasMore = limit !== undefined && txs.length >= limit;

  if (isCrossChain) {
    await collectCrossChainTokensFromTransactions(network, address, txs, signal);

    const activities = compact(txs.map((tx) => {
      const txChain = getZerionTransactionChain(tx);

      return txChain ? transformEvmTxToUnified(txChain, tx, address) : undefined;
    }));

    return { activities, hasMore };
  }

  await collectTokensFromTransactions(network, chain, address, txs, signal);

  const activities = compact(txs.map((tx) => transformEvmTxToUnified(chain, tx, address)));

  return { activities, hasMore };
}

export async function fetchEvmTxs(options: {
  chain: EVMChain;
  network: ApiNetwork;
  address: string;
  slug?: string;
  toTimestamp?: number;
  fromTimestamp?: number;
  limit?: number;
  isCrossChain?: boolean;
  hash?: string;
  signal?: AbortSignal;
}) {
  const {
    chain, network, address, slug, toTimestamp, fromTimestamp, limit, isCrossChain, hash, signal,
  } = options;

  const isUntrackableGuarded = !signal && getIsNegVerdictCacheEnabled();
  if (isUntrackableGuarded && untrackableRegistry.has(network, address)) {
    // Zerion already told us this address is untrackable; skip the round-trip and return an
    // empty, terminal result so the activity state machine converges (history end reached).
    return [];
  }

  const tokenAddress = slug
    ? (slug === getChainConfig(chain).nativeToken.slug || slug === 'eth')
      ? undefined
      : getTokenBySlug(slug)?.tokenAddress
    : undefined;
  const zerionChain = getZerionChainByApiChain(chain);

  const params = {
    'filter[min_mined_at]': fromTimestamp ? fromTimestamp + SEC : undefined,
    'filter[max_mined_at]': toTimestamp ? toTimestamp - SEC : undefined,
    'page[size]': limit,
    'filter[chain_ids]': isCrossChain ? undefined : zerionChain,
    'filter[fungible_implementations]': tokenAddress ? `${zerionChain}:${tokenAddress.toLowerCase()}` : undefined,
    'filter[search_query]': hash,
  };

  try {
    const data = await fetchJson<ZerionTransactionsResponse>(
      `${getEvmApiUrl(network)}/v1/wallets/${address}/transactions/`,
      params,
      { signal },
    );

    return data.data;
  } catch (err) {
    throwIfAborted(signal);
    // Only a plain address-scoped history request (no hash, no token filter) proves the ADDRESS
    // itself is untrackable. A 4xx on a hash- or token-scoped request can be caused by those
    // params rather than the address, so marking here would wrongly freeze a real wallet - e.g.
    // fetchEvmTx() below fetches a user's own outgoing tx by hash with address = the user's own
    // address, and a 400 there must not blank that user's history and balances.
    const isAddressScopedHistory = !hash && !slug;
    if (
      isUntrackableGuarded && isAddressScopedHistory
      && err instanceof ApiServerError && isNegativeCacheableStatus(err.statusCode)
    ) {
      untrackableRegistry.mark(network, address);
      logDebugError('fetchEvmTxs: wallet is untrackable on Zerion', { address, chain, status: err.statusCode });
      return [];
    }

    throw err;
  }
}

export async function fetchEvmTx(
  chain: EVMChain,
  network: ApiNetwork,
  hash: string,
): Promise<ZerionTransaction | undefined> {
  // We nned to get unparsed tx from node first
  const transfer = await getEvmProvider(network, chain).getTransaction(hash);

  if (!transfer) {
    return undefined;
  }

  // Then get it parsed by participant address & hash from Zerion
  const tx = await fetchEvmTxs({ chain, network, hash, address: transfer.from });

  if (!tx.length) {
    return undefined;
  }

  return tx[0];
}

export async function collectTokensFromTransactions(
  network: ApiNetwork,
  chain: EVMChain,
  address: string,
  rawTxs: ZerionTransaction[],
  signal?: AbortSignal,
) {
  const addresses = new Set<string>();
  const zerionChain = getZerionChainByApiChain(chain);

  for (const tx of rawTxs) {
    collectZerionTxTokenAddresses(tx, zerionChain, addresses);
  }

  await updateTokensMetadataByAddress(network, chain, [...addresses], signal);
}

async function collectCrossChainTokensFromTransactions(
  network: ApiNetwork,
  address: string,
  rawTxs: ZerionTransaction[],
  signal?: AbortSignal,
) {
  const txsByChain = new Map<EVMChain, ZerionTransaction[]>();

  for (const tx of rawTxs) {
    const chain = getZerionTransactionChain(tx);

    if (!chain) {
      continue;
    }

    const chainTxs = txsByChain.get(chain) ?? [];
    chainTxs.push(tx);
    txsByChain.set(chain, chainTxs);
  }

  await Promise.all(
    [...txsByChain.entries()].map(([chain, txs]) => (
      collectTokensFromTransactions(network, chain, address, txs, signal)
    )),
  );
}

function getZerionTransactionChain(tx: ZerionTransaction) {
  const chain = getApiChainByZerionChain(tx.relationships.chain.data.id);

  if (!getIsSupportedChain(chain) || getChainConfig(chain).chainStandard !== 'ethereum') {
    logDebugError('getZerionTransactionChain', 'Unsupported chain', { chain });

    return undefined;
  }

  return chain;
}

export async function fetchCrossChainActivitySlice(options: ApiFetchActivitySliceOptions): Promise<ApiActivity[]> {
  const {
    accountId, tokenSlug, toTimestamp, fromTimestamp, limit, signal,
  } = options;

  const { network } = parseAccountId(accountId);
  const { address } = await fetchEvmWallet(accountId, 'ethereum');

  const { activities } = await getTokenActivitySlice(
    'ethereum', network, address, tokenSlug, toTimestamp, fromTimestamp, limit, true, signal,
  );

  return activities;
}

function transformUnknownTx(
  chain: EVMChain,
  tx: ZerionTransaction,
  address: string,
): ApiActivity {
  return updateActivityMetadata({
    id: tx.attributes.hash,
    kind: 'transaction',
    timestamp: new Date(tx.attributes.mined_at).getTime(),
    comment: undefined,
    fromAddress: normalizeAddress(tx.attributes.sent_from),
    toAddress: normalizeAddress(tx.attributes.sent_to),
    amount: 0n,
    slug: getChainConfig(chain).nativeToken.slug,
    isIncoming: tx.attributes.sent_from !== address,
    normalizedAddress: normalizeAddress(address),
    fee: BigInt(tx.attributes.fee.quantity.int),
    type: 'callContract',
    shouldHide: false,
    status: 'completed',
    externalMsgHashNorm: tx.attributes.hash,
    isScam: tx.attributes.flags.is_trash,
  });
}

/**
 * An allowance grant or revoke, read from the same Zerion approvals the wallet permissions are built
 * from. Zerion marks these transactions `approve` and `revoke`; both carry the resulting allowance,
 * so a revoke is the same activity with a zero amount.
 */
function transformEvmApproval(
  chain: EVMChain,
  tx: ZerionTransaction,
  address: string,
): ApiActivity | undefined {
  const zerionChain = getZerionChainByApiChain(chain);
  const [approval] = collectZerionApprovals(tx, zerionChain);
  if (approval?.amount === undefined) {
    return undefined;
  }

  const slug = getZerionFungibleTokenSlug(chain, zerionChain, approval.fungibleInfo);

  if (!slug) {
    return undefined;
  }

  return updateActivityMetadata({
    id: tx.attributes.hash,
    kind: 'transaction',
    timestamp: new Date(tx.attributes.mined_at).getTime(),
    comment: undefined,
    fromAddress: normalizeAddress(tx.attributes.sent_from),
    toAddress: approval.spenderAddress,
    // The allowance the transaction sets, not a transfer, so it keeps its sign in both directions
    amount: approval.amount,
    slug,
    isIncoming: normalizeAddress(tx.attributes.sent_from) !== address,
    normalizedAddress: normalizeAddress(address),
    fee: BigInt(tx.attributes.fee.quantity.int),
    type: 'approval',
    isApprovalUnlimited: isUnlimitedEvmAllowance(approval.amount),
    status: 'completed',
    isScam: tx.attributes.flags.is_trash,
  });
}

function transformEvmSwap(
  chain: EVMChain,
  tx: ZerionTransaction,
  address: string,
): ApiActivity {
  const nativeToken = getChainConfig(chain).nativeToken;
  const zerionChain = getZerionChainByApiChain(chain);

  const feeActId = findPimlicoFeeAct(tx)?.id;
  const isFeeLeg = (actId?: string) => feeActId !== undefined && actId === feeActId;
  const inAsset = tx.attributes.transfers.find((e) =>
    e.direction === 'in'
    && 'fungible_info' in e
    && !isFeeLeg(e.act_id)
    && normalizeAddress(e.recipient) === address,
  ) as ZerionTokenTransfer
  || undefined;

  const outAsset = tx.attributes.transfers.find((e) =>
    e.direction === 'out'
    && 'fungible_info' in e
    && !isFeeLeg(e.act_id)
    && normalizeAddress(e.sender) === address,
  ) as ZerionTokenTransfer
  || undefined;

  if (!inAsset || !outAsset) {
    return transformUnknownTx(chain, tx, address);
  }

  const inTokenSlug = getZerionFungibleTokenSlug(chain, zerionChain, inAsset.fungible_info);
  const outTokenSlug = getZerionFungibleTokenSlug(chain, zerionChain, outAsset.fungible_info);

  const inToken = inTokenSlug === nativeToken.slug
    ? nativeToken
    : inTokenSlug ? getTokenBySlug(inTokenSlug) : undefined;

  const outToken = outTokenSlug === nativeToken.slug
    ? nativeToken
    : outTokenSlug ? getTokenBySlug(outTokenSlug) : undefined;

  if (!inToken || !outToken) {
    return transformUnknownTx(chain, tx, address);
  }

  return updateActivityMetadata({
    id: tx.attributes.hash,
    kind: 'swap',
    comment: undefined,
    fromAddress: normalizeAddress(address),
    timestamp: new Date(tx.attributes.mined_at).getTime(),
    from: outToken.slug,
    fromAmount: toDecimal(BigInt(outAsset.quantity.int || 0), outToken.decimals),
    to: inToken.slug,
    toAmount: toDecimal(BigInt(inAsset.quantity.int || 0), inToken.decimals),
    networkFee: toDecimal(BigInt(tx.attributes.fee.quantity.int), nativeToken.decimals),
    swapFee: '0',
    status: 'completed',
    hashes: [],
    transactionIds: {},
    externalMsgHashNorm: tx.attributes.hash,
    isScam: tx.attributes.flags.is_trash,
  });
}

function transformEvmTransfer(
  chain: EVMChain,
  tx: ZerionTransaction,
  transfer: ZerionTokenTransfer,
  address: string,
): ApiActivity {
  const slug = getZerionFungibleTokenSlug(chain, getZerionChainByApiChain(chain), transfer.fungible_info);
  if (!slug) {
    return transformUnknownTx(chain, tx, address);
  }

  const isIncoming = transfer.direction === 'in';

  return updateActivityMetadata({
    id: tx.attributes.hash,
    kind: 'transaction',
    timestamp: new Date(tx.attributes.mined_at).getTime(),
    comment: undefined,
    fromAddress: normalizeAddress(transfer.sender),
    toAddress: normalizeAddress(transfer.recipient),
    amount: isIncoming ? BigInt(transfer.quantity.int) : -BigInt(transfer.quantity.int),
    slug,
    isIncoming,
    normalizedAddress: normalizeAddress(address),
    fee: BigInt(tx.attributes.fee.quantity.int),
    status: 'completed',
    isScam: tx.attributes.flags.is_trash,
  });
}

function transformEvmTokenMint(
  chain: EVMChain,
  tx: ZerionTransaction,
  address: string,
): ApiActivity | undefined {
  const mintAct = tx.attributes.acts?.find((act) => act.type === 'mint');
  if (tx.attributes.operation_type !== 'mint' && !mintAct) {
    return undefined;
  }

  const fungibleTransfers = tx.attributes.transfers.filter((transfer): transfer is ZerionTokenTransfer => (
    'fungible_info' in transfer
  ));

  const mintedByAct = mintAct
    ? fungibleTransfers.find((transfer) => (
      transfer.act_id === mintAct.id
      && transfer.direction === 'in'
      && normalizeAddress(transfer.recipient) === address
    ))
    : undefined;

  const mintedTransfer = mintedByAct ?? (
    tx.attributes.operation_type === 'mint'
      ? fungibleTransfers.find((transfer) => (
        transfer.direction === 'in' && normalizeAddress(transfer.recipient) === address
      ))
      : undefined
  );

  if (!mintedTransfer) {
    return undefined;
  }

  const slug = getZerionFungibleTokenSlug(
    chain,
    getZerionChainByApiChain(chain),
    mintedTransfer.fungible_info,
  );
  if (!slug) {
    return undefined;
  }

  const type = getEvmMintTransactionType(slug);
  const relayerAddress = normalizeAddress(PERPS_HYPERCORE_BRIDGE_RELAYER);

  return updateActivityMetadata({
    id: tx.attributes.hash,
    kind: 'transaction',
    timestamp: new Date(tx.attributes.mined_at).getTime(),
    comment: undefined,
    fromAddress: normalizeAddress(tx.attributes.sent_from),
    toAddress: normalizeAddress(mintedTransfer.recipient),
    amount: BigInt(mintedTransfer.quantity.int),
    slug,
    isIncoming: true,
    normalizedAddress: type === 'perps_withdraw' ? relayerAddress : normalizeAddress(address),
    fee: BigInt(tx.attributes.fee.quantity.int),
    type,
    status: 'completed',
    isScam: tx.attributes.flags.is_trash,
  });
}

// TODO: make moere reliable detection of perps withdraws
function getEvmMintTransactionType(slug: string): ApiTransactionType {
  if (IS_PERPS_ENABLED && slug === ARBITRUM_USDC_MAINNET.slug) {
    return 'perps_withdraw';
  }

  return 'mint';
}

/**
 * CCTP deposit into HyperCore: outgoing Arbitrum USDC to the extension contract. Gross USDC out
 * includes a fixed bridge fee; the activity amount is the credited deposit (gross − fee).
 */
function transformEvmPerpsDeposit(
  chain: EVMChain,
  tx: ZerionTransaction,
  address: string,
): ApiActivity | undefined {
  if (chain !== PERPS_CCTP_DEPOSIT_CHAIN) {
    return undefined;
  }

  const zerionChain = getZerionChainByApiChain(chain);
  const bridgeAddress = normalizeAddress(PERPS_CCTP_EXTENSION_ADDRESS);
  let grossUsdcOut = 0n;

  for (const transfer of tx.attributes.transfers) {
    if (!('fungible_info' in transfer)) {
      continue;
    }

    if (
      transfer.direction !== 'out'
      || normalizeAddress(transfer.sender) !== address
      || normalizeAddress(transfer.recipient) !== bridgeAddress
    ) {
      continue;
    }

    const slug = getZerionFungibleTokenSlug(chain, zerionChain, transfer.fungible_info);
    if (slug !== ARBITRUM_USDC_MAINNET.slug) {
      continue;
    }

    grossUsdcOut += BigInt(transfer.quantity.int);
  }

  if (grossUsdcOut <= PERPS_CCTP_FORWARD_FEE_USDC_BASE_UNITS) {
    return undefined;
  }

  const depositAmount = grossUsdcOut - PERPS_CCTP_FORWARD_FEE_USDC_BASE_UNITS;

  return updateActivityMetadata({
    id: tx.attributes.hash,
    kind: 'transaction',
    timestamp: new Date(tx.attributes.mined_at).getTime(),
    comment: undefined,
    fromAddress: normalizeAddress(address),
    toAddress: bridgeAddress,
    amount: -depositAmount,
    slug: ARBITRUM_USDC_MAINNET.slug,
    isIncoming: false,
    normalizedAddress: bridgeAddress,
    fee: BigInt(tx.attributes.fee.quantity.int),
    type: 'perps_deposit',
    status: 'completed',
    isScam: tx.attributes.flags.is_trash,
  });
}

/** The paymaster's send act. Its transfer is the token fee of a gasless operation. */
function findPimlicoFeeAct(tx: ZerionTransaction) {
  const paymaster = tx.attributes.paymaster;

  if (!paymaster || normalizeAddress(paymaster) !== normalizeAddress(PIMLICO_SINGLETON_PAYMASTER_ADDRESS)) {
    return undefined;
  }

  const paymasterAddress = normalizeAddress(paymaster);

  return (tx.attributes.acts ?? []).find((act) => (
    act.type === 'send' && act.sent_from !== undefined && normalizeAddress(act.sent_from) === paymasterAddress
  ));
}

/**
 * A swap Zerion already parsed, with the paymaster send written as the token fee.
 * The swap itself stays the trade. Only the fee changes.
 */
function transformEvmGaslessSwap(
  chain: EVMChain,
  tx: ZerionTransaction,
  address: string,
  activity: ApiActivity,
): ApiActivity | undefined {
  if (activity.kind !== 'swap') {
    return undefined;
  }

  const feeAct = findPimlicoFeeAct(tx);
  if (!feeAct) {
    return undefined;
  }

  const feeTransfer = tx.attributes.transfers.find((transfer): transfer is ZerionTokenTransfer => (
    'fungible_info' in transfer && transfer.act_id === feeAct.id
  ));

  if (!feeTransfer || normalizeAddress(feeTransfer.sender) !== address) {
    return undefined;
  }

  const zerionChain = getZerionChainByApiChain(chain);
  const feeSlug = getZerionFungibleTokenSlug(chain, zerionChain, feeTransfer.fungible_info);
  const nativeToken = getChainConfig(chain).nativeToken;
  const feeToken = feeSlug === nativeToken.slug ? nativeToken : feeSlug ? getTokenBySlug(feeSlug) : undefined;

  if (!feeToken || feeToken.slug !== activity.from) {
    return undefined;
  }

  return {
    ...activity,
    networkFee: toDecimal(BigInt(feeTransfer.quantity.int), feeToken.decimals),
    extra: { ...activity.extra, isGasless: true },
  };
}

/**
 * A Pimlico gasless transfer. The wallet's send act is the transfer, and the paymaster's send act is the token fee.
 */
function transformEvmGaslessTransfer(
  chain: EVMChain,
  tx: ZerionTransaction,
  address: string,
): ApiActivity | undefined {
  const paymaster = tx.attributes.paymaster;

  if (!paymaster || normalizeAddress(paymaster) !== normalizeAddress(PIMLICO_SINGLETON_PAYMASTER_ADDRESS)) {
    return undefined;
  }

  const paymasterAddress = normalizeAddress(paymaster);

  const sendActs = (tx.attributes.acts ?? []).flatMap((act) => (
    act.type === 'send' && act.sent_from ? [{ id: act.id, sentFrom: normalizeAddress(act.sent_from) }] : []
  ));

  const feeAct = sendActs.find((act) => act.sentFrom === paymasterAddress);
  const valueActs = sendActs.filter((act) => act.sentFrom !== paymasterAddress);

  if (!feeAct || valueActs.length !== 1) {
    return undefined;
  }

  const [valueAct] = valueActs;

  const fungibleTransfers = tx.attributes.transfers.filter((transfer): transfer is ZerionTokenTransfer => (
    'fungible_info' in transfer
  ));

  const transfer = fungibleTransfers.find((item) => item.act_id === valueAct.id);
  const feeTransfer = fungibleTransfers.find((item) => item.act_id === feeAct.id);

  if (!transfer || !feeTransfer) {
    return undefined;
  }

  const zerionChain = getZerionChainByApiChain(chain);
  const slug = getZerionFungibleTokenSlug(chain, zerionChain, transfer.fungible_info);
  const feeSlug = getZerionFungibleTokenSlug(chain, zerionChain, feeTransfer.fungible_info);

  if (!slug || slug !== feeSlug) {
    return undefined;
  }

  const isIncoming = transfer.direction === 'in';
  const isWalletParty = isIncoming
    ? normalizeAddress(transfer.recipient) === address
    : normalizeAddress(transfer.sender) === address;

  if (!isWalletParty) {
    return undefined;
  }

  const hasPaidFee = normalizeAddress(feeTransfer.sender) === address;

  return updateActivityMetadata({
    id: tx.attributes.hash,
    kind: 'transaction',
    timestamp: new Date(tx.attributes.mined_at).getTime(),
    comment: undefined,
    fromAddress: normalizeAddress(transfer.sender),
    toAddress: normalizeAddress(transfer.recipient),
    amount: isIncoming ? BigInt(transfer.quantity.int) : -BigInt(transfer.quantity.int),
    slug,
    isIncoming,
    normalizedAddress: normalizeAddress(address),
    fee: hasPaidFee ? BigInt(feeTransfer.quantity.int) : 0n,
    status: 'completed',
    isScam: tx.attributes.flags.is_trash,
    ...(hasPaidFee && { extra: { isGasless: true } }),
  });
}

function transformEvmNftTransfer(
  chain: EVMChain,
  transfer: ZerionNftTransfer,
  tx: ZerionTransaction,
  address: string,
): ApiActivity {
  const { nft_info: nftInfo } = transfer;

  return updateActivityMetadata({
    id: tx.attributes.hash,
    kind: 'transaction',
    timestamp: new Date(tx.attributes.mined_at).getTime(),
    comment: undefined,
    fromAddress: normalizeAddress(transfer.sender),
    toAddress: normalizeAddress(transfer.recipient),
    amount: 0n,
    slug: getChainConfig(chain).nativeToken.slug,
    isIncoming: transfer.direction === 'in',
    normalizedAddress: normalizeAddress(address),
    fee: BigInt(tx.attributes.fee.quantity.int),
    status: 'completed',
    nft: {
      chain,
      index: 0,
      address: normalizeNftAddress(`${nftInfo.contract_address}/${nftInfo.token_id}`),
      image: nftInfo.content?.preview?.url || '',
      thumbnail: nftInfo.content?.preview?.url || '',
      name: nftInfo.name,
      description: '',
      isOnSale: false,
      isHidden: nftInfo.flags?.is_spam === true,
      spamInfo: {
        provider: 'zerion',
        isSpam: nftInfo.flags?.is_spam ?? undefined,
      },
      metadata: {
        attributes: [],
      },
      interface: nftInfo.interface,
    },
    isScam: tx.attributes.flags.is_trash,
  });
}

export function transformEvmTxToUnified(
  chain: EVMChain,
  tx: ZerionTransaction,
  address: string,
): ApiActivity {
  address = normalizeAddress(address);

  const tokenMint = transformEvmTokenMint(chain, tx, address);
  if (tokenMint) {
    return tokenMint;
  }

  const perpsDeposit = IS_PERPS_ENABLED ? transformEvmPerpsDeposit(chain, tx, address) : undefined;
  if (perpsDeposit) {
    return perpsDeposit;
  }

  const gaslessTransfer = transformEvmGaslessTransfer(chain, tx, address);
  if (gaslessTransfer) {
    return gaslessTransfer;
  }

  if (tx.attributes.transfers.length > 1) {
    try {
      const swap = transformEvmSwap(chain, tx, address);

      return transformEvmGaslessSwap(chain, tx, address, swap) ?? swap;
    } catch (error) {
      // Fallback
    }
  }

  const transfer = tx.attributes.transfers.find((e) =>
    e.direction === 'in'
      ? normalizeAddress(e.recipient) === address
      : normalizeAddress(e.sender) === address,
  );

  if (!transfer) {
    return transformEvmApproval(chain, tx, address) ?? transformUnknownTx(chain, tx, address);
  }

  const isNftTransfer = 'nft_info' in transfer;

  if (isNftTransfer) {
    return transformEvmNftTransfer(chain, transfer, tx, address);
  }

  return transformEvmTransfer(chain, tx, transfer, address);
}

/**
 * The backend swap row carries the native fee, which is zero when a paymaster paid it.
 * The chain transaction has the token fee.
 */
export async function fetchActivityDetails(
  accountId: string,
  activity: ApiActivity,
  signal?: AbortSignal,
): Promise<ApiActivity | undefined> {
  if (activity.kind !== 'swap' || !activity.shouldLoadDetails) {
    return undefined;
  }

  const chain = getEvmSwapChain(activity);
  const hash = getEvmSwapHash(activity);
  if (!chain || !hash || !activity.fromAddress) {
    return undefined;
  }

  const { network } = parseAccountId(accountId);
  let txs: ZerionTransaction[];
  try {
    txs = await fetchEvmTxs({
      chain,
      network,
      hash,
      address: normalizeAddress(activity.fromAddress),
      signal,
    });
  } catch (err) {
    throwIfAborted(signal);
    logDebugError('fetchActivityDetails', chain, err);
    return undefined;
  }

  const parsed = txs[0] ? transformEvmTxToUnified(chain, txs[0], normalizeAddress(activity.fromAddress)) : undefined;
  if (!parsed || parsed.kind !== 'swap' || !parsed.extra?.isGasless) {
    return undefined;
  }

  return {
    ...activity,
    networkFee: parsed.networkFee,
    extra: { ...activity.extra, isGasless: true },
    shouldLoadDetails: undefined,
  };
}

function getEvmSwapChain(activity: ApiActivity & { kind: 'swap' }): EVMChain | undefined {
  const candidates = [
    activity.transactionIds.outgoing?.chain,
    activity.transactionIds.incoming?.chain,
    getChainBySlug(activity.from),
    getChainBySlug(activity.to),
  ];

  return candidates.find((chain): chain is EVMChain => findChainConfig(chain)?.chainStandard === 'ethereum');
}

function getEvmSwapHash(activity: ApiActivity & { kind: 'swap' }) {
  const hashes = [
    activity.externalMsgHashNorm,
    activity.transactionIds.outgoing?.hash,
    activity.transactionIds.incoming?.hash,
    ...activity.hashes,
  ];

  return hashes.find((hash) => hash?.startsWith('0x'));
}
