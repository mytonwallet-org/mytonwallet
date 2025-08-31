import type {
  ApiBalanceBySlug,
  ApiChain, ApiNetwork,
  ApiSwapAsset,
  ApiTokenWithPrice,
} from '../../api/types';
import type { Account, AccountState, AccountType, GlobalState } from '../types';

import {
  APP_NAME, IS_CORE_WALLET, POPULAR_WALLET_VERSIONS, TON_USDT_SLUG, TONCOIN,
} from '../../config';
import isPartialDeepEqual from '../../util/isPartialDeepEqual';
import { getChainBySlug } from '../../util/tokens';
import {
  selectAccount,
  selectAccountOrAuthAccount,
  selectAccountSettings,
  selectAccountState,
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
  addressByChain,
  partial,
  titlePostfix,
  network,
  isMnemonicImported,
}: {
  global: GlobalState;
  accountId: string;
  type: AccountType;
  addressByChain: Account['addressByChain'];
  partial?: Partial<Account>;
  titlePostfix?: string;
  network?: ApiNetwork;
  isMnemonicImported?: boolean;
}) {
  const account: Account = {
    ...partial,
    type,
    addressByChain,
  };
  let shouldForceAccountEdit = true;

  if (!account.title) {
    network = network || selectCurrentNetwork(global);
    const accounts = selectNetworkAccounts(global) || {};
    const accountAmount = Object.keys(accounts).length;
    const isMainnet = network === 'mainnet';

    const viewWalletsCount = Object.values(accounts).filter((acc) => acc.type === 'view').length;
    const regularWalletsCount = accountAmount - viewWalletsCount;

    const titlePrefix = type === 'view'
      ? 'View Wallet'
      : isMainnet ? 'Wallet' : 'Testnet Wallet';
    const postfix = titlePostfix ? ` ${titlePostfix}` : '';

    const count = type === 'view' ? viewWalletsCount + 1 : regularWalletsCount + 1;
    account.title = `${titlePrefix} ${count}${postfix}`;

    if (accountAmount === 0) {
      account.title = isMainnet ? APP_NAME : `Testnet ${APP_NAME}`;
      shouldForceAccountEdit = false;
    }
  } else if (titlePostfix) {
    const title = account.title?.replace(new RegExp(`\\b(${POPULAR_WALLET_VERSIONS.join('|')})\\b`, 'g'), '');
    account.title = `${title.trim()} ${titlePostfix}`;
  }

  if (!IS_CORE_WALLET) {
    global = { ...global, shouldForceAccountEdit };
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

export function renameAccount(global: GlobalState, accountId: string, title: string) {
  return updateAccount(global, accountId, { title });
}

export function createAccountsFromGlobal(global: GlobalState, isMnemonicImported = false): GlobalState {
  const { firstNetworkAccount, secondNetworkAccount } = global.auth;

  global = createAccount({ global, type: 'mnemonic', ...firstNetworkAccount!, isMnemonicImported });
  if (secondNetworkAccount) {
    global = createAccount({ global, type: 'mnemonic', ...secondNetworkAccount, isMnemonicImported });
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

  // Force balance value for USDT-TON and manually imported tokens
  const importedSlugs = selectAccountSettings(global, accountId)?.importedSlugs ?? [];
  // Balance updates may arrive before authentication is complete
  const hasTonWallet = Boolean(selectAccountOrAuthAccount(global, accountId)?.addressByChain?.ton);

  let forcedSlugs = importedSlugs;
  if (hasTonWallet) forcedSlugs = [...forcedSlugs, TON_USDT_SLUG];

  for (const slug of forcedSlugs) {
    if (!(slug in newBalances)) {
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
  if (!partial[TONCOIN.slug].price) {
    partial = Object.values(partial).reduce((result, token) => {
      const existingToken = existingTokens?.[token.slug];

      result[token.slug] = {
        ...token,
        price: existingToken?.price ?? token.price,
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
  return updateAccountState(global, global.currentAccountId!, partial);
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
  return updateAccountSettings(global, global.currentAccountId!, settingsUpdate);
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
