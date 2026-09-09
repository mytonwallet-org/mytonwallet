import { Cell } from '@ton/core';

import type {
  ApiActivity,
  ApiNetwork,
  ApiNft,
  ApiNftAttribute,
  ApiNftSuperCollection,
  ApiSwapActivity,
  ApiSwapDexLabel,
  ApiToken,
  ApiTransaction,
  ApiTransactionActivity,
  ApiTransactionType,
} from '../../../types';
import type { ParsedAction } from '../types';
import type {
  AddressBook,
  AnyAction,
  AuctionBidAction,
  CallContractAction,
  ContractDeployAction,
  DexDepositLiquidityAction,
  DexSlug,
  DexWithdrawLiquidityAction,
  DnsAction,
  JettonBurnAction,
  JettonMasterMetadata,
  JettonMintAction,
  JettonTransferAction,
  MetadataMap,
  NftCollectionMetadata,
  NftItemMetadata,
  NftMintAction,
  NftTransferAction,
  SocketFinality,
  StakeDepositAction,
  StakeWithdrawalAction,
  StakeWithdrawalRequestAction,
  SwapAction,
  TonTransferAction,
} from './types';

import {
  BURN_ADDRESS,
  DNS_IMAGE_GEN_URL,
  ETHENA_STAKING_VAULT,
  LIQUID_POOL,
  MW_CARDS_COLLECTION,
  MYCOIN_STAKING_POOL,
  NFT_FRAGMENT_COLLECTIONS,
  NFT_FRAGMENT_GIFT_IMAGE_TO_URL_REGEX,
  STON_PTON_ADDRESS,
  TON_TSUSDE,
  TON_USDE,
  TONCOIN,
} from '../../../../config';
import { buildTxId, parseTxId } from '../../../../util/activities';
import { sortActivities } from '../../../../util/activities/order';
import { toMilliseconds, toSeconds } from '../../../../util/datetime';
import { toDecimal } from '../../../../util/decimals';
import { getDnsDomainZone } from '../../../../util/dns';
import { fixIpfsUrl, getProxiedLottieUrl } from '../../../../util/fetch';
import { omitUndefined } from '../../../../util/iteratees';
import { logDebugError } from '../../../../util/logs';
import safeExec from '../../../../util/safeExec';
import { buildMwCardsNftMetadata, getIsFragmentGift, getIsNftUnverified, readComment } from '../util/metadata';
import { toBase64Address } from '../util/tonCore';
import {
  checkHasScamLink,
  checkIsTrustedCollection,
  getNftSuperCollectionsByCollectionAddress,
} from '../../../common/addresses';
import { updateActivityMetadata } from '../../../common/helpers';
import { buildTokenSlug, getTokenBySlug } from '../../../common/tokens';
import {
  EXCESS_OP_CODES,
  JettonStakingOpCode,
  OpCode,
  TeleitemOpCode,
} from '../constants';
import { extractMetadata, getProxiedImage } from './metadata';
import { callToncenterV3 } from './other';

type ActionsResponse = {
  actions: AnyAction[];
  address_book: AddressBook;
  metadata?: MetadataMap;
};

type ParseOptions = {
  network: ApiNetwork;
  addressBook: AddressBook;
  walletAddress: string;
  metadata: MetadataMap;
  nftSuperCollectionsByCollectionAddress: Record<string, ApiNftSuperCollection>;
  isPending?: boolean;
  finality?: SocketFinality;
};

function resolveActivityStatus(
  isPending: boolean | undefined,
  isSuccess: boolean,
  finality: SocketFinality | undefined,
): ApiTransaction['status'] {
  if (isPending) {
    return 'pending';
  }
  if (finality === 'confirmed' || finality === 'signed') {
    return 'confirmed';
  }
  return isSuccess ? 'completed' : 'failed';
}

const RAW_LIQUID_POOL_ADDRESS = '0:F6FF877DD4CE1355B101572045F09D54C29309737EB52CA542CFA6C195F7CC5B';
const RAW_NFT_CARD_COLLECTION = '0:901362FD85FC31D55F2C82617D91EADA1F1D6B34AF559A047572D56F20D046CA';
const TME_RENEW_HASH_SUFFIX = '0000000000000000000000000000000000000000000000';

const RAW_NFT_COLLECTIONS_TO_RELOAD_METADATA = new Set<string | null>([RAW_NFT_CARD_COLLECTION]);

type FetchActionsOptions = {
  network: ApiNetwork;
  filter: {
    /** Mismatches `walletAddress` when actions are requested for a specific token */
    address: string | string[];
  } | {
    actionId: string | string[];
  };
  limit: number;
  walletAddress: string;
  fromTimestamp?: number;
  toTimestamp?: number;
  shouldIncludeFrom?: boolean;
  shouldIncludeTo?: boolean;
  includeTypes?: AnyAction['type'][];
  excludeTypes?: AnyAction['type'][];
  signal?: AbortSignal;
};

/**
 * Fetches actions, parses them, sorts according to our rules and makes sure there are no duplicates.
 */
