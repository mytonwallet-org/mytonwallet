import type { ApiChain, ApiStakingState } from '../api/types';
import type { ChainDisplayConfiguration, UserToken } from '../global/types';

import { IS_GRAM_WALLET, TONCOIN } from '../config';
import { getAllSupportedVisibleChains } from './chain';
import { unique } from './iteratees';
import { getFullStakingBalance } from './staking';

export const DEFAULT_CHAIN_DISPLAY_CONFIGURATION: ChainDisplayConfiguration = { displayMode: 'value' };

/**
 * The chains the app shows automatically, until the user changes the list themselves.
 *
 * If the wallet already holds funds, the app shows the chains those funds are in. If the wallet is empty,
 * the app shows every supported chain - otherwise the user would have nowhere to receive their first funds.
 *
 * When the wallet holds funds but none of them are in the account's own chains, only the first chain is shown,
 * matching `automaticallyVisibleChains` on iOS.
 */
export function getDefaultVisibleChains(accountChains: ApiChain[], chainsWithBalance: ReadonlySet<ApiChain>) {
  const availableChains = unique(accountChains);

  if (!chainsWithBalance.size) {
    const supportedChains = getAllSupportedVisibleChains();

    return new Set(availableChains.filter((chain) => supportedChains.has(chain)));
  }

  const fundedChains = availableChains.filter((chain) => chainsWithBalance.has(chain));

  return new Set(fundedChains.length ? fundedChains : availableChains.slice(0, 1));
}

/** Chains holding a non-zero amount of any token, staked balances included */
export function getChainsWithBalance(tokens?: UserToken[], stakingStates?: ApiStakingState[]) {
  const result = new Set<ApiChain>();
  if (!tokens?.length) return result;

  const chainBySlug = new Map(tokens.map((token) => [token.slug, token.chain]));

  for (const token of tokens) {
    if (token.amount > 0n) {
      result.add(token.chain);
    }
  }

  for (const stakingState of stakingStates ?? []) {
    const chain = chainBySlug.get(stakingState.tokenSlug);
    if (chain && getFullStakingBalance(stakingState) > 0n) {
      result.add(chain);
    }
  }

  return result;
}

/**
 * The chains whose addresses the account's address line shows: the visible chains narrowed for Gram Wallet.
 * While a Gram Wallet account's shown token list holds tokens on TON alone (or none at all), the line collapses
 * to the TON address, matching Air (`MAccount.addressLineChains` on iOS, `WMultichainAddressLabel` on Android).
 * Display-only: the address menu, the Receive screen and the share link keep every visible chain.
 * An undefined `hasOnlyTonTokens` means the token list is not known yet, so nothing is hidden.
 */
export function getAddressLineChains(
  chains: ApiChain[],
  hasOnlyTonTokens?: boolean,
  isGramWallet = IS_GRAM_WALLET,
): ApiChain[] {
  if (!isGramWallet || !hasOnlyTonTokens || !chains.includes(TONCOIN.chain)) {
    return chains;
  }

  return [TONCOIN.chain];
}

/** Whether every shown token belongs to the TON chain; undefined while the token list is not known yet */
export function getHasOnlyTonTokens(tokens?: UserToken[]) {
  if (!tokens) return undefined;

  return !tokens.some(({ isDisabled, chain }) => !isDisabled && chain !== TONCOIN.chain);
}

export function getIsChainVisible(
  config: ChainDisplayConfiguration,
  chain: ApiChain,
  defaultVisibleChains: ReadonlySet<ApiChain>,
) {
  if (config.hiddenChains?.includes(chain)) return false;
  if (config.shownChains?.includes(chain)) return true;

  return defaultVisibleChains.has(chain);
}

/**
 * Every chain of the account in the order the Blockchains screen lists them:
 * the shown ones first, the hidden ones after.
 *
 * `defaultOrder` is the chains in the regular app order.
 * `valueOrder` is the same chains sorted by balance.
 */
export function getOrderedChainsForDisplay(
  config: ChainDisplayConfiguration,
  defaultOrder: ApiChain[],
  valueOrder: ApiChain[],
  defaultVisibleChains: ReadonlySet<ApiChain>,
) {
  const availableOrder = unique(defaultOrder);
  const completeValueOrder = buildCompleteValueOrder(availableOrder, valueOrder);

  if (config.displayMode === 'value') {
    return [
      ...completeValueOrder.filter((chain) => defaultVisibleChains.has(chain)),
      ...completeValueOrder.filter((chain) => !defaultVisibleChains.has(chain)),
    ];
  }

  const visibleChains = getNormalizedManualOrder(config, availableOrder, defaultVisibleChains);
  const visibleChainSet = new Set(visibleChains);

  return [...visibleChains, ...completeValueOrder.filter((chain) => !visibleChainSet.has(chain))];
}

/**
 * The stored manual order is a plain list of chain names, so over time it can go stale: some chain gets hidden later,
 * and a chain added to the app afterward is missing from the list entirely.
 *
 * So the hidden chains are dropped from it, and the new ones are appended in the order they show up in the app.
 */
