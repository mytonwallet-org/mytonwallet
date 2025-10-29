import type { ApiChain } from '../api/types';
import type { Account, UserToken } from '../global/types';

import { TRC20_USDT_MAINNET_SLUG, TRX } from '../config';

const SCAM_DOMAIN_ADDRESS_REGEX = /^[-\w]{26,}\./;

export function shouldShowSeedPhraseScamWarning(
  account: Account,
  accountTokens: UserToken[],
  transferTokenChain: ApiChain,
): boolean {
  // For multisig accounts a warning should always be shown
  if (account?.byChain[transferTokenChain]?.isMultisig) {
    return true;
  }

  // Only show when trying to transfer TRON tokens
  if (transferTokenChain !== 'tron') {
    return false;
  }

  // Check if account has TRON tokens (like USDT)
  return accountTokens.some((token) =>
    token.slug === TRC20_USDT_MAINNET_SLUG
    || (token.chain === 'tron' && token.amount > 0n && token.slug !== TRX.slug),
  );
}

export function shouldShowDomainScamWarning(address: string) {
  return SCAM_DOMAIN_ADDRESS_REGEX.test(address);
}
