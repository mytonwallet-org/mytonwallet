import type {
  ApiActivity,
  ApiChain,
  ApiSwapActivity,
  ApiTransaction,
  ApiTransactionActivity,
  ApiTransactionType,
} from '../../api/types';
import type { LangFn } from '../langProvider';
import { SwapType } from '../../global/types';

import { ALL_STAKING_POOLS, BURN_ADDRESS } from '../../config';
import { unique } from '../iteratees';
import { getIsTransactionWithPoisoning } from '../poisoningHash';
import { getSwapType } from '../swap/getSwapType';
import { getChainBySlug } from '../tokens';

type UnusualTxType = 'backend-swap' | 'local' | 'additional';

type TranslationTenses = [past: string, present: string, future: string];

const TRANSACTION_TYPE_TITLES: Partial<Record<ApiTransactionType & keyof any, TranslationTenses>> = {
  stake: ['Staked', 'Staking', '$stake_action'],
  unstake: ['Unstaked', 'Unstaking', '$unstake_action'],
  unstakeRequest: ['Requested Unstake', 'Requesting Unstake', '$request_unstake_action'],
  callContract: ['Called Contract', 'Calling Contract', '$call_contract_action'],
  excess: ['Excess', 'Excess', 'Excess'],
  contractDeploy: ['Deployed Contract', 'Deploying Contract', '$deploy_contract_action'],
  bounced: ['Bounced', 'Bouncing', '$bounce_action'],
  mint: ['Minted', 'Minting', '$mint_action'],
  burn: ['Burned', 'Burning', '$burn_action'],
  auctionBid: ['NFT Auction Bid', 'Bidding at NFT Auction', 'NFT Auction Bid '],
  dnsChangeAddress: ['Updated Address', 'Updating Address', '$update_address_action'],
  dnsChangeSite: ['Updated Site', 'Updating Site', '$update_site_action'],
  dnsChangeSubdomains: ['Updated Subdomains', 'Updating Subdomains', '$update_subdomains_action'],
  dnsChangeStorage: ['Updated Storage', 'Updating Storage', '$update_storage_action'],
  dnsDelete: ['Deleted Domain Record', 'Deleting Domain Record', '$delete_domain_record_action'],
  dnsRenew: ['Renewed Domain', 'Renewing Domain', '$renew_domain_action'],
  liquidityDeposit: ['Provided Liquidity', 'Providing Liquidity', '$provide_liquidity_action'],
  liquidityWithdraw: ['Withdrawn Liquidity', 'Withdrawing Liquidity', '$withdraw_liquidity_action'],
};

export const STAKING_TRANSACTION_TYPES = new Set<ApiTransactionType | undefined>([
  'stake', 'unstake', 'unstakeRequest',
]);

export const DNS_TRANSACTION_TYPES = new Set<ApiTransactionType | undefined>([
  'dnsChangeAddress', 'dnsChangeSite', 'dnsChangeStorage', 'dnsChangeSubdomains', 'dnsDelete', 'dnsRenew',
]);

/**
 * Both 'pendingTrusted' and 'pending' mean the activity is awaiting confirmation by the blockchain.
 * - 'pendingTrusted' — awaiting confirmation and trusted (initiated by our app).
 * - 'pending' — awaiting confirmation from an external/unauthenticated source.
 */
const PENDING_STATUSES = new Set(['pending', 'pendingTrusted']);

export function parseTxId(txId: string): {
  hash: string;
  subId?: string;
  type?: UnusualTxType;
} {
  const [hash, subId, type] = txId.split(':') as [string, string | undefined, UnusualTxType | undefined];
  return { hash, type, subId };
}

export function parseNotificationTxId(txId: string): string {
  // Format `lt:hash`
  if (/^\d+:/u.test(txId)) {
    return txId.split(':')[1];
  }

  return txId;
}

export function getIsTxIdLocal(txId: string) {
  return txId.endsWith(':local');
}

export function getIsBackendSwapId(id: string) {
  return id.endsWith(':backend-swap');
}

export function buildBackendSwapId(backendId: string) {
  return buildTxId(backendId, undefined, 'backend-swap');
}

export function buildLocalTxId(hash: string, subId?: number) {
  return buildTxId(hash, subId, 'local');
}

export function buildTxId(hash: string, subId?: number | string, type?: UnusualTxType) {
  if (!type && subId === undefined) return hash;
  if (type === undefined) return `${hash}:${subId}`;
  return `${hash}:${subId ?? ''}:${type}`;
}

/** Returns the token slugs that the activity is a part of the history of */
export function getActivityTokenSlugs(activity: ApiActivity): string[] {
  switch (activity.kind) {
    case 'transaction': {
      if (activity.nft) return []; // We don't want NFT activities to get into any token activity list
      return [activity.slug];
    }
    case 'swap': {
      return [activity.from, activity.to];
    }
  }
}

export function getActivityChains(activity: ApiActivity): ApiChain[] {
  switch (activity.kind) {
    case 'transaction': {
      return [getChainBySlug(activity.slug)];
    }
    case 'swap': {
      return unique([
        getChainBySlug(activity.from),
        getChainBySlug(activity.to),
      ]);
    }
  }
}

export function getIsActivitySuitableForFetchingTimestamp(activity: ApiActivity | undefined) {
  return !!activity
    && !getIsTxIdLocal(activity.id)
    && !getIsBackendSwapId(activity.id)
    && !getIsActivityPending(activity);
}

