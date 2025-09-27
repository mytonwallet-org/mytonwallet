import { Cell } from '@ton/core';

import type {
  ApiActivity,
  ApiNetwork,
  ApiNft,
  ApiNftSuperCollection,
  ApiSwapActivity,
  ApiSwapDexLabel,
  ApiToken,
  ApiTransactionActivity,
  ApiTransactionType,
} from '../../../types';
import type {
  AddressBook,
  AnyAction,
  AnyTokenMetadata,
  AuctionBidAction,
  CallContractAction,
  ChangeDnsAction,
  ContractDeployAction,
  DeleteDnsAction,
  DexDepositLiquidityAction,
  DexSlug,
  DexWithdrawLiquidityAction,
  JettonBurnAction,
  JettonMasterMetadata,
  JettonMintAction,
  JettonTransferAction,
  MetadataMap,
  NftCollectionMetadata,
  NftItemMetadata,
  NftMintAction,
  NftTransferAction,
  RenewDnsAction,
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
  MTW_CARDS_COLLECTION,
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
import { buildMtwCardsNftMetadata, getIsFragmentGift, readComment } from '../util/metadata';
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
  OUR_FEE_PAYLOAD_BOC,
  TeleitemOpCode,
} from '../constants';
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
};

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
};

/**
 * Fetches actions, parses them, sorts according to our rules and makes sure there are no duplicates.
 */
export async function fetchActions(options: FetchActionsOptions): Promise<ApiActivity[]> {
  const {
    network, filter, limit, toTimestamp, fromTimestamp,
    shouldIncludeFrom, shouldIncludeTo, walletAddress,
    includeTypes, excludeTypes,
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
    actions: rawActions,
    address_book: addressBook,
    metadata = {},
  } = await callToncenterV3<ActionsResponse>(network, '/actions', data);
  const nftSuperCollectionsByCollectionAddress = await getNftSuperCollectionsByCollectionAddress();

  const activities = parseActions(
    network,
    walletAddress,
    rawActions,
    addressBook,
    metadata,
    nftSuperCollectionsByCollectionAddress,
  );

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

  return parseActions(
    network,
    address,
    actions,
    addressBook,
    metadata,
    nftSuperCollectionsByCollectionAddress,
    true,
  );
}

export function parseActions(
  network: ApiNetwork,
  walletAddress: string,
  rawActions: AnyAction[],
  addressBook: AddressBook,
  metadata: MetadataMap,
  nftSuperCollectionsByCollectionAddress: Record<string, ApiNftSuperCollection>,
  isPending?: boolean,
): ApiActivity[] {
  const options: ParseOptions = {
    network,
    addressBook,
    walletAddress,
    metadata,
    nftSuperCollectionsByCollectionAddress,
    isPending,
  };
  const activities = [];

  for (const action of rawActions) {
    activities.push(...parseAction(action, options));
  }

  return activities;
}