export async function fetchActions(options: FetchActionsOptions): Promise<ApiActivity[]> {
  const {
    network, filter, limit, toTimestamp, fromTimestamp,
    shouldIncludeFrom, shouldIncludeTo, walletAddress,
    includeTypes, excludeTypes, signal,
  } = options;

  const data: AnyLiteral = {
    account: 'address' in filter ? filter.address : undefined,
    action_id: 'actionId' in filter ? filter.actionId : undefined,
    limit,
    start_utime: fromTimestamp && toSeconds(fromTimestamp) + (!shouldIncludeFrom ? 1 : 0),
    end_utime: toTimestamp && toSeconds(toTimestamp) - (!shouldIncludeTo ? 1 : 0),
    sort: 'desc',
    ...(includeTypes?.length && { action_type: includeTypes.join(',') }),
    ...(excludeTypes?.length && { exclude_action_type: excludeTypes.join(',') }),
  };

  // The API sorts the actions by trace_end_lt + trace_id + action_end_lt + action_id.
  // That is, the actions are grouped by the trace, and sorted by the time inside the groups.
  const {
    actions,
    address_book: addressBook,
    metadata = {},
  } = await callToncenterV3<ActionsResponse>(network, '/actions', data, signal);

  const nftSuperCollectionsByCollectionAddress = await getNftSuperCollectionsByCollectionAddress();

  const activities = parseActionsToActivities(actions, {
    network,
    walletAddress,
    addressBook,
    metadata,
    nftSuperCollectionsByCollectionAddress,
  });

  // Even though the activities returned by Toncenter are sorted by timestamp, our sorting may differ.
  // It's important to enforce our sorting, because otherwise `mergeSortedActivities` may leave duplicates.
  return sortActivities(activities);
}

export async function fetchPendingActions(network: ApiNetwork, address: string): Promise<ApiActivity[]> {
  const {
    actions,
    address_book: addressBook,
    metadata = {},
  } = await callToncenterV3<ActionsResponse>(network, '/pendingActions', {
    account: address,
  });

  const nftSuperCollectionsByCollectionAddress = await getNftSuperCollectionsByCollectionAddress();

  return parseActionsToActivities(actions, {
    network,
    walletAddress: address,
    addressBook,
    metadata,
    nftSuperCollectionsByCollectionAddress,
    isPending: true,
  });
}

export function parseActionsToActivities(actions: AnyAction[], options: ParseOptions): ApiActivity[] {
  const activities: ApiActivity[] = [];

  for (const action of actions) {
    const parsedAction = parseAction(action, options);
    for (const activity of parsedAction.activities) {
      activities.push(activity);
    }
  }

  return activities;
}

export function parseActions(actions: AnyAction[], options: ParseOptions): ParsedAction[] {
  return actions.map((action) => parseAction(action, options));
}

function parseAction(action: AnyAction, options: ParseOptions): ParsedAction {
  let result: ParsedAction = {
    action,
    activities: [],
  };

  switch (action.type) {
    case 'ton_transfer': {
      result = parseTonTransfer(action, options);
      break;
    }
    case 'call_contract': {
      result = parseCallContract(action, options);
      break;
    }
    case 'contract_deploy': {
      result = parseContractDeploy(action, options);
      break;
    }
    case 'nft_transfer': {
      result = parseNftTransfer(action, options);
      break;
    }
    case 'nft_mint': {
      result = parseNftMint(action, options);
      break;
    }
    case 'jetton_transfer': {
      result = parseJettonTransfer(action, options);
      break;
    }
    case 'jetton_mint': {
      result = parseJettonMint(action, options);
      break;
    }
    case 'jetton_burn': {
      result = parseJettonBurn(action, options);
      break;
    }
    case 'stake_deposit': {
      result = parseStakeDeposit(action, options);
      break;
    }
    case 'stake_withdrawal': {
      result = parseStakeWithdrawal(action, options);
      break;
    }
    case 'stake_withdrawal_request': {
      result = parseStakeWithdrawalRequest(action, options);
      break;
    }
    case 'jetton_swap': {
      result = parseJettonSwap(action, options);
      break;
    }
    case 'change_dns':
    case 'delete_dns':
    case 'renew_dns': {
      result = parseDns(action, options);
      break;
    }
    case 'auction_bid': {
      result = parseAuctionBid(action, options);
      break;
    }
    case 'dex_deposit_liquidity': {
      result = parseLiquidityDeposit(action, options);
      break;
    }
    case 'dex_withdraw_liquidity': {
      result = parseLiquidityWithdraw(action, options);
      break;
    }
  }

  for (let i = 0; i < result.activities.length; i++) {
    const activity = result.activities[i];
    if (!activity) continue;

    if ('nft' in activity && activity.nft?.isHidden) {
      activity.shouldHide = true;
    }

    if (activity.kind === 'transaction' && !activity.isIncoming) {
      activity.shouldLoadDetails ??= true;
    }

    result.activities[i] = updateActivityMetadata(activity);
  }

  return result;
}

