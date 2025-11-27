import type { ApiChain } from '../api/types';
import type { Account, UserToken } from '../global/types';

import { getChainConfig } from './chain';
import { getIsNativeToken } from './tokens';

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

  const {
    shouldShowScamWarningIfNotEnoughGas,
    usdtSlug: { mainnet: usdtSlug },
  } = getChainConfig(transferTokenChain);

  // Only show when trying to transfer in some chains
  if (!shouldShowScamWarningIfNotEnoughGas) {
    return false;
  }

  // Check if account has that chain tokens (like USDT)
  return accountTokens.some((token) =>
    token.slug === usdtSlug
    || (token.chain === transferTokenChain && token.amount > 0n && !getIsNativeToken(token.slug)),
  );
}

export function shouldShowDomainScamWarning(address: string) {
  return SCAM_DOMAIN_ADDRESS_REGEX.test(address);
}
