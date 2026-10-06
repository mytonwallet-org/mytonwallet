import type { ApiChain, ApiDappTransfer, ApiToken } from '../../../api/types';
import type { Account, SavedAddress, UserToken } from '../../../global/types';

import { STON_PTON_SLUG, TONCOIN, UNKNOWN_TOKEN } from '../../../config';
import { getChainConfig } from '../../../util/chain';
import { getTelegramAvatarUrlFromDomain } from '../../../util/dns';
import { findOtherAccountId, findSavedAddressName } from '../../../util/getLocalAddressName';
import { shortenAddress } from '../../../util/shortenAddress';
import { isNftTransferPayload, isTokenTransferPayload } from '../../../util/ton/transfer';

export type ConfirmationAsset =
  | { type: 'token'; token: ApiToken | UserToken; amount: bigint }
  | { type: 'nft'; name?: string; thumbnail?: string };

export type ConfirmationRecipient =
  | { type: 'address'; text: string }
  | { type: 'wallet'; name: string; accountId?: string; imageUrl?: string };

/**
 * Lists what a dApp request sends, one asset per message.
 *
 * A request with hidden transfers, or with a message whose payload could not be parsed, gets no assets at all.
 * Showing only the parsed messages would misrepresent what the request does.
 */
export function getDappTransferAssets(
  transactions: ApiDappTransfer[],
  shouldHideTransfers: boolean | undefined,
  tokensBySlug: Record<string, ApiToken>,
): ConfirmationAsset[] {
  if (shouldHideTransfers || transactions.some((transaction) => transaction.isDangerous)) {
    return [];
  }

  return transactions.map((transaction) => getDappTransferAsset(transaction, tokensBySlug));
}

/**
 * The user's other accounts and saved addresses are shown by name with an avatar. Any other address is shown
 * as text: its domain or a label from the backend when there is one, the shortened address otherwise.
 */
export function getTransferRecipient({
  address, addressName, chain, currentAccountId, accounts, savedAddresses,
}: {
  address: string;
  addressName?: string;
  chain: ApiChain;
  currentAccountId: string;
  accounts?: Record<string, Account>;
  savedAddresses?: SavedAddress[];
}): ConfirmationRecipient {
  const accountId = accounts && findOtherAccountId({ address, chain, currentAccountId, accounts });
  if (accountId) {
    const { title, byChain } = accounts[accountId];

    return {
      type: 'wallet',
      name: title || shortenAddress(address)!,
      accountId,
      imageUrl: getTelegramAvatarUrlFromDomain(byChain.ton?.domain),
    };
  }

  const savedName = savedAddresses && findSavedAddressName({ address, chain, savedAddresses });
  if (savedName) {
    return { type: 'wallet', name: savedName };
  }

  return { type: 'address', text: addressName || shortenAddress(address)! };
}

function getDappTransferAsset(
  { chain, amount, payload }: ApiDappTransfer,
  tokensBySlug: Record<string, ApiToken>,
): ConfirmationAsset {
  if (isNftTransferPayload(payload)) {
    return { type: 'nft', name: payload.nft?.name || payload.nftName, thumbnail: payload.nft?.thumbnail };
  }

  if (isTokenTransferPayload(payload) || payload?.type === 'tokens:burn') {
    const { slug } = payload;

    // pTON is the STON.fi wrapper that lets its routers swap Toncoin as a jetton. The wallet never holds pTON:
    // the swapped Toncoin is attached to the message, so the swap is shown as the Toncoin it spends.
    if (slug === STON_PTON_SLUG) {
      return { type: 'token', token: tokensBySlug[TONCOIN.slug] ?? TONCOIN, amount: payload.amount };
    }

    return {
      type: 'token',
      token: tokensBySlug[slug] ?? { ...UNKNOWN_TOKEN, name: UNKNOWN_TOKEN.symbol, slug, chain },
      amount: payload.amount,
    };
  }

  // Comments, contract calls and other payloads move only the native token attached to the message
  const { nativeToken } = getChainConfig(chain);

  return { type: 'token', token: tokensBySlug[nativeToken.slug] ?? nativeToken, amount };
}