function parseTonTransfer(action: TonTransferAction, options: ParseOptions): ParsedAction {
  const { details, details: { encrypted: isEncrypted, source, destination, value } } = action;

  const comment = (!isEncrypted && details.comment) || undefined;
  const encryptedComment = (isEncrypted && details.comment) || undefined;

  const activity: ApiTransactionActivity = {
    ...parseCommonFields(action, options, source, destination, value),
    slug: TONCOIN.slug,
    comment,
    encryptedComment,
  };

  return {
    action,
    activities: [activity],
  };
}

function parseCallContract(action: CallContractAction, options: ParseOptions): ParsedAction {
  const { walletAddress } = options;
  const { details, details: { source, destination, value } } = action;

  const common = parseCommonFields(action, options, source, destination, value);
  const opCode = Number(details.opcode);
  const shouldHide = !common.isIncoming && [OpCode.OurFee, TeleitemOpCode.Ok].includes(opCode);

  let type: ApiTransactionType | undefined;
  if (EXCESS_OP_CODES.includes(opCode)) {
    type = 'excess';
  // eslint-disable-next-line @typescript-eslint/no-unsafe-enum-comparison
  } else if (opCode === OpCode.Bounced) {
    type = 'bounced';
  } else if ([JettonStakingOpCode.UnstakeRequest, JettonStakingOpCode.ClaimRewards].includes(opCode)) {
    type = 'unstakeRequest';
  } else if (common.toAddress !== walletAddress) {
    type = 'callContract';
  }

  const activity: ApiTransactionActivity = {
    ...common,
    slug: TONCOIN.slug,
    type,
    shouldHide,
    extra: omitUndefined({
      // eslint-disable-next-line @typescript-eslint/no-unsafe-enum-comparison
      ...(opCode === OpCode.OurFee && { isOurSwapFee: true }),
    }),
  };

  return {
    action,
    activities: [activity],
  };
}

function parseContractDeploy(action: ContractDeployAction, options: ParseOptions): ParsedAction {
  const { details: { source, destination } } = action;

  if (!source) {
    return { action, activities: [] };
  }

  // Deploy action is additional and always occurs alongside others (duplicating amount), so we hide amount and fee.

  const activity: ApiTransactionActivity = {
    ...parseCommonFields(action, options, source, destination),
    slug: TONCOIN.slug,
    type: 'contractDeploy',
    shouldLoadDetails: false,
    fee: 0n,
  };

  return {
    action,
    activities: [activity],
    toncoinChange: activity.amount,
  };
}

function parseJettonTransfer(action: JettonTransferAction, options: ParseOptions): ParsedAction {
  const { addressBook } = options;
  const {
    details,
    details: {
      is_encrypted_comment: isEncrypted,
      forward_payload: forwardPayload,
      sender,
      receiver,
      amount,
    },
  } = action;

  const common = parseCommonFields(action, options, sender, receiver, amount);
  const { isIncoming, toAddress, fromAddress } = common;

  const comment = (!isEncrypted && details.comment) || undefined;
  const encryptedComment = (isEncrypted && details.comment) || undefined;
  const tokenAddress = addressBook[details.asset].user_friendly;
  const slug = buildTokenSlug('ton', tokenAddress);
  const isOurSwapFee = !isIncoming && isOurSwapFeePayload(forwardPayload);

  let type: ApiTransactionType;
  if (toAddress === BURN_ADDRESS) {
    type = 'burn';
  } else if (toAddress === MYCOIN_STAKING_POOL) {
    type = 'stake';
  } else if (fromAddress === MYCOIN_STAKING_POOL) {
    type = 'unstake';
  } else if (tokenAddress === TON_USDE.tokenAddress) {
    if (fromAddress === ETHENA_STAKING_VAULT) {
      type = 'unstake';
    } else if (toAddress === ETHENA_STAKING_VAULT) {
      type = 'stake';
    }
  }

  const activity: ApiTransactionActivity = {
    ...common,
    slug,
    comment,
    encryptedComment,
    shouldHide: isOurSwapFee,
    type,
    extra: omitUndefined({
      queryId: details.query_id,
      ...(isOurSwapFee && { isOurSwapFee: true }),
    }),
  };

  return {
    action,
    activities: [activity],
  };
}

function parseJettonMint(action: JettonMintAction, options: ParseOptions): ParsedAction {
  const { addressBook } = options;
  const {
    details,
    details: {
      receiver,
      receiver_jetton_wallet: jettonWalletRaw,
      amount,
    },
  } = action;

  const tokenAddress = addressBook[details.asset].user_friendly;
  const slug = buildTokenSlug('ton', tokenAddress);

  let commonFields: ReturnType<typeof parseCommonFields>;
  let type: ApiTransactionType = 'mint';

  if (
    tokenAddress === TON_TSUSDE.tokenAddress
    && action.end_lt !== action.trace_end_lt
  ) {
    // TODO After fix on Toncenter's side, move it to transfer parsing (currently it's mistakenly detected as mint)
    type = 'unstakeRequest';
    const { metadata: _metadata, ...commonFieldsWithoutMetadata } = parseCommonFields(
      action, options, receiver, receiver, 0,
    );
    commonFields = {
      ...commonFieldsWithoutMetadata,
      toAddress: ETHENA_STAKING_VAULT,
      isIncoming: false,
      normalizedAddress: ETHENA_STAKING_VAULT,
    };
  } else {
    commonFields = parseCommonFields(action, options, jettonWalletRaw, receiver, amount);
  }

  const activity: ApiTransactionActivity = {
    ...commonFields,
    slug,
    type,
  };

  return {
    action,
    activities: [activity],
  };
}