export function getNormalizedManualOrder(
  config: ChainDisplayConfiguration,
  defaultOrder: ApiChain[],
  defaultVisibleChains: ReadonlySet<ApiChain>,
) {
  const availableOrder = unique(defaultOrder);
  const availableChains = new Set(availableOrder);
  const orderedManually = unique(config.manualOrder ?? []).filter((chain) => {
    return availableChains.has(chain) && getIsChainVisible(config, chain, defaultVisibleChains);
  });
  const manuallyOrderedChains = new Set(orderedManually);

  return [
    ...orderedManually,
    ...availableOrder.filter((chain) => {
      return !manuallyOrderedChains.has(chain) && getIsChainVisible(config, chain, defaultVisibleChains);
    }),
  ];
}

/**
 * The chains to show everywhere in the app except the Blockchains screen.
 *
 * The list always holds at least one chain. Otherwise, the wallet would have no address to receive funds at.
 */
export function getVisibleChains(
  config: ChainDisplayConfiguration,
  defaultOrder: ApiChain[],
  valueOrder: ApiChain[],
  defaultVisibleChains: ReadonlySet<ApiChain>,
) {
  const orderedChains = getOrderedChainsForDisplay(config, defaultOrder, valueOrder, defaultVisibleChains);
  const isAutomatic = config.displayMode === 'value';
  const visibleChains = orderedChains.filter((chain) => (isAutomatic
    ? defaultVisibleChains.has(chain)
    : getIsChainVisible(config, chain, defaultVisibleChains)));

  if (visibleChains.length) {
    return visibleChains;
  }

  const fallbackChain = isAutomatic
    ? orderedChains[0]
    : defaultOrder.find((chain) => !config.hiddenChains?.includes(chain)) ?? defaultOrder[0];

  return fallbackChain ? [fallbackChain] : [];
}

export function setChainDisplayMode(
  config: ChainDisplayConfiguration,
  displayMode: ChainDisplayConfiguration['displayMode'],
  capturedOrder?: ApiChain[],
) {
  return buildChainDisplayConfiguration({
    ...config,
    displayMode,
    manualOrder: displayMode === 'manual' && capturedOrder ? capturedOrder : config.manualOrder,
  });
}

/**
 * A switch is stored only when the user changes a chain's visibility by hand.
 *
 * Flipping it back to the default state removes the record, and the chain's visibility is decided by its balance again.
 *
 * For example, a chain hidden now because of a zero balance shows up on its own once funds arrive in it later,
 * with no need to visit the settings again.
 */
export function setChainVisibility(
  config: ChainDisplayConfiguration,
  chain: ApiChain,
  isVisible: boolean,
  isAutomaticallyVisible: boolean,
) {
  const hiddenChains = (config.hiddenChains ?? []).filter((c) => c !== chain);
  const shownChains = (config.shownChains ?? []).filter((c) => c !== chain);

  if (isVisible !== isAutomaticallyVisible) {
    (isVisible ? shownChains : hiddenChains).push(chain);
  }

  return buildChainDisplayConfiguration({
    ...config,
    hiddenChains,
    shownChains,
    manualOrder: isVisible ? config.manualOrder : config.manualOrder?.filter((c) => c !== chain),
  });
}

export function setManualChainOrder(
  config: ChainDisplayConfiguration,
  manualOrder: ApiChain[],
  defaultVisibleChains: ReadonlySet<ApiChain>,
) {
  return buildChainDisplayConfiguration({
    ...config,
    manualOrder: manualOrder.filter((chain) => getIsChainVisible(config, chain, defaultVisibleChains)),
  });
}

export function getIsDefaultChainDisplayConfiguration(config: ChainDisplayConfiguration) {
  return config.displayMode === 'value'
    && !config.hiddenChains?.length
    && !config.shownChains?.length
    && !config.manualOrder?.length;
}

function buildChainDisplayConfiguration(config: ChainDisplayConfiguration): ChainDisplayConfiguration {
  const hiddenChains = unique(config.hiddenChains ?? []);
  const hiddenChainSet = new Set(hiddenChains);
  const shownChains = unique(config.shownChains ?? []).filter((chain) => !hiddenChainSet.has(chain));
  const manualOrder = unique(config.manualOrder ?? []);

  return {
    displayMode: config.displayMode,
    ...(hiddenChains.length > 0 && { hiddenChains }),
    ...(shownChains.length > 0 && { shownChains }),
    ...(manualOrder.length > 0 && { manualOrder }),
  };
}

function buildCompleteValueOrder(availableOrder: ApiChain[], valueOrder: ApiChain[]) {
  const availableChains = new Set(availableOrder);
  const orderedByValue = unique(valueOrder).filter((chain) => availableChains.has(chain));
  const valueOrderedChains = new Set(orderedByValue);

  return [...orderedByValue, ...availableOrder.filter((chain) => !valueOrderedChains.has(chain))];
}