export function getTransactionTitle(
  { type, isIncoming, nft }: ApiTransaction,
  tense: 'past' | 'present' | 'future',
  translate: LangFn,
) {
  const tenseIndex = tense === 'past' ? 0 : tense === 'present' ? 1 : 2;
  let titles: TranslationTenses;

  if (type === 'nftTrade') {
    titles = isIncoming
      ? ['Sold NFT', 'Selling NFT', '$sell_nft_action']
      : ['Bought NFT', 'Buying NFT', '$buy_nft_action'];
  } else if (type === 'mint' && nft) {
    titles = ['Minted NFT', 'Minting NFT', '$mint_nft_action'];
  } else if (type === 'burn' && nft) {
    titles = ['Burned NFT', 'Burning NFT', '$burn_nft_action'];
  } else if (type && TRANSACTION_TYPE_TITLES[type]) {
    titles = TRANSACTION_TYPE_TITLES[type];
  } else if (nft) {
    titles = isIncoming
      ? ['Received NFT', 'Receiving NFT', '$receive_nft_action']
      : ['Sent NFT', 'Sending NFT', '$send_nft_action'];
  } else {
    titles = isIncoming
      ? ['Received', 'Receiving', '$receive_action']
      : ['Sent', 'Sending', '$send_action'];
  }

  return translate(titles[tenseIndex]);
}

export function isScamTransaction(transaction: ApiTransaction) {
  return Boolean(transaction.metadata?.isScam)
    || Boolean(transaction.nft?.isScam)
    || getIsTransactionWithPoisoning(transaction);
}

// A spam NFT is one the backend marked as hidden, one from an unverified collection (both unless the user
// whitelisted it), or one the user blacklisted. The scam case is covered by `isScamTransaction`.
// An unverified collection is only unknown, not a scam, so it hides what other people sent, not what the user did.
export function getIsHiddenNftActivity(
  transaction: ApiTransaction,
  blacklistedNftAddresses?: string[],
  whitelistedNftAddresses?: string[],
  areUnverifiedNftsHidden?: boolean,
) {
  const { nft, isIncoming, type } = transaction;

  if (!nft) return false;

  if (blacklistedNftAddresses?.includes(nft.address)) return true;

  if (whitelistedNftAddresses?.includes(nft.address)) return false;

  // The user buys and sells on a marketplace themselves, and `isIncoming` shows the TONCOIN direction there
  const isReceivedFromOthers = isIncoming && type !== 'nftTrade';

  return Boolean(nft.isHidden) || Boolean(areUnverifiedNftsHidden && nft.isUnverified && isReceivedFromOthers);
}

export function shouldShowTransactionComment(transaction: ApiTransaction) {
  return Boolean(transaction.comment || transaction.encryptedComment)
    && !STAKING_TRANSACTION_TYPES.has(transaction.type)
    && !isScamTransaction(transaction);
}

export function getTransactionAmountDisplayMode({ type, amount, nft }: ApiTransaction) {
  const isPlainTransfer = type === undefined && !nft;
  if (!amount && !isPlainTransfer) {
    return 'hide';
  }
  return type === 'stake' || type === 'unstake'
    ? 'noSign'
    : 'normal';
}

/** Returns the UI sections where the address should be shown */
export function shouldShowTransactionAddress(transaction: ApiTransactionActivity): ('list' | 'modal')[] {
  const { type, isIncoming, nft, toAddress, fromAddress, extra } = transaction;

  if (type === 'nftTrade') {
    return extra?.marketplace ? ['list'] : [];
  }

  const shouldHide = isOurStakingTransaction(transaction)
    || type === 'burn'
    || (!isIncoming && nft && toAddress === nft.address)
    || (isIncoming && type === 'excess' && fromAddress === BURN_ADDRESS);

  return shouldHide ? [] : ['list', 'modal'];
}

/** "Our" is staking that can be controlled with My Wallet app */
export function isOurStakingTransaction({ type, isIncoming, toAddress, fromAddress }: ApiTransaction) {
  return STAKING_TRANSACTION_TYPES.has(type) && ALL_STAKING_POOLS.includes(isIncoming ? fromAddress : toAddress);
}

export function shouldShowTransactionAnnualYield(transaction: ApiTransaction) {
  return transaction.type === 'stake' && isOurStakingTransaction(transaction);
}

export function getIsActivityWithHash(activity: ApiTransactionActivity) {
  return !getIsTxIdLocal(activity.id) || !activity.extra?.withW5Gasless;
}

export function getIsActivityPending(activity: ApiActivity) {
  // "Pending" is a blockchain term. The activities originated by our backend are never considered pending in this sense.
  return getIsActivityPendingForUser(activity) && !getIsBackendSwapId(activity.id);
}

export function getIsActivityPendingForUser(activity: ApiActivity) {
  return PENDING_STATUSES.has(activity.status);
}

/**
 * If the account has the "from" token chain, the swap "in" transaction has been performed by the app automatically
 * (see the `submitSwapCex` action code). So, if the Сhangelly status is "waiting", the UI shouldn't tell the user that
 * the app is waiting for their payment.
 */
export function getShouldSkipSwapWaitingStatus(
  { from, to }: ApiSwapActivity,
  accountChains: Partial<Record<ApiChain, unknown>>,
) {
  return getSwapType(from, to, accountChains) !== SwapType.CrosschainToWallet;
}