function parseJettonBurn(action: JettonBurnAction, options: ParseOptions): ParsedAction {
  const { network } = options;
  const { details, details: { owner, owner_jetton_wallet: jettonWallet, amount } } = action;

  const slug = buildTokenSlug('ton', toBase64Address(details.asset, true, network));

  const activity: ApiTransactionActivity = {
    ...parseCommonFields(action, options, owner, jettonWallet, amount),
    slug,
    type: 'burn',
  };

  return {
    action,
    activities: [activity],
  };
}

function parseNftTransfer(action: NftTransferAction, options: ParseOptions): ParsedAction {
  const {
    network,
    metadata,
    walletAddress,
    addressBook,
    nftSuperCollectionsByCollectionAddress,
  } = options;

  const {
    nft_item_index: index,
    nft_item: rawNftAddress,
    nft_collection: rawCollectionAddress,
    new_owner: newOwner,
    old_owner: oldOwner,
    forward_payload: forwardPayload,
    is_purchase: isPurchase,
    price,
    response_destination: responseDestination,
    marketplace,
    payout_amount: payoutAmount,
  } = action.details;

  const { nft, isMetadataMissing } = parseToncenterNft(
    network,
    metadata,
    rawNftAddress,
    nftSuperCollectionsByCollectionAddress,
    { rawCollectionAddress: rawCollectionAddress ?? undefined, index: index ?? undefined },
  );

  let shouldHide = !nft && rawCollectionAddress ? isHiddenCollection(rawCollectionAddress, metadata) : undefined;

  // Hide duplicate NFT transfer actions that appear when listing NFT on Getgems marketplace
  // These are actions where old_owner and new_owner are not the wallet address,
  // but wallet address is only in response_destination
  if (oldOwner && newOwner && responseDestination) {
    const oldOwnerAddress = addressBook[oldOwner]?.user_friendly;
    const newOwnerAddress = addressBook[newOwner]?.user_friendly;

    if (oldOwnerAddress !== walletAddress && newOwnerAddress !== walletAddress) {
      shouldHide = true;
    }
  }

  const activity: ApiTransactionActivity = {
    ...parseCommonFields(action, options, oldOwner ?? rawNftAddress, newOwner),
    shouldHide,
    slug: TONCOIN.slug,
    nft,
    comment: (forwardPayload && safeReadComment(forwardPayload)) || undefined,
    shouldReload: (isMetadataMissing && RAW_NFT_COLLECTIONS_TO_RELOAD_METADATA.has(action.details.nft_collection))
      || undefined,
    extra: omitUndefined({
      queryId: action.details.query_id,
    }),
  };

  if (activity.toAddress === BURN_ADDRESS) {
    activity.type = 'burn';
  } else if (isPurchase && price) {
    const isBuying = addressBook[newOwner]?.user_friendly === walletAddress;
    activity.type = 'nftTrade';
    activity.isIncoming = !isBuying;
    activity.amount = isBuying ? -BigInt(price) : BigInt(payoutAmount || price);
    activity.extra = {
      marketplace: marketplace ?? undefined,
    };
  }

  const toncoinChange = action.details.is_purchase ? -BigInt(action.details.price!) : undefined;

  return {
    action,
    activities: [activity],
    toncoinChange,
  };
}

function parseNftMint(action: NftMintAction, options: ParseOptions): ParsedAction {
  const { network, metadata, nftSuperCollectionsByCollectionAddress } = options;

  const {
    owner,
    nft_item_index: index,
    nft_item: rawNftAddress,
    nft_collection: rawCollectionAddress,
  } = action.details;

  const { nft, isMetadataMissing } = parseToncenterNft(
    network,
    metadata,
    rawNftAddress,
    nftSuperCollectionsByCollectionAddress,
    { rawCollectionAddress: rawCollectionAddress ?? undefined, index: index ?? undefined },
  );

  const activity: ApiTransactionActivity = {
    ...parseCommonFields(action, options, owner, rawNftAddress),
    slug: TONCOIN.slug,
    nft,
    type: 'mint',
    shouldReload: (isMetadataMissing && RAW_NFT_COLLECTIONS_TO_RELOAD_METADATA.has(action.details.nft_collection))
      || undefined,
  };

  return {
    action,
    activities: [activity],
  };
}

function isHiddenCollection(rawCollectionAddress: string, metadata: MetadataMap) {
  const collectionMetadata = metadata[rawCollectionAddress]?.token_info[0] as NftCollectionMetadata | undefined;
  return collectionMetadata?.name?.includes('Withdrawal Payout');
}

