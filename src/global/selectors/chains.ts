import type { ApiBalanceBySlug, ApiChain, ApiStakingState } from '../../api/types';
import type { Account, AccountSettings, ChainDisplayConfiguration, GlobalState } from '../types';

import { getOrderedAccountChains } from '../../util/chain';
import {
  type AccountChainSummary,
  buildAccountChainSummary,
  DEFAULT_CHAIN_DISPLAY_CONFIGURATION,
  getAddressLineChains,
  getDefaultVisibleChains,
  getOrderedChainsForDisplay,
  getVisibleChains,
} from '../../util/chainDisplay';
import { areSortedArraysEqual } from '../../util/iteratees';
import memoize from '../../util/memoize';
import { buildTokenVisibilityOptions } from '../../util/tokens';
import withCache from '../../util/withCache';
import { selectAccount, selectAccountSettings, selectAccountState, selectCurrentAccountId } from './accounts';
import { selectAccountStakingStates } from './staking';
import { getHasConfirmedActivities, selectAccountTokenInfoMemoizedFor } from './tokens';

const EMPTY_BY_CHAIN: Account['byChain'] = {};
const EMPTY_BALANCES: ApiBalanceBySlug = {};

export interface ChainDisplay {
  config: ChainDisplayConfiguration;
  /** Every chain of the account, in the app display order and regardless of the settings */
  defaultOrder: ApiChain[];
  /** The same chains in the order the Blockchains screen lists them: the shown ones first, the hidden ones after */
  orderedChains: ApiChain[];
  /** The chains the app shows outside the address rows: the address menu, the share link */
  visibleChains: ApiChain[];
  /** The chains the address rows show: `visibleChains` narrowed by the Gram Wallet gate (see `getAddressLineChains`) */
  addressLineChains: ApiChain[];
  /** The chains that would be shown if the user had not flipped any switch - needed to interpret those switches */
  defaultVisibleChains: ReadonlySet<ApiChain>;
}

// The `accountId` parameter is unused inside the body but acts as the `withCache` key - it gives
// each account its own `memoize` so switching `A → B → A` keeps `A`'s cached result intact
const selectChainDisplayMemoizedFor = withCache((accountId: string) => memoize((
  byChain: Account['byChain'],
  config: ChainDisplayConfiguration,
  summary: AccountChainSummary,
): ChainDisplay => {
  const defaultOrder = getOrderedAccountChains(byChain);
  const { valueOrder, chainsWithBalance, hasOnlyTonTokens } = summary;
  const defaultVisibleChains = getDefaultVisibleChains(defaultOrder, chainsWithBalance);
  const visibleChains = getVisibleChains(config, defaultOrder, valueOrder, defaultVisibleChains);

  return {
    config,
    defaultOrder,
    orderedChains: getOrderedChainsForDisplay(config, defaultOrder, valueOrder, defaultVisibleChains),
    visibleChains,
    addressLineChains: getAddressLineChains(visibleChains, hasOnlyTonTokens),
    defaultVisibleChains,
  };
}));

// Every price tick replaces `tokenInfo`, so the summary is rebuilt often. It is compared by value and the previous
// object is kept while the chain order and funding stay the same, so `selectChainDisplayMemoizedFor` keyed by it
// does not recompute
const selectAccountChainSummaryMemoizedFor = withCache((accountId: string) => {
  let lastSummary: AccountChainSummary | undefined;

  return memoize((
    byChain: Account['byChain'],
    balancesBySlug: ApiBalanceBySlug | undefined,
    tokenInfo: GlobalState['tokenInfo'],
    accountSettings: AccountSettings | undefined,
    areTokensWithNoCostHidden: boolean | undefined,
    hasActivities: boolean,
    stakingStates: ApiStakingState[] | undefined,
  ): AccountChainSummary => {
    const visibility = buildTokenVisibilityOptions(
      accountId,
      balancesBySlug ?? EMPTY_BALANCES,
      tokenInfo.bySlug,
      accountSettings,
      areTokensWithNoCostHidden,
      hasActivities,
    );
    const summary = buildAccountChainSummary(
      getOrderedAccountChains(byChain),
      balancesBySlug,
      tokenInfo.bySlug,
      stakingStates,
      visibility,
    );

    if (lastSummary && areChainSummariesEqual(lastSummary, summary)) {
      return lastSummary;
    }

    lastSummary = summary;
    return summary;
  });
});

