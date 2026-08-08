import type { ApiChain, ApiStakingState } from '../../api/types';
import type { Account, AccountSettings, ChainDisplayConfiguration, GlobalState, UserToken } from '../types';

import { sortChainsByBalance } from '../../util/calculateFullBalance';
import { getOrderedAccountChains } from '../../util/chain';
import {
  DEFAULT_CHAIN_DISPLAY_CONFIGURATION,
  getAddressLineChains,
  getChainsWithBalance,
  getDefaultVisibleChains,
  getHasOnlyTonTokens,
  getOrderedChainsForDisplay,
  getVisibleChains,
} from '../../util/chainDisplay';
import memoize from '../../util/memoize';
import withCache from '../../util/withCache';
import { selectAccount, selectAccountSettings, selectCurrentAccountId } from './accounts';
import { selectAccountStakingStates } from './staking';
import { selectAccountTokens } from './tokens';

const EMPTY_BY_CHAIN: Account['byChain'] = {};

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
  tokens?: UserToken[],
  stakingStates?: ApiStakingState[],
): ChainDisplay => {
  const defaultOrder = getOrderedAccountChains(byChain);
  const valueOrder = sortChainsByBalance(defaultOrder, tokens, stakingStates);
  const defaultVisibleChains = getDefaultVisibleChains(
    defaultOrder,
    getChainsWithBalance(tokens, stakingStates),
  );

  const visibleChains = getVisibleChains(config, defaultOrder, valueOrder, defaultVisibleChains);

  return {
    config,
    defaultOrder,
    orderedChains: getOrderedChainsForDisplay(config, defaultOrder, valueOrder, defaultVisibleChains),
    visibleChains,
    addressLineChains: getAddressLineChains(visibleChains, getHasOnlyTonTokens(tokens)),
    defaultVisibleChains,
  };
}));

export function selectAccountChainDisplay(global: GlobalState, accountId: string): ChainDisplay {
  return selectChainDisplayMemoizedFor(accountId)(
    selectAccount(global, accountId)?.byChain ?? EMPTY_BY_CHAIN,
    selectAccountSettings(global, accountId)?.chainDisplayConfiguration ?? DEFAULT_CHAIN_DISPLAY_CONFIGURATION,
    selectAccountTokens(global, accountId),
    selectAccountStakingStates(global, accountId),
  );
}

export function selectCurrentAccountChainDisplay(global: GlobalState) {
  const accountId = selectCurrentAccountId(global);
  return accountId ? selectAccountChainDisplay(global, accountId) : undefined;
}

/**
 * The address-line chains of each given account, keyed by account id (see `ChainDisplay.addressLineChains`).
 *
 * Suffixed `Slow` because it loops over every account, which is too much work for a `mapStateToProps`.
 * Call it from a container's `useMemo` that already holds the account tokens instead.
 */
export function selectMultipleAccountsAddressLineChainsSlow(
  accounts: Record<string, Account>,
  settingsByAccountId: Record<string, AccountSettings>,
  tokensByAccountId: Record<string, UserToken[] | undefined>,
  stakingStatesByAccountId: Record<string, ApiStakingState[] | undefined>,
) {
  const result: Record<string, ApiChain[]> = {};

  for (const accountId in accounts) {
    result[accountId] = selectChainDisplayMemoizedFor(accountId)(
      accounts[accountId].byChain,
      settingsByAccountId[accountId]?.chainDisplayConfiguration ?? DEFAULT_CHAIN_DISPLAY_CONFIGURATION,
      tokensByAccountId[accountId],
      stakingStatesByAccountId[accountId],
    ).addressLineChains;
  }

  return result;
}