function parseStakeDeposit(action: StakeDepositAction, options: ParseOptions): ParsedAction {
  const { details: { stake_holder: holder, pool, amount } } = action;

  const activity: ApiTransactionActivity = {
    ...parseCommonFields(action, options, holder, pool, amount),
    slug: TONCOIN.slug,
    type: 'stake',
  };

  return {
    action,
    activities: [activity],
    toncoinChange: activity.amount,
  };
}

function parseStakeWithdrawal(action: StakeWithdrawalAction, options: ParseOptions): ParsedAction {
  const { addressBook } = options;
  const { details, details: { stake_holder: holder, amount } } = action;

  // Fix issue with old data when pool is null
  const pool = details.pool ?? RAW_LIQUID_POOL_ADDRESS;
  const fixedOptions = pool in addressBook ? options : {
    ...options,
    addressBook: {
      ...addressBook,
      // eslint-disable-next-line no-null/no-null
      [pool]: { user_friendly: LIQUID_POOL, domain: null },
    },
  };

  const activity: ApiTransactionActivity = {
    ...parseCommonFields(action, fixedOptions, pool, holder, amount),
    slug: TONCOIN.slug,
    type: 'unstake',
    shouldLoadDetails: details.provider === 'tonstakers' && !details.payout_nft,
  };

  return {
    action,
    activities: [activity],
    toncoinChange: activity.amount,
  };
}

function parseStakeWithdrawalRequest(action: StakeWithdrawalRequestAction, options: ParseOptions): ParsedAction {
  const { details: { stake_holder: holder, pool } } = action;

  const activity: ApiTransactionActivity = {
    ...parseCommonFields(action, options, holder, pool, 0), // TODO (actions) Replace to real fee
    slug: TONCOIN.slug,
    type: 'unstakeRequest',
  };

  return {
    action,
    activities: [activity],
  };
}

function parseJettonSwap(action: SwapAction, options: ParseOptions): ParsedAction {
  const { metadata, isPending, addressBook, walletAddress } = options;
  const {
    end_utime: endUtime,
    success: isSuccess,
    details: {
      dex_incoming_transfer: {
        amount: fromAmount,
        asset: fromAsset,
        source: fromSource,
      },
      dex_outgoing_transfer: {
        amount: toAmount,
        asset: toAsset,
        destination: toDestination,
      },
      sender,
    },
  } = action;

  const decimalsFrom = (fromAsset && parseToncenterJetton(fromAsset, metadata)?.decimals) || TONCOIN.decimals;
  const decimalsTo = (toAsset && parseToncenterJetton(toAsset, metadata)?.decimals) || TONCOIN.decimals;

  const fromTokenAddress = fromAsset ? toBase64Address(fromAsset, true) : undefined;
  const toTokenAddress = toAsset ? toBase64Address(toAsset, true) : undefined;

  let from: string;
  let to: string;
  // The TON a leg takes or gives changes the wallet's balance only when the wallet is the leg's counterparty. In a
  // route through TON the router hands the TON of one hop to the next one, so it is neither the wallet's cost nor
  // its income
  let toncoinChange = 0n;
  const isWallet = (rawAddress: string) => addressBook[rawAddress]?.user_friendly === walletAddress;

  if (fromTokenAddress && fromTokenAddress !== STON_PTON_ADDRESS) {
    from = buildTokenSlug('ton', fromTokenAddress);
  } else {
    from = TONCOIN.slug;
    if (isWallet(fromSource)) toncoinChange = -BigInt(fromAmount);
  }

  if (toTokenAddress && toTokenAddress !== STON_PTON_ADDRESS) {
    to = buildTokenSlug('ton', toTokenAddress);
  } else {
    to = TONCOIN.slug;
    if (isWallet(toDestination)) toncoinChange = BigInt(toAmount);
  }

  const activity: ApiSwapActivity = {
    kind: 'swap',
    id: buildActionActivityId(action),
    timestamp: toMilliseconds(endUtime),
    from,
    fromAmount: toDecimal(BigInt(fromAmount), decimalsFrom),
    fromAddress: sender,
    to,
    toAmount: toDecimal(BigInt(toAmount), decimalsTo),
    networkFee: '0',
    swapFee: '0',
    ourFee: '0',
    status: resolveActivityStatus(isPending, isSuccess, options.finality),
    hashes: [],
    transactionIds: {},
    externalMsgHashNorm: action.trace_external_hash_norm ?? action.trace_external_hash,
    shouldLoadDetails: true,
  };

  return {
    action,
    activities: [activity],
    toncoinChange,
  };
}