function parseAction(action: AnyAction, options: ParseOptions): ApiActivity[] {
  let result: (ApiActivity | undefined)[] = [];

  switch (action.type) {
    case 'ton_transfer': {
      result = [parseTonTransfer(action, options)];
      break;
    }
    case 'call_contract': {
      result = [parseCallContract(action, options)];
      break;
    }
    case 'contract_deploy': {
      result = [parseContractDeploy(action, options)];
      break;
    }
    case 'nft_transfer': {
      result = [parseNftTransfer(action, options)];
      break;
    }
    case 'nft_mint': {
      result = [parseNftMint(action, options)];
      break;
    }
    case 'jetton_transfer': {
      result = [parseJettonTransfer(action, options)];
      break;
    }
    case 'jetton_mint': {
      result = [parseJettonMint(action, options)];
      break;
    }
    case 'jetton_burn': {
      result = [parseJettonBurn(action, options)];
      break;
    }
    case 'stake_deposit': {
      result = [parseStakeDeposit(action, options)];
      break;
    }
    case 'stake_withdrawal': {
      result = [parseStakeWithdrawal(action, options)];
      break;
    }
    case 'stake_withdrawal_request': {
      result = [parseStakeWithdrawalRequest(action, options)];
      break;
    }
    case 'jetton_swap': {
      result = [parseJettonSwap(action, options)];
      break;
    }
    case 'change_dns':
    case 'delete_dns':
    case 'renew_dns': {
      result = [parseDns(action, options)];
      break;
    }
    case 'auction_bid': {
      result = [parseAuctionBid(action, options)];
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

  for (let i = 0; i < result.length; i++) {
    const activity = result[i];
    if (!activity) continue;

    if ('nft' in activity && activity.nft?.isHidden) {
      activity.shouldHide = true;
    }

    if (activity.kind === 'transaction' && !activity.isIncoming) {
      activity.shouldLoadDetails ??= true;
    }

    result[i] = updateActivityMetadata(activity);
  }

  return result.filter(Boolean);
}

function parseTonTransfer(action: TonTransferAction, options: ParseOptions): ApiTransactionActivity {
  const { details, details: { encrypted: isEncrypted, source, destination, value } } = action;

  const comment = (!isEncrypted && details.comment) || undefined;
  const encryptedComment = (isEncrypted && details.comment) || undefined;

  return {
    ...parseCommonFields(action, options, source, destination, value),
    slug: TONCOIN.slug,
    comment,
    encryptedComment,
  };
}

function parseCallContract(action: CallContractAction, options: ParseOptions): ApiTransactionActivity | undefined {
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

  return {
    ...common,
    slug: TONCOIN.slug,
    type,
    shouldHide,
  };
}

function parseContractDeploy(action: ContractDeployAction, options: ParseOptions): ApiTransactionActivity | undefined {
  const { details: { source, destination } } = action;

  if (!source) {
    return undefined;
  }

  // Deploy action is additional and always occurs alongside others (duplicating amount), so we hide amount and fee.

  return {
    ...parseCommonFields(action, options, source, destination),
    slug: TONCOIN.slug,
    type: 'contractDeploy',
    shouldLoadDetails: false,
    fee: 0n,
  };
}

function parseJettonTransfer(action: JettonTransferAction, options: ParseOptions): ApiTransactionActivity {
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
  const shouldHide = !isIncoming && forwardPayload === OUR_FEE_PAYLOAD_BOC;

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

  return {
    ...common,
    slug,
    comment,
    encryptedComment,
    shouldHide,
    type,
  };
}

function parseJettonMint(action: JettonMintAction, options: ParseOptions): ApiTransactionActivity {
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
    commonFields = {
      ...parseCommonFields(action, options, receiver, receiver, 0),
      toAddress: ETHENA_STAKING_VAULT,
      isIncoming: false,
      normalizedAddress: ETHENA_STAKING_VAULT,
    };
  } else {
    commonFields = parseCommonFields(action, options, jettonWalletRaw, receiver, amount);
  }

  return {
    ...commonFields,
    slug,
    type,
  };
}

function parseJettonBurn(action: JettonBurnAction, options: ParseOptions): ApiTransactionActivity {
  const { network } = options;
  const { details, details: { owner, owner_jetton_wallet: jettonWallet, amount } } = action;

  const slug = buildTokenSlug('ton', toBase64Address(details.asset, true, network));

  return {
    ...parseCommonFields(action, options, owner, jettonWallet, amount),
    slug,
    type: 'burn',
  };
}

function parseNftTransfer(action: NftTransferAction, options: ParseOptions): ApiTransactionActivity {
  const {
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
  } = action.details;

  const { nft, isMetadataMissing } = parseToncenterNft(
    metadata,
    rawNftAddress,
    nftSuperCollectionsByCollectionAddress,
    rawCollectionAddress ?? undefined,
    index ?? undefined,
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
  };

  if (activity.toAddress === BURN_ADDRESS) {
    activity.type = 'burn';
  } else if (isPurchase && price) {
    const isBuying = addressBook[newOwner]?.user_friendly === walletAddress;
    activity.type = 'nftTrade';
    activity.isIncoming = !isBuying;
    activity.amount = isBuying ? -BigInt(price) : BigInt(price);
    activity.extra = {
      marketplace: marketplace ?? undefined,
    };
  }

  return activity;
}

function parseNftMint(action: NftMintAction, options: ParseOptions): ApiTransactionActivity {
  const { metadata, nftSuperCollectionsByCollectionAddress } = options;

  const {
    owner,
    nft_item_index: index,
    nft_item: rawNftAddress,
    nft_collection: rawCollectionAddress,
  } = action.details;

  const { nft, isMetadataMissing } = parseToncenterNft(
    metadata,
    rawNftAddress,
    nftSuperCollectionsByCollectionAddress,
    rawCollectionAddress ?? undefined,
    index ?? undefined,
  );

  return {
    ...parseCommonFields(action, options, owner, rawNftAddress),
    slug: TONCOIN.slug,
    nft,
    type: 'mint',
    shouldReload: (isMetadataMissing && RAW_NFT_COLLECTIONS_TO_RELOAD_METADATA.has(action.details.nft_collection))
      || undefined,
  };
}

function isHiddenCollection(rawCollectionAddress: string, metadata: MetadataMap) {
  const collectionMetadata = metadata[rawCollectionAddress]?.token_info[0] as NftCollectionMetadata | undefined;
  return collectionMetadata?.name?.includes('Withdrawal Payout');
}

function parseStakeDeposit(action: StakeDepositAction, options: ParseOptions): ApiTransactionActivity {
  const { details: { stake_holder: holder, pool, amount } } = action;

  return {
    ...parseCommonFields(action, options, holder, pool, amount),
    slug: TONCOIN.slug,
    type: 'stake',
  };
}

function parseStakeWithdrawal(action: StakeWithdrawalAction, options: ParseOptions): ApiTransactionActivity {
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

  return {
    ...parseCommonFields(action, fixedOptions, pool, holder, amount),
    slug: TONCOIN.slug,
    type: 'unstake',
    shouldLoadDetails: details.provider === 'tonstakers' && !details.payout_nft,
  };
}

function parseStakeWithdrawalRequest(
  action: StakeWithdrawalRequestAction,
  options: ParseOptions,
): ApiTransactionActivity {
  const { details: { stake_holder: holder, pool } } = action;

  return {
    ...parseCommonFields(action, options, holder, pool, 0), // TODO (actions) Replace to real fee
    slug: TONCOIN.slug,
    type: 'unstakeRequest',
  };
}

function parseJettonSwap(action: SwapAction, options: ParseOptions): ApiSwapActivity {
  const { metadata, isPending } = options;
  const {
    end_utime: endUtime,
    success: isSuccess,
    details: {
      dex_incoming_transfer: {
        amount: fromAmount,
        asset: fromAsset,
      },
      dex_outgoing_transfer: {
        amount: toAmount,
        asset: toAsset,
      },
    },
  } = action;

  const decimalsFrom = (fromAsset && parseToncenterJetton(fromAsset, metadata)?.decimals) || TONCOIN.decimals;
  const decimalsTo = (toAsset && parseToncenterJetton(toAsset, metadata)?.decimals) || TONCOIN.decimals;

  const fromTokenAddress = fromAsset ? toBase64Address(fromAsset, true) : undefined;
  const toTokenAddress = toAsset ? toBase64Address(toAsset, true) : undefined;

  const from = fromTokenAddress && fromTokenAddress !== STON_PTON_ADDRESS
    ? buildTokenSlug('ton', fromTokenAddress) : TONCOIN.slug;
  const to = toTokenAddress && toTokenAddress !== STON_PTON_ADDRESS
    ? buildTokenSlug('ton', toTokenAddress) : TONCOIN.slug;

  return {
    kind: 'swap',
    id: buildActionActivityId(action),
    timestamp: toMilliseconds(endUtime),
    from,
    fromAmount: toDecimal(BigInt(fromAmount), decimalsFrom),
    to,
    toAmount: toDecimal(BigInt(toAmount), decimalsTo),
    networkFee: '0',
    swapFee: '0',
    ourFee: '0',
    status: isPending ? 'pending' : isSuccess ? 'completed' : 'failed',
    hashes: [],
    externalMsgHashNorm: action.trace_external_hash_norm ?? action.trace_external_hash,
    shouldLoadDetails: true,
  };
}

function parseDns(
  action: ChangeDnsAction | RenewDnsAction | DeleteDnsAction,
  options: ParseOptions,
): ApiTransactionActivity {
  const { metadata, nftSuperCollectionsByCollectionAddress } = options;
  const { details: { source, asset } } = action;

  const { nft } = parseToncenterNft(metadata, asset, nftSuperCollectionsByCollectionAddress);

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

  return {
    ...parseCommonFields(action, options, source, asset, 0), // TODO (actions) Replace to real fee
    slug: TONCOIN.slug,
    type,
    nft,
  };
}

function parseAuctionBid(action: AuctionBidAction, options: ParseOptions): ApiTransactionActivity {
  const { metadata, nftSuperCollectionsByCollectionAddress } = options;
  const { details } = action;

  const {
    bidder,
    auction,
    nft_item_index: index,
    nft_item: rawNftAddress,
    nft_collection: rawCollectionAddress,
  } = details;

  const { nft } = parseToncenterNft(
    metadata,
    rawNftAddress ?? undefined,
    nftSuperCollectionsByCollectionAddress,
    rawCollectionAddress ?? undefined,
    index ?? undefined,
  );

  return {
    ...parseCommonFields(action, options, bidder, auction, details.amount),
    slug: TONCOIN.slug,
    type: 'auctionBid',
    nft,
  };
}

export function parseLiquidityDeposit(
  action: DexDepositLiquidityAction,
  options: ParseOptions,
): ApiTransactionActivity[] {
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

  return activities;
}

function parseLiquidityWithdraw(action: DexWithdrawLiquidityAction, options: ParseOptions): ApiTransactionActivity[] {
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

  return [
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
  const { walletAddress, network, addressBook, isPending } = options;
  const fromAddress = addressBook[rawFromAddress].user_friendly;
  const toAddress = addressBook[rawToAddress].user_friendly;
  const isIncoming = toAddress === walletAddress;
  const normalizedAddress = toBase64Address(isIncoming ? fromAddress : toAddress, true, network);
  const amount = isIncoming ? BigInt(amountString) : -BigInt(amountString);
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
    // Pending actions from Toncenter are not trusted
    status: isPending ? 'pending' : action.success ? 'completed' : 'failed',
  } satisfies Partial<ApiTransactionActivity>;
}

function parseToncenterNft(
  metadataMap: MetadataMap,
  rawNftAddress: string,
  nftSuperCollectionsByCollectionAddress: Record<string, ApiNftSuperCollection>,
  rawCollectionAddress?: string,
  index?: string,
): { nft?: ApiNft; isMetadataMissing?: true } {
  try {
    const nftMetadata = extractMetadata<NftItemMetadata>(rawNftAddress, metadataMap, 'nft_items');

    if (!nftMetadata) {
      return { isMetadataMissing: true };
    }

    const { name, description, extra } = nftMetadata;
    let { image } = nftMetadata;
    const lottie = extra?.lottie ? getProxiedLottieUrl(extra.lottie) : undefined;

    const nftAddress = toBase64Address(rawNftAddress, true);
    const collectionMetadata = rawCollectionAddress
      ? extractMetadata<NftCollectionMetadata>(rawCollectionAddress, metadataMap, 'nft_collections')
      : undefined;
    const collectionAddress = rawCollectionAddress ? toBase64Address(rawCollectionAddress, true) : undefined;

    // TODO (actions) Determine that this is a domain by the collection address once Toncenter adds it
    const domain = extra?.domain ?? name ?? '';
    const { zone: domainZone, base: domainBase } = getDnsDomainZone(domain) ?? {};

    if (domainZone && (!collectionAddress || !image)) {
      if (domainZone.suffixes[0] === 'ton') {
        image = `${DNS_IMAGE_GEN_URL}${domainBase}`;
      }

      const nft = omitUndefined<ApiNft>({
        index: Number(index),
        name: domain,
        address: nftAddress,

        thumbnail: extra?._image_medium ?? image!,
        image: image!,
        description,
        isOnSale: false, // TODO (actions) Replace with real value when Toncenter supports it
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

    const isScam = hasScamLink; // TODO (actions) Replace with real value when Toncenter supports it
    const isHidden = extra?.render_type === 'hidden' || isScam;
    const isFragmentGift = getIsFragmentGift(nftSuperCollectionsByCollectionAddress, collectionAddress);
    const isMtwCard = collectionAddress === MTW_CARDS_COLLECTION;
    const fixedImage = image ? fixIpfsUrl(image) : undefined;

    const thumbnail = extra?._image_medium ?? fixedImage!;

    const nft: ApiNft = omitUndefined<ApiNft>({
      index: Number(index),
      name: name!,
      address: nftAddress,
      thumbnail,
      image: fixedImage!,
      description,
      isOnSale: false, // TODO (actions) Replace with real value when Toncenter supports it
      isHidden,
      metadata: {
        ...(isFragmentGift && {
          fragmentUrl: image!.replace(NFT_FRAGMENT_GIFT_IMAGE_TO_URL_REGEX, 'https://$1'),
        }),
        // `id` must be set to `index + 1`. Unlike TonApi where this field is preformatted,
        // we need to manually adjust it here due to data source differences.
        ...(isMtwCard && buildMtwCardsNftMetadata({
          id: Number(index || 0) + 1, image, attributes: extra?.attributes,
        })),
      },
      ...(collectionAddress && {
        collectionAddress,
        collectionName: collectionMetadata?.name,
        isOnFragment: isFragmentGift || NFT_FRAGMENT_COLLECTIONS.includes(rawCollectionAddress!),
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
    image: jettonMetadata.image!,
    decimals: Number(jettonMetadata.extra!.decimals),
  };
}

function extractMetadata<T extends AnyTokenMetadata>(
  rawAddress: string,
  metadata: MetadataMap,
  type: AnyTokenMetadata['type'],
): T | undefined {
  const data = metadata[rawAddress];
  if (!data || !data.is_indexed) return undefined;
  return data.token_info?.find((tokenInfo) => tokenInfo.type === type) as T;
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
