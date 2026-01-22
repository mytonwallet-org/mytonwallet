import { useMemo } from '../lib/teact/teact';

import type { ApiChain, ApiNft, ApiTokenWithPrice, ApiTransactionActivity } from '../api/types';
import type { Account, SavedAddress } from '../global/types';

import { getIsActivityWithHash, getTransactionAmountDisplayMode, parseTxId } from '../util/activities';
import { getLocalAddressName } from '../util/getLocalAddressName';
import { getNativeToken } from '../util/tokens';
import { getExplorerTransactionUrl } from '../util/url';

interface UseTransactionDetailsOptions {
  transaction?: ApiTransactionActivity;
  tokensBySlug?: Record<string, ApiTokenWithPrice>;
  nftsByAddress?: Record<string, ApiNft>;
  accounts?: Record<string, Account>;
  savedAddresses?: SavedAddress[];
  currentAccountId: string;
  isTestnet?: boolean;
  selectedExplorerIds?: Partial<Record<ApiChain, string>>;
}

export default function useTransactionDetails({
  transaction,
  tokensBySlug,
  nftsByAddress,
  accounts,
  savedAddresses,
  currentAccountId,
  isTestnet,
  selectedExplorerIds,
}: UseTransactionDetailsOptions) {
  const {
    fromAddress,
    toAddress,
    amount,
    comment,
    fee,
    id,
    isIncoming,
    slug,
    nft,
    status,
  } = transaction || {};

  const token = slug ? tokensBySlug?.[slug] : undefined;
  const chain = token?.chain;
  const nativeToken = token ? getNativeToken(token.chain) : undefined;
  const address = isIncoming ? fromAddress : toAddress;
  const isActivityWithHash = Boolean(transaction && getIsActivityWithHash(transaction));
  const transactionHash = chain && id ? parseTxId(id).hash : undefined;
  const doesNftExist = Boolean(nft && nftsByAddress?.[nft.address]);
  const amountDisplayMode = transaction ? getTransactionAmountDisplayMode(transaction) : 'default';

  const localAddressName = useMemo(() => {
    if (!chain || !address) return undefined;

    return getLocalAddressName({
      address,
      chain,
      currentAccountId,
      accounts: accounts!,
      savedAddresses,
    });
  }, [accounts, address, chain, currentAccountId, savedAddresses]);

  const addressName = localAddressName || transaction?.metadata?.name;
  const transactionUrl = chain
    ? getExplorerTransactionUrl(chain, transactionHash, isTestnet, selectedExplorerIds?.[chain])
    : undefined;

  return {
    fromAddress,
    toAddress,
    amount,
    comment,
    fee,
    id,
    isIncoming,
    slug,
    nft,
    status,
    token,
    chain,
    nativeToken,
    address,
    isActivityWithHash,
    transactionHash,
    doesNftExist,
    amountDisplayMode,
    localAddressName,
    addressName,
    transactionUrl,
  };
}