function parseDns(action: DnsAction, options: ParseOptions): ParsedAction {
  const { network, metadata, nftSuperCollectionsByCollectionAddress } = options;
  const { details: { source, asset } } = action;

  const { nft } = parseToncenterNft(
    network,
    metadata,
    asset,
    nftSuperCollectionsByCollectionAddress,
    // Toncenter gives no collection address for DNS actions, and without one the parser would
    // refuse to treat the item as a domain. Such an action can only come from a real DNS contract,
    // so it is safe to confirm that here
    { isDns: true },
  );

  let type: ApiTransactionType;
  if (action.type === 'change_dns') {
    const { sum_type: sumType } = action.details.value;
    if (sumType === 'DNSSmcAddress') {
      type = 'dnsChangeAddress';
    } else if (sumType === 'DNSAdnlAddress') {
      type = 'dnsChangeSite';
    } else if (sumType === 'DNSStorageAddress') {
      type = 'dnsChangeStorage';
    } else if (sumType === 'DNSNextResolver') {
      type = 'dnsChangeSubdomains';
    }
  } else if (
    action.type === 'renew_dns'
    || (action.type === 'delete_dns' && action.details.hash.endsWith(TME_RENEW_HASH_SUFFIX))
  ) {
    type = 'dnsRenew';
  } else {
    type = 'dnsDelete';
  }

  const activity: ApiTransactionActivity = {
    ...parseCommonFields(action, options, source, asset, 0), // TODO (actions) Replace to real fee
    slug: TONCOIN.slug,
    type,
    nft,
  };

  return {
    action,
    activities: [activity],
  };
}

function parseAuctionBid(action: AuctionBidAction, options: ParseOptions): ParsedAction {
  const { network, metadata, nftSuperCollectionsByCollectionAddress } = options;
  const { details } = action;

  const {
    bidder,
    auction,
    nft_item_index: index,
    nft_item: rawNftAddress,
    nft_collection: rawCollectionAddress,
  } = details;

  const { nft } = parseToncenterNft(
    network,
    metadata,
    rawNftAddress ?? undefined,
    nftSuperCollectionsByCollectionAddress,
    { rawCollectionAddress: rawCollectionAddress ?? undefined, index: index ?? undefined },
  );

  const activity: ApiTransactionActivity = {
    ...parseCommonFields(action, options, bidder, auction, details.amount),
    slug: TONCOIN.slug,
    type: 'auctionBid',
    nft,
  };

  return {
    action,
    activities: [activity],
    toncoinChange: activity.amount,
  };
}

export function parseLiquidityDeposit(action: DexDepositLiquidityAction, options: ParseOptions): ParsedAction {
  const { addressBook } = options;
  const { details, details: { source, pool, destination_liquidity: destinationAddress, dex } } = action;

  const common = parseCommonFields(action, options, source, pool ?? destinationAddress);

  const partialExtended = {
    ...common,
    type: 'liquidityDeposit',
    extra: {
      dex: convertDexId(dex),
    },
  } as const;

  const activities: ApiTransactionActivity[] = [{
    ...partialExtended,
    amount: -BigInt(details.amount_1 ?? 0n),
    slug: getAssetSlug(addressBook, details.asset_1),
  }];

  // eslint-disable-next-line no-null/no-null
  if (details.amount_2 !== null) {
    const id = buildActionActivityId(action, 'additional');
    activities.push({
      ...partialExtended,
      id,
      amount: -BigInt(details.amount_2),
      slug: getAssetSlug(addressBook, details.asset_2),
    });
  }

  const toncoinChange = activities.find(({ slug }) => slug === TONCOIN.slug)?.amount;

  return {
    action,
    activities,
    toncoinChange,
  };
}

function parseLiquidityWithdraw(action: DexWithdrawLiquidityAction, options: ParseOptions): ParsedAction {
  const { addressBook } = options;
  const { details, details: { source, pool, dex } } = action;

  const common = parseCommonFields(action, options, pool, source);

  const partialExtended = {
    ...common,
    shouldLoadDetails: true,
    type: 'liquidityWithdraw',
    extra: {
      dex: convertDexId(dex),
    },
  } as const;

  const additionalId = buildActionActivityId(action, 'additional');

  const activities: ApiTransactionActivity[] = [
    {
      ...partialExtended,
      amount: BigInt(details.amount_1),
      slug: getAssetSlug(addressBook, details.asset_1),
    },
    {
      ...partialExtended,
      id: additionalId,
      amount: BigInt(details.amount_2),
      slug: getAssetSlug(addressBook, details.asset_2),
    },
  ];

  const toncoinChange = activities.find(({ slug }) => slug === TONCOIN.slug)?.amount;

  return {
    action,
    activities,
    toncoinChange,
  };
}

function getAssetSlug(addressBook: AddressBook, rawAddress?: string | null) {
  return rawAddress ? buildTokenSlug('ton', addressBook[rawAddress].user_friendly) : TONCOIN.slug;
}

