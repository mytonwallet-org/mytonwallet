import type { ApiChain } from '../../api/types';
import type { GlobalState } from '../types';

import { getChainConfig, getTrustedUsdtSlugs } from '../../util/chain';
import { CHAIN_ORDER } from '../../util/chain';
import { getMaxTransferAmount } from '../../util/fee/transferFee';
import { isValidAddressOrDomain } from '../../util/isValidAddress';
import { orderByPattern } from '../../util/iteratees';
import {
  getOffRampBaselineCurrencies,
  getOnRampBaselineCurrencies,
  hasEffectiveRampCurrency,
} from '../../util/ramp-currencies';
import { getChainBySlug, getIsNativeToken } from '../../util/tokens';
import { selectCurrentAccount } from './accounts';
import {
  selectChainTokenWithMaxBalanceSlow,
  selectCurrentAccountTokenBalance,
  selectCurrentAccountTokens,
} from './tokens';

export function selectCurrentTransferMaxAmount(global: GlobalState) {
  const { currentTransfer } = global;
  const tokenBalance = selectCurrentAccountTokenBalance(global, currentTransfer.tokenSlug);

  const { explainedFee } = currentTransfer;

  const fullFeeTerms = explainedFee?.fullFee?.terms;

  const canTransferFullBalance = explainedFee?.canTransferFullBalance ?? (
    fullFeeTerms === undefined && getIsNativeToken(currentTransfer.tokenSlug)
      ? getChainConfig(getChainBySlug(currentTransfer.tokenSlug)).canTransferFullNativeBalance
      : false
  );

  return getMaxTransferAmount({
    tokenBalance,
    tokenSlug: currentTransfer.tokenSlug,
    fullFee: fullFeeTerms,
    canTransferFullBalance,
  });
}

/**
 * Returns the token slug that should be set to current transfer form to keep the token in sync with the "to" address
 */
export function selectTokenMatchingCurrentTransferAddressSlow(global: GlobalState): string {
  const { tokenSlug: currentTokenSlug, toAddress } = global.currentTransfer;
  const currentChain = getChainBySlug(currentTokenSlug);

  if (!toAddress) {
    return currentTokenSlug;
  }

  const availableChains = selectCurrentAccount(global)?.byChain;
  if (!availableChains) {
    return currentTokenSlug;
  }

  const orderedChains = orderByPattern(
    Object.keys(availableChains) as Array<keyof typeof availableChains>,
    (chain) => chain,
    CHAIN_ORDER,
  );

  // First try to match a chain by the full address, then by the prefix.
  // Because a valid TRON address is a prefix of a valid TON address, and we want to match TRON in this case.
  for (const isCheckingPrefix of [false, true]) {
    for (const chain of orderedChains) {
      if (isValidAddressOrDomain(toAddress, chain, isCheckingPrefix)) {
        if (chain === currentChain) {
          return currentTokenSlug;
        }

        const token = selectBestChainTokenSlow(global, chain, currentTokenSlug);
        if (token) return token.slug;
      }
    }
  }

  // If the address matches no available chain, don't change the selected token
  return currentTokenSlug;
}

/**
 * Returns the best token to use when switching to a new chain:
 * - If the current token is the native token of its chain, prefers the native token of the new chain.
 * - If the current token is USDT, prefers the USDT token of the new chain.
 * - Otherwise, falls back to the token with the highest USD balance.
 */
function selectBestChainTokenSlow(global: GlobalState, chain: ApiChain, currentTokenSlug: string) {
  const currentChain = getChainBySlug(currentTokenSlug);
  const tokens = selectCurrentAccountTokens(global) ?? [];

  if (currentTokenSlug === getChainConfig(currentChain).nativeToken.slug) {
    const nativeTokenSlug = getChainConfig(chain).nativeToken.slug;
    const nativeToken = tokens.find((token) => token.slug === nativeTokenSlug);
    if (nativeToken) return nativeToken;
  }

  if (getTrustedUsdtSlugs().has(currentTokenSlug)) {
    const { usdtSlug } = getChainConfig(chain);
    const usdtToken = tokens.find(
      (token) => token.chain === chain && (token.slug === usdtSlug.mainnet || token.slug === usdtSlug.testnet),
    );
    if (usdtToken) return usdtToken;
  }

  return selectChainTokenWithMaxBalanceSlow(global, chain);
}

export function selectAllowedOnOffRampCurrencies(global: GlobalState) {
  return global.restrictions.allowedOnOffRampCurrencies;
}

/**
 * Both gates take the chain rather than defaulting to "any chain": an entry point that carries no chain of its own
 * still opens one, and a union answer is how a button ends up offered on an account whose click then declines.
 * Chainless callers ask `selectDefaultOnRampChain` first, which is that question asked about the actual account.
 */
export function selectIsOnRampAllowed(global: GlobalState, chain: ApiChain) {
  const { settings: { isTestnet }, restrictions: { isOnRampDisabled, allowedOnOffRampCurrencies } } = global;

  if (isTestnet || isOnRampDisabled) return false;
  if (!getChainConfig(chain).isOnRampSupported) return false;

  return hasEffectiveRampCurrency(getOnRampBaselineCurrencies(chain), allowedOnOffRampCurrencies);
}

export function selectIsOffRampAllowed(global: GlobalState, chain: ApiChain) {
  const { settings: { isTestnet }, restrictions: { isOffRampDisabled, allowedOnOffRampCurrencies } } = global;

  if (isTestnet || isOffRampDisabled) return false;
  if (!getChainConfig(chain).isOffRampSupported) return false;

  return hasEffectiveRampCurrency(getOffRampBaselineCurrencies(chain), allowedOnOffRampCurrencies);
}

/**
 * The chain an entry point that carries no chain of its own ends up buying on: the account's first chain the ramp
 * actually serves. Answering with the first chain outright would hide the button on an account whose leading chain
 * is unserved while a servable one sits further down. Absent means the account has nothing to buy on, which is the
 * only thing such an entry point has to check - it cannot disagree with the click it opens.
 */
export function selectDefaultOnRampChain(global: GlobalState) {
  const byChain = selectCurrentAccount(global)?.byChain;

  return byChain && CHAIN_ORDER.find((chain) => byChain[chain] && selectIsOnRampAllowed(global, chain));
}

/** Off-ramp counterpart of `selectDefaultOnRampChain`, which sells whatever the last transfer was denominated in */
export function selectDefaultOffRampChain(global: GlobalState): ApiChain {
  const { tokenSlug } = global.currentTransfer;

  return tokenSlug ? getChainBySlug(tokenSlug) : 'ton';
}
