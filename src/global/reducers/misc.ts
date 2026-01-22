import type {
  ApiBalanceBySlug,
  ApiChain,
  ApiCurrencyRates,
  ApiNetwork,
  ApiSwapAsset,
  ApiTokenWithPrice,
} from '../../api/types';
import type { Account, AccountChain, AccountState, AccountType, GlobalState } from '../types';
import { AuthState } from '../types';

import { POPULAR_WALLET_VERSIONS, TONCOIN } from '../../config';
import { generateAccountTitle } from '../../util/account';
import { getDefaultEnabledSlugs } from '../../util/chain';
import isPartialDeepEqual from '../../util/isPartialDeepEqual';
import { getChainBySlug } from '../../util/tokens';
import {
  selectAccount,
  selectAccountOrAuthAccount,
  selectAccountSettings,
  selectAccountState,
  selectCurrentAccountId,
  selectCurrentNetwork,
  selectNetworkAccounts,
} from '../selectors';

export function updateAuth(global: GlobalState, authUpdate: Partial<GlobalState['auth']>) {
  return {
    ...global,
    auth: {
      ...global.auth,
      ...authUpdate,
    },
  } as GlobalState;
}

export function updateAccounts(
  global: GlobalState,
  state: Partial<GlobalState['accounts']>,
) {
  return {
    ...global,
    accounts: {
      ...(global.accounts || { byId: {} }),
      ...state,
    },
  };
}

export function setIsPinAccepted(global: GlobalState): GlobalState {
  return {
    ...global,
    isPinAccepted: true,
  };
}

export function clearIsPinAccepted(global: GlobalState): GlobalState {
  return global.isPinAccepted
    ? { ...global, isPinAccepted: undefined }
    : global;
}

export function createAccount({
  global,
  accountId,
  type,
  byChain,
  partial,
  titlePostfix,
  network,
  isMnemonicImported,
}: {
  global: GlobalState;
  accountId: string;
  type: AccountType;
  byChain: Account['byChain'];
  partial?: Partial<Account>;
  titlePostfix?: string;
  network?: ApiNetwork;
  isMnemonicImported?: boolean;
}) {
  const account: Account = {
    ...partial,
    type,
    byChain,
  };

  if (!account.title) {
    network = network || selectCurrentNetwork(global);
    const accounts = selectNetworkAccounts(global) || {};

    account.title = generateAccountTitle({
      accounts,
      accountType: type,
      network,
      titlePostfix,
    });
  } else if (titlePostfix) {
    const title = account.title?.replace(new RegExp(`\\b(${POPULAR_WALLET_VERSIONS.join('|')})\\b`, 'g'), '');
    account.title = `${title.trim()} ${titlePostfix}`;
  }

  if (selectAccount(global, accountId)) {
    throw new Error(`Account ${accountId} already exists`);
  }

  return {
    ...global,
    accounts: {
      ...global.accounts,
      byId: {
        ...global.accounts?.byId,
        [accountId]: account,
      },
    },
  };
}

export function updateAccount(
  global: GlobalState,
  accountId: string,
  partial: Partial<Account>,
) {
  const account = selectAccount(global, accountId);

  if (!account) {
    throw new Error(`Account ${accountId} doesn't exist`);
  }

  return {
    ...global,
    accounts: {
      ...global.accounts,
      byId: {
        ...global.accounts?.byId,
        [accountId]: {
          ...account,
          ...partial,
        },
      },
    },
  };
}

export function updateAccountChain(
  global: GlobalState,
  accountId: string,
  chain: ApiChain,
  partial: Partial<AccountChain>,
) {
  const account = selectAccount(global, accountId);
  if (!account) {
    throw new Error(`Account ${accountId} doesn't exist`);
  }

  const chainData = account.byChain[chain];
  if (!chainData) {
    throw new Error(`Account ${accountId} doesn't have the ${chain} chain`);
  }

  const updatedAccount = {
    ...account,
    byChain: {
      ...account.byChain,
      [chain]: {
        ...chainData,
        ...partial,
      },
    },
  };

  return {
    ...global,
    accounts: {
      ...global.accounts,
      byId: {
        ...global.accounts?.byId,
        [accountId]: updatedAccount,
      },
    },
  };
}

export function renameAccount(global: GlobalState, accountId: string, title: string) {
  return updateAccount(global, accountId, { title });
}

export function createAccountsFromGlobal(global: GlobalState, isMnemonicImported = false): GlobalState {
  for (const account of global.auth.accounts ?? []) {
    global = createAccount({ global, type: 'mnemonic', ...account, isMnemonicImported });
  }

  return global;
}

export function updateBalances(
  global: GlobalState,
  accountId: string,
  chain: ApiChain,
  chainBalances: ApiBalanceBySlug,
): GlobalState {
  const newBalances: ApiBalanceBySlug = { ...chainBalances };
  const currentBalances = selectAccountState(global, accountId)?.balances?.bySlug ?? {};

  for (const [slug, currentBalance] of Object.entries(currentBalances)) {
    if (getChainBySlug(slug) !== chain) {
      newBalances[slug] = currentBalance;
    }
  }

  const importedSlugs = selectAccountSettings(global, accountId)?.importedSlugs ?? [];
  const network = selectCurrentNetwork(global);

  // Force balance values for the default enabled tokens and manually imported tokens
  for (const slug of [...getDefaultEnabledSlugs(network), ...importedSlugs]) {
    if (getChainBySlug(slug) === chain && !(slug in newBalances)) {
      newBalances[slug] = 0n;
    }
  }

  return updateAccountState(global, accountId, {
    balances: {
      bySlug: newBalances,
    },
  });
}