function parseCommonFields(
  action: AnyAction,
  options: ParseOptions,
  rawFromAddress: string,
  rawToAddress: string,
  amountString: string | number = 0,
) {
  const id = buildActionActivityId(action);
  const { walletAddress, network, addressBook, isPending, finality } = options;
  const fromAddress = addressBook[rawFromAddress].user_friendly;
  const toAddress = addressBook[rawToAddress].user_friendly;
  const isIncoming = toAddress === walletAddress;
  const normalizedAddress = toBase64Address(isIncoming ? fromAddress : toAddress, true, network);
  const amount = isIncoming ? BigInt(amountString) : -BigInt(amountString);
  const domain = addressBook[isIncoming ? rawFromAddress : rawToAddress]?.domain;
  return {
    kind: 'transaction',
    id,
    timestamp: toMilliseconds(action.end_utime),
    externalMsgHashNorm: action.trace_external_hash_norm ?? action.trace_external_hash,
    fee: 0n, // Calculated when TransactionModal opens
    fromAddress,
    toAddress,
    isIncoming,
    normalizedAddress,
    amount,
    ...(domain && { metadata: { name: domain } }),
    // Pending actions from Toncenter are not trusted
    status: resolveActivityStatus(isPending, action.success, finality),
  } satisfies Partial<ApiTransactionActivity>;
}

export function parseToncenterNft(
  network: ApiNetwork,
  metadataMap: MetadataMap,
  rawNftAddress: string,
  nftSuperCollectionsByCollectionAddress: Record<string, ApiNftSuperCollection>,
  options?: {
    rawCollectionAddress?: string;
    /** Stringified integer */
    index?: string;
    /**
     * The NFT owner and whether it is listed for sale. Toncenter reports this only in `/nft/items`.
     * When the NFT is rebuilt from a history action, the state is unknown and both fields are left out.
     */
    ownerAddress?: string;
    isOnSale?: boolean;
    /**
     * Passed as `true` when we know the NFT is a DNS item. Without it an NFT with no collection is
     * never shown as a domain: anyone can mint a standalone NFT and call it `whatever.ton`, so the
     * name alone proves nothing.
     */
    isDns?: boolean;
  },
): { nft?: ApiNft; isMetadataMissing?: true } {
  const { rawCollectionAddress, index, ownerAddress, isOnSale, isDns: isDnsByContext } = options ?? {};

  try {
    const nftMetadata = extractMetadata<NftItemMetadata>(rawNftAddress, metadataMap, 'nft_items');

    if (!nftMetadata) {
      return { isMetadataMissing: true };
    }

    const {
      name, description, extra, image, nft_index: metadataIndex,
      is_nsfw: isNsfwByModeration, is_scam: isScamByModeration,
    } = nftMetadata;
    const parsedIndex = Number(index ?? metadataIndex);
    const nftIndex = Number.isFinite(parsedIndex) ? parsedIndex : 0;
    const lottie = extra?.lottie ? getProxiedLottieUrl(extra.lottie) : undefined;

    const nftAddress = toBase64Address(rawNftAddress, true, network);
    const collectionMetadata = rawCollectionAddress
      ? extractMetadata<NftCollectionMetadata>(rawCollectionAddress, metadataMap, 'nft_collections')
      : undefined;
    const collectionAddress = rawCollectionAddress ? toBase64Address(rawCollectionAddress, true, network) : undefined;

    const domain = extra?.domain ?? name ?? '';
    const { zone: domainZone, base: domainBase } = getDnsDomainZone(domain) ?? {};
    // A name that looks like a domain is not enough. Treat the NFT as a real domain only if its
    // collection is the zone resolver contract, or if the caller vouches that this is a DNS item
    const isDns = collectionAddress
      ? collectionAddress === domainZone?.resolver
      : isDnsByContext;

    if (domainZone && isDns && !image) {
      // Rendered by our own service, so it is as trusted as an indexer preview
      const generatedImage = domainZone.suffixes[0] === 'ton'
        ? `${DNS_IMAGE_GEN_URL}${domainBase}`
        : undefined;

      const nft = omitUndefined<ApiNft>({
        chain: 'ton',
        interface: 'default',
        index: nftIndex,
        name: domain,
        address: nftAddress,

        thumbnail: generatedImage ?? extra?._image_medium,
        image: generatedImage ?? extra?._image_big ?? extra?._image_medium,
        description,
        ownerAddress,
        isOnSale: isOnSale ?? false,
        collectionAddress: collectionAddress ?? domainZone.resolver,
        collectionName: domainZone.collectionName,
        metadata: {
          ...(lottie && { lottie }),
        },
      });
      return { nft };
    }

    let hasScamLink = false;

    if (!collectionAddress || !checkIsTrustedCollection(collectionAddress)) {
      for (const text of [name, description].filter(Boolean)) {
        if (checkHasScamLink(text)) {
          hasScamLink = true;
        }
      }
    }

    // Toncenter moderates whole collections too, and an item of a flagged collection carries no
    // flag of its own
    const isScam = (isScamByModeration ?? collectionMetadata?.is_scam) || hasScamLink;
    const isNsfw = isNsfwByModeration ?? collectionMetadata?.is_nsfw;
    const isHidden = extra?.render_type === 'hidden' || isScam;
    const isFragmentGift = getIsFragmentGift(nftSuperCollectionsByCollectionAddress, collectionAddress);
    const isOnFragment = isFragmentGift || NFT_FRAGMENT_COLLECTIONS.includes(rawCollectionAddress!);
    const isMwCard = collectionAddress === MW_CARDS_COLLECTION;
    // A non-string `value` breaks the UI, and the MyTonWallet card traits are read as strings too
    const attributes = Array.isArray(extra?.attributes)
      ? extra.attributes.filter((attribute): attribute is ApiNftAttribute => typeof attribute?.value === 'string')
      : undefined;
    // Our own collection served from our own CDN, so its metadata URL is as trusted as an indexer
    // preview. Toncenter also fails to proxy these images, answering 404 for its cached source
    const mwCardImage = isMwCard ? image : undefined;
    // The whitelisted collections have known authors, so the hosts of their metadata URLs are trusted.
    // Only a fallback: the indexer preview, when it exists, keeps the moderation applied
    const trustedRawImage = image && collectionAddress && checkIsTrustedCollection(collectionAddress)
      ? fixIpfsUrl(image)
      : undefined;

    const nft: ApiNft = omitUndefined<ApiNft>({
      chain: 'ton',
      interface: 'default',
      index: nftIndex,
      name: name!,
      address: nftAddress,
      thumbnail: mwCardImage ?? extra?._image_medium ?? trustedRawImage,
      image: mwCardImage ?? extra?._image_big ?? extra?._image_medium ?? trustedRawImage,
      description,
      ownerAddress,
      isOnSale: isOnSale ?? false,
      isHidden,
      isScam,
      isNsfw,
      isUnverified: getIsNftUnverified({ collectionAddress, isOnFragment }),
      metadata: {
        ...(attributes && { attributes }),
        ...(lottie && { lottie }),
        // The URL is derived from the image URL, so a gift without an image simply has no link
        ...(isFragmentGift && image && {
          fragmentUrl: image.replace(NFT_FRAGMENT_GIFT_IMAGE_TO_URL_REGEX, 'https://$1'),
        }),
        // `id` must be set to `index + 1`. Unlike TonApi where this field is preformatted,
        // we need to manually adjust it here due to data source differences.
        ...(isMwCard && buildMwCardsNftMetadata({ id: nftIndex + 1, image, attributes })),
      },
      ...(collectionAddress && {
        collectionAddress,
        collectionName: collectionMetadata?.name,
        isOnFragment,
        isTelegramGift: isFragmentGift,
      }),
    });

    return { nft };
  } catch (err) {
    logDebugError('parseToncenterNft', err);
    return {};
  }
}