export function selectAccountChainDisplay(global: GlobalState, accountId: string): ChainDisplay {
  return selectChainDisplayMemoizedFor(accountId)(
    selectAccount(global, accountId)?.byChain ?? EMPTY_BY_CHAIN,
    selectAccountSettings(global, accountId)?.chainDisplayConfiguration ?? DEFAULT_CHAIN_DISPLAY_CONFIGURATION,
    selectAccountChainSummary(global, accountId),
  );
}

export function selectCurrentAccountChainDisplay(global: GlobalState) {
  const accountId = selectCurrentAccountId(global);
  return accountId ? selectAccountChainDisplay(global, accountId) : undefined;
}

/**
 * The address-line chains of each given account, keyed by account id (see `ChainDisplay.addressLineChains`).
 *
 * Suffixed `Slow` because it loops over every given account, which is too much work for a `mapStateToProps`.
 * Call it from a container's `useMemo` with `accounts` narrowed to the accounts actually rendered.
 */
export function selectMultipleAccountsAddressLineChainsSlow(
  accounts: Record<string, Account>,
  byAccountId: GlobalState['byAccountId'],
  tokenInfo: GlobalState['tokenInfo'],
  settingsByAccountId: Record<string, AccountSettings>,
  areTokensWithNoCostHidden: boolean | undefined,
  stakingStatesByAccountId: Record<string, ApiStakingState[] | undefined>,
) {
  const result: Record<string, ApiChain[]> = {};

  for (const accountId in accounts) {
    const { byChain } = accounts[accountId];
    const accountState = byAccountId[accountId];
    const accountSettings = settingsByAccountId[accountId];
    const balancesBySlug = accountState?.balances?.bySlug;
    const summary = selectAccountChainSummaryMemoizedFor(accountId)(
      byChain,
      balancesBySlug,
      selectAccountTokenInfoMemoizedFor(accountId)(balancesBySlug, tokenInfo),
      accountSettings,
      areTokensWithNoCostHidden,
      getHasConfirmedActivities(accountState?.activities),
      stakingStatesByAccountId[accountId],
    );

    result[accountId] = selectChainDisplayMemoizedFor(accountId)(
      byChain,
      accountSettings?.chainDisplayConfiguration ?? DEFAULT_CHAIN_DISPLAY_CONFIGURATION,
      summary,
    ).addressLineChains;
  }

  return result;
}

function selectAccountChainSummary(global: GlobalState, accountId: string) {
  const accountState = selectAccountState(global, accountId);
  const balancesBySlug = accountState?.balances?.bySlug;

  return selectAccountChainSummaryMemoizedFor(accountId)(
    selectAccount(global, accountId)?.byChain ?? EMPTY_BY_CHAIN,
    balancesBySlug,
    selectAccountTokenInfoMemoizedFor(accountId)(balancesBySlug, global.tokenInfo),
    selectAccountSettings(global, accountId),
    global.settings.areTokensWithNoCostHidden,
    getHasConfirmedActivities(accountState?.activities),
    selectAccountStakingStates(global, accountId),
  );
}

function areChainSummariesEqual(a: AccountChainSummary, b: AccountChainSummary) {
  return a.hasOnlyTonTokens === b.hasOnlyTonTokens
    && areSortedArraysEqual(a.valueOrder, b.valueOrder)
    && a.chainsWithBalance.size === b.chainsWithBalance.size
    && [...a.chainsWithBalance].every((chain) => b.chainsWithBalance.has(chain));
}