export function changeBalance(global: GlobalState, accountId: string, slug: string, balance: bigint) {
  return updateAccountState(global, accountId, {
    balances: {
      bySlug: {
        ...selectAccountState(global, accountId)?.balances?.bySlug,
        [slug]: balance,
      },
    },
  });
}

export function updateTokens(
  global: GlobalState,
  partial: Record<string, ApiTokenWithPrice>,
  withDeepCompare = false,
): GlobalState {
  const existingTokens = global.tokenInfo?.bySlug;

  // If the backend does not work, then we won't delete the old prices
  if (!partial[TONCOIN.slug].priceUsd) {
    partial = Object.values(partial).reduce((result, token) => {
      const existingToken = existingTokens?.[token.slug];

      result[token.slug] = {
        ...token,
        priceUsd: existingToken?.priceUsd ?? token.priceUsd,
        percentChange24h: existingToken?.percentChange24h ?? token.percentChange24h,
      };
      return result;
    }, {} as Record<string, ApiTokenWithPrice>);
  }

  if (withDeepCompare && existingTokens && isPartialDeepEqual(existingTokens, partial)) {
    return global;
  }

  return {
    ...global,
    tokenInfo: {
      ...global.tokenInfo,
      bySlug: {
        ...existingTokens,
        ...partial,
      },
    },
  };
}

export function updateSwapTokens(
  global: GlobalState,
  partial: Record<string, ApiSwapAsset>,
): GlobalState {
  const currentTokens = global.swapTokenInfo?.bySlug;

  return {
    ...global,
    swapTokenInfo: {
      ...global.swapTokenInfo,
      bySlug: {
        ...currentTokens,
        ...partial,
      },
      isLoaded: true,
    },
  };
}

export function updateCurrentAccountState(global: GlobalState, partial: Partial<AccountState>): GlobalState {
  return updateAccountState(global, selectCurrentAccountId(global)!, partial);
}

export function updateAccountState(
  global: GlobalState, accountId: string, partial: Partial<AccountState>, withDeepCompare = false,
): GlobalState {
  // Updates from the API may arrive after the account is removed.
  // This check prevents that useless data from persisting in the global state.
  if (!doesAccountExist(global, accountId)) {
    return global;
  }

  const accountState = selectAccountState(global, accountId);

  if (withDeepCompare && accountState && isPartialDeepEqual(accountState, partial)) {
    return global;
  }

  return {
    ...global,
    byAccountId: {
      ...global.byAccountId,
      [accountId]: {
        ...accountState,
        ...partial,
      },
    },
  };
}

export function updateSettings(global: GlobalState, settingsUpdate: Partial<GlobalState['settings']>) {
  return {
    ...global,
    settings: {
      ...global.settings,
      ...settingsUpdate,
    },
  } as GlobalState;
}

export function updateAccountSettings(
  global: GlobalState,
  accountId: string,
  settingsUpdate: Partial<GlobalState['settings']['byAccountId']['*']>,
) {
  // Updates from the API may arrive after the account is removed.
  // This check prevents that useless data from persisting in the global state.
  if (!doesAccountExist(global, accountId)) {
    return global;
  }

  return {
    ...global,
    settings: {
      ...global.settings,
      byAccountId: {
        ...global.settings.byAccountId,
        [accountId]: {
          ...global.settings.byAccountId[accountId],
          ...settingsUpdate,
        },
      },
    },
  } as GlobalState;
}

export function updateCurrentAccountSettings(
  global: GlobalState,
  settingsUpdate: Partial<GlobalState['settings']['byAccountId']['*']>,
) {
  return updateAccountSettings(global, selectCurrentAccountId(global)!, settingsUpdate);
}

export function updateBiometrics(global: GlobalState, biometricsUpdate: Partial<GlobalState['biometrics']>) {
  return {
    ...global,
    biometrics: {
      ...global.biometrics,
      ...biometricsUpdate,
    },
  };
}

export function updateRestrictions(global: GlobalState, partial: Partial<GlobalState['restrictions']>) {
  return {
    ...global,
    restrictions: {
      ...global.restrictions,
      ...partial,
    },
  };
}

export function updateCurrentAccountId(global: GlobalState, accountId: string): GlobalState {
  if (!accountId) {
    throw Error('Empty accountId!');
  }

  return {
    ...global,
    currentAccountId: accountId,
  };
}

function doesAccountExist(global: GlobalState, accountId: string) {
  return !!selectAccountOrAuthAccount(global, accountId);
}

export function updateCurrencyRates(global: GlobalState, rates: ApiCurrencyRates): GlobalState {
  return {
    ...global,
    currencyRates: rates,
  };
}

export function updateCurrentTransactionInfo(
  global: GlobalState,
  partial: Partial<GlobalState['currentTransactionInfo']>,
): GlobalState {
  return {
    ...global,
    currentTransactionInfo: {
      ...global.currentTransactionInfo,
      ...partial,
    },
  };
}

export function resetAuthToStartScreen(global: GlobalState) {
  return updateAuth(global, { state: AuthState.none, error: undefined });
}