function parseToncenterJetton(rawAddress: string, metadata: MetadataMap): ApiToken | undefined {
  const tokenAddress = toBase64Address(rawAddress, true);
  const slug = buildTokenSlug('ton', tokenAddress);
  const token = getTokenBySlug(slug);

  if (token) {
    return token;
  }

  const jettonMetadata = extractMetadata<JettonMasterMetadata>(rawAddress, metadata, 'jetton_masters');

  if (!jettonMetadata) {
    return undefined;
  }

  return {
    tokenAddress,
    slug,
    chain: 'ton',
    name: jettonMetadata.name!,
    symbol: jettonMetadata.symbol!,
    image: getProxiedImage(jettonMetadata),
    decimals: Number(jettonMetadata.extra!.decimals),
  };
}

/**
 * Whether a forward payload is the marker our backend attaches to the swap fee transfer. Toncenter serializes the cell
 * without a CRC, so the payload is compared by content, not by its base64 form.
 */
export function isOurSwapFeePayload(payloadBase64: string | null | undefined) {
  if (!payloadBase64) return false;

  return safeExec(() => {
    const slice = Cell.fromBase64(payloadBase64).beginParse();
    // eslint-disable-next-line @typescript-eslint/no-unsafe-enum-comparison
    return slice.remainingBits >= 32 && slice.loadUint(32) === OpCode.OurFee;
  }) ?? false;
}

function safeReadComment(payloadBase64: string) {
  return safeExec(() => {
    const cell = Cell.fromBase64(payloadBase64);
    if (cell.isExotic) return undefined;
    return readComment(cell.asSlice());
  });
}

function buildActionActivityId(action: AnyAction, type?: 'additional') {
  // `lt` in activity ID is needed for sorting when timestamps are same.
  // The sorting is tuned to match the Toncenter API sorting as close as possible.
  const subId = `${action.start_lt}-${action.action_id}`;
  return buildTxId(
    action.trace_id ?? action.trace_external_hash_norm ?? action.trace_external_hash,
    subId,
    type,
  );
}

export function parseActionActivityId(id: string) {
  const { hash: traceId, subId } = parseTxId(id);
  const [startLt, actionId] = subId!.split('-');
  return { traceId, startLt, actionId };
}

function convertDexId(toncenterDex: DexSlug | undefined): ApiSwapDexLabel | undefined {
  switch (toncenterDex) {
    case 'dedust':
      return 'dedust';
    case 'stonfi':
    case 'stonfi_v2':
      return 'ston';
    default:
      return undefined;
  }
}
