import { getIsHeavyAnimating, onFullyIdle } from '../lib/teact/teact';
import { addCallback, removeCallback } from '../lib/teact/teactn';

import type { ApiActivity, ApiChain } from '../api/types';
import type {
  Account,
  AccountState,
  GlobalState,
  SavedAddress,
  TokenPeriod,
} from './types';
import {
  StakingState,
} from './types';

import {
  DEBUG,
  GLOBAL_STATE_CACHE_DISABLED,
  GLOBAL_STATE_CACHE_KEY,
  IS_CAPACITOR,
  MAIN_ACCOUNT_ID,
  TONCOIN,
} from '../config';
import { buildAccountId, parseAccountId } from '../util/account';
import { getActivityTokenSlugs, getIsActivityPending, getIsTxIdLocal } from '../util/activities';
import { bigintReviver } from '../util/bigint';
import { getTokenInfo } from '../util/chain';
import isEmptyObject from '../util/isEmptyObject';
import {
  cloneDeep, extractKey, filterValues, mapValues, omit, pick, pickTruthy, unique,
} from '../util/iteratees';
import {
  clearPoisoningCache,
  updatePoisoningCacheFromGlobalState,
} from '../util/poisoningHash';
import { onBeforeUnload, throttle } from '../util/schedulers';
import { getIsActiveStakingState } from '../util/staking';
import { IS_ELECTRON } from '../util/windowEnvironment';
import { addActionHandler, getGlobal } from './index';
import { INITIAL_STATE, STATE_VERSION } from './initialState';
import { selectAccountState, selectAccountTokens } from './selectors';

const UPDATE_THROTTLE = IS_CAPACITOR ? 500 : 5000;
const ACTIVITIES_LIMIT = 20;
const ACTIVITY_TOKENS_LIMIT = 30;
const STAKING_HISTORY_LIMIT = 30;

const updateCacheThrottled = throttle(() => onFullyIdle(() => updateCache()), UPDATE_THROTTLE, false);
const updateCacheForced = () => updateCache(true);

let isCaching = false;
let unsubscribeFromBeforeUnload: NoneToVoidFunction | undefined;
let preloadedData: Partial<GlobalState> | undefined;

export function initCache() {
  if (GLOBAL_STATE_CACHE_DISABLED) {
    return;
  }

  addActionHandler('afterSignIn', setupCaching);

  addActionHandler('afterSignOut', (global, actions, payload) => {
    clearPoisoningCache();

    if (payload?.shouldReset) {
      preloadedData = pick(global, ['swapTokenInfo', 'tokenInfo', 'restrictions']);
      clearCaching();
      localStorage.removeItem(GLOBAL_STATE_CACHE_KEY);
    }
  });

  addActionHandler('cancelCaching', clearCaching);
}

function setupCaching() {
  if (isCaching) return;

  isCaching = true;

  addCallback(updateCacheThrottled);
  unsubscribeFromBeforeUnload = onBeforeUnload(updateCacheForced, true);
  window.addEventListener('blur', updateCacheForced);

  updateCacheForced();
}

function clearCaching() {
  if (!isCaching) return;

  window.removeEventListener('blur', updateCacheForced);
  unsubscribeFromBeforeUnload?.();
  removeCallback(updateCacheThrottled);

  isCaching = false;
}

export function loadCache(initialState: GlobalState): GlobalState {
  if (GLOBAL_STATE_CACHE_DISABLED) {
    return initialState;
  }

  if (DEBUG) {
    // eslint-disable-next-line no-console
    console.time('global-state-cache-read');
  }

  const json = localStorage.getItem(GLOBAL_STATE_CACHE_KEY);
  let cached = json ? JSON.parse(json, bigintReviver) as GlobalState : undefined;

  if (DEBUG) {
    // eslint-disable-next-line no-console
    console.timeEnd('global-state-cache-read');
  }

  if (cached) {
    try {
      migrateCache(cached, initialState);
      loadMemoryCache(cached);
    } catch (err) {
      // eslint-disable-next-line no-console
      console.error(err);

      cached = undefined;
    }
  }

  return {
    ...initialState,
    ...preloadedData,
    ...cached,
  };
}

function migrateCache(cached: GlobalState, initialState: GlobalState) {
  // Pre-fill settings with defaults
  cached.settings = {
    ...initialState.settings,
    ...cached.settings,
  };

  if (cached.stateVersion === STATE_VERSION) {
    return;
  }

  // Migration to multi-accounts
  if (!cached.byAccountId) {
    (cached as any).accounts = {
      byId: {
        [MAIN_ACCOUNT_ID]: {
          address: (cached as any).addresses.byAccountId[MAIN_ACCOUNT_ID],
          title: 'Main Account',
        },
      },
    };

    delete (cached as any).addresses;

    cached.byAccountId = {};
    cached.byAccountId[MAIN_ACCOUNT_ID] = {
      isBackupRequired: Boolean((cached as any).isBackupRequired),
      currentTokenSlug: (cached as any).currentTokenSlug as string,
      currentTokenPeriod: (cached as any).currentTokenPeriod as TokenPeriod,
    };

    if ('balances' in cached) {
      cached.byAccountId[MAIN_ACCOUNT_ID].balances = (cached as any).balances.byAccountId[MAIN_ACCOUNT_ID];
      delete (cached as any).balances;
    }

    if ('transactions' in cached) {
      (cached.byAccountId[MAIN_ACCOUNT_ID] as any).transactions = (cached as any).transactions;
      delete (cached as any).transactions;
    }

    if ('nfts' in cached) {
      cached.byAccountId[MAIN_ACCOUNT_ID].nfts = (cached as any).nfts;
      delete (cached as any).nfts;
    }

    if ('savedAddresses' in cached) {
      cached.byAccountId[MAIN_ACCOUNT_ID].savedAddresses = (cached as any).savedAddresses;
      delete (cached as any).savedAddresses;
    }

    if ('backupWallet' in cached) {
      delete (cached as any).backupWallet;
    }
  }

  if (
    (!cached.currentAccountId || !cached.byAccountId[cached.currentAccountId]) && Object.keys(cached.byAccountId).length
  ) {
    cached.currentAccountId = Object.keys(cached.byAccountId)[0];
  }

  // Initializing the v1
  if (!cached.stateVersion && cached.accounts && !isEmptyObject(cached.accounts)) {
    cached.stateVersion = 1;
  }

  if (cached.stateVersion === 1) {
    cached.stateVersion = 2;

    if (cached.tokenInfo?.bySlug) {
      cached.tokenInfo.bySlug = {
        toncoin: {
          ...cached.tokenInfo.bySlug.toncoin,
          decimals: TONCOIN.decimals,
        },
      };
    }

    if (cached.byAccountId) {
      Object.values(cached.byAccountId).forEach((accountState) => {
        if (accountState.balances?.bySlug) {
          accountState.balances.bySlug = pick(accountState.balances.bySlug, ['toncoin']);
        }
        if ((accountState as any).transactions) {
          delete (accountState as any).transactions;
        }
      });
    }
  }

  if (cached.stateVersion === 2) {
    cached.stateVersion = 3;

    // Normalization of MAIN_ACCOUNT_ID '0' => '0-ton-mainnet'
    const oldId = '0';
    const newId = MAIN_ACCOUNT_ID;
    if (cached.accounts && oldId in cached.accounts.byId) {
      if (cached.currentAccountId === oldId) {
        cached.currentAccountId = newId;
      }
      cached.accounts.byId[newId] = cached.accounts.byId[oldId];
      delete cached.accounts.byId[oldId];
      cached.byAccountId[newId] = cached.byAccountId[oldId];
      delete cached.byAccountId[oldId];
    }

    // Add testnet accounts
    if (cached.accounts) {
      for (const accountId of Object.keys(cached.accounts.byId)) {
        const testnetAccountId = buildAccountId({
          ...parseAccountId(accountId),
          network: 'testnet',
        });
        cached.accounts.byId[testnetAccountId] = cloneDeep(cached.accounts.byId[accountId]);
        cached.byAccountId[testnetAccountId] = {};
      }
    }
  }

  if (cached.stateVersion === 3) {
    cached.stateVersion = 4;

    if (cached.byAccountId) {
      for (const accountId of Object.keys(cached.byAccountId)) {
        delete (cached.byAccountId[accountId] as any).transactions;
      }
    }
  }

  if (cached.stateVersion === 4) {
    cached.stateVersion = 5;

    (cached as any).staking = {
      state: StakingState.None,
    };
  }

  if (cached.stateVersion === 5) {
    cached.stateVersion = 6;

    if (cached.byAccountId) {
      for (const accountId of Object.keys(cached.byAccountId)) {
        delete (cached.byAccountId[accountId] as any).transactions;
      }
    }
  }

  if (cached.stateVersion === 6) {
    cached.stateVersion = 7;

    if (cached.byAccountId) {
      for (const accountId of Object.keys(cached.byAccountId)) {
        delete (cached.byAccountId[accountId] as any).transactions;
      }
    }
  }

  if (cached.stateVersion === 7) {
    if (cached.byAccountId) {
      for (const accountId of Object.keys(cached.byAccountId)) {
        delete (cached.byAccountId[accountId] as any).backupWallet;
      }
    }

    cached.stateVersion = 8;
  }

  if (cached.stateVersion === 8) {
    if (cached.settings && IS_ELECTRON) {
      cached.settings.isDeeplinkHookEnabled = true;
    }

    cached.stateVersion = 9;
  }

  function clearActivities() {
    if (cached.byAccountId) {
      for (const accountId of Object.keys(cached.byAccountId)) {
        delete (cached.byAccountId[accountId] as any).activities;
      }
    }
  }

  if (cached.stateVersion === 9) {
    clearActivities();
    cached.stateVersion = 10;
  }

  if (cached.stateVersion === 10) {
    if ((cached.settings as any).areTokensWithNoBalanceHidden === undefined) {
      (cached.settings as any).areTokensWithNoBalanceHidden = true;
    }
    cached.stateVersion = 11;
  }

  if (cached.stateVersion === 11) {
    clearActivities();
    cached.stateVersion = 12;
  }

  if (cached.stateVersion === 12) {
    if (cached.byAccountId) {
      for (const accountId of Object.keys(cached.byAccountId)) {
        delete cached.byAccountId[accountId].activities;

        const { balances } = cached.byAccountId[accountId];
        if (balances) {
          balances.bySlug = Object.entries(balances.bySlug).reduce((acc, [slug, balance]) => {
            acc[slug] = BigInt(balance);
            return acc;
          }, {} as Record<string, bigint>);
        }
      }
    }
    cached.stateVersion = 13;
  }

  if (cached.stateVersion === 13) {
    const { areTokensWithNoPriceHidden, areTokensWithNoBalanceHidden } = cached.settings as any as {
      areTokensWithNoPriceHidden?: boolean;
      areTokensWithNoBalanceHidden?: boolean;
    };

    cached.settings.areTokensWithNoCostHidden = Boolean(areTokensWithNoPriceHidden || areTokensWithNoBalanceHidden);
    cached.stateVersion = 14;
  }

  if (cached.stateVersion >= 14 && cached.stateVersion <= 17) {
    clearActivities();
    cached.stateVersion = 18;
  }

  if (cached.stateVersion === 18 || cached.stateVersion === 19) {
    for (const accountId of Object.keys(cached.byAccountId)) {
      cached.byAccountId[accountId].currentTokenPeriod = '1D';
    }
    cached.stateVersion = 20;
  }

  if (cached.stateVersion >= 20 && cached.stateVersion <= 22) {
    clearActivities();
    cached.stateVersion = 23;
  }

  if (cached.stateVersion === 23) {
    // Removed: isSortByValueEnabled initialization (deprecated in v50)
    cached.stateVersion = 24;
  }

  if (cached.stateVersion === 24) {
    if (cached.accounts) {
      clearActivities();
      for (const account of Object.values(cached.accounts.byId)) {
        (account as any).addressByChain = { ton: (account as any).address };
        delete (account as any).address;
      }
    }
    cached.stateVersion = 25;
  }

  if (cached.stateVersion === 25) {
    if (cached.byAccountId) {
      for (const accountId of Object.keys(cached.byAccountId)) {
        const savedAddresses = cached.byAccountId[accountId].savedAddresses;
        if (savedAddresses && !('length' in savedAddresses)) {
          cached.byAccountId[accountId].savedAddresses = Object.keys(savedAddresses as Record<string, string>)
            .map((address) => ({
              name: savedAddresses[address],
              address,
              chain: 'ton',
            } as SavedAddress));
        }
      }
    }
    cached.stateVersion = 26;
  }

  if (cached.stateVersion === 26) {
    clearActivities();
    cached.stateVersion = 27;
  }

  if (cached.stateVersion === 27) {
    delete (cached.settings as any).dapps;
    cached.stateVersion = 28;
  }

  if (cached.stateVersion === 28) {
    const accountIds = Object.keys(cached.settings.byAccountId);
    for (const accountId of accountIds) {
      const exceptionSlugs = (cached.settings.byAccountId[accountId] as any).exceptionSlugs as string[] | undefined;
      if (cached.settings.areTokensWithNoCostHidden) {
        cached.settings.byAccountId[accountId].alwaysShownSlugs = exceptionSlugs;
      } else {
        cached.settings.byAccountId[accountId].alwaysHiddenSlugs = exceptionSlugs;
      }
    }
    cached.stateVersion = 29;
  }

  if (cached.stateVersion === 29) {
    cached.currentTransfer.tokenSlug = TONCOIN.slug;
    cached.stateVersion = 30;
  }

  if (cached.stateVersion === 30) {
    clearActivities();
    cached.stateVersion = 31;
  }

  if (cached.stateVersion === 31) {
    if (cached.settings.autolockValue && cached.settings.autolockValue !== 'never') {
      cached.settings.isAppLockEnabled = true;
    }
    cached.stateVersion = 32;
  }

  if (cached.stateVersion >= 32 && cached.stateVersion <= 35) {
    clearActivities();
    cached.stateVersion = 36;
  }

  if (cached.stateVersion === 36) {
    for (const account of Object.values(cached.accounts?.byId ?? {})) {
      account.type = (account as { isHardware?: boolean }).isHardware ? 'hardware' : 'mnemonic';
      delete (account as { isHardware?: boolean }).isHardware;
    }
    cached.stateVersion = 37;
  }

  if (cached.stateVersion === 37) {
    for (const token of Object.values(cached.tokenInfo.bySlug) as any[]) {
      if (!token.price) token.price = 0;
      if (!token.percentChange24h) token.percentChange24h = 0;
      if (!token.priceUsd) token.priceUsd = 0;
      if (token.quote) delete token.quote;
    }
    cached.stateVersion = 38;
  }

  if (cached.stateVersion >= 38 && cached.stateVersion <= 41) {
    clearActivities();
    cached.stateVersion = 42;
  }

  if (cached.stateVersion === 41) {
    for (const accountId of Object.keys(cached.byAccountId)) {
      const accountState = cached.byAccountId[accountId];
      if ((accountState as any).dappLastOpenedDatesByOrigin) {
        accountState.dappLastOpenedDatesByUrl = (accountState as any).dappLastOpenedDatesByOrigin;
        delete (accountState as any).dappLastOpenedDatesByOrigin;
      }
    }
    cached.stateVersion = 42;
  }

  if (cached.stateVersion >= 42 && cached.stateVersion <= 44) {
    clearActivities();
    cached.stateVersion = 45;
  }

  if (cached.stateVersion === 45) {
    clearActivities();

    if (cached.accounts) {
      for (const _account of Object.values(cached.accounts.byId)) {
        const account = _account as Account & {
          addressByChain?: Partial<Record<ApiChain, string>>;
          domainByChain?: Partial<Record<ApiChain, string>>;
          isMultisigByChain?: Partial<Record<ApiChain, boolean>>;
        };

        if (account.byChain) continue; // The migration has passed already

        account.byChain = mapValues(account.addressByChain ?? {}, (address, chain) => ({
          address,
          domain: account.domainByChain?.[chain as ApiChain],
          isMultisig: account.isMultisigByChain?.[chain as ApiChain] || undefined,
        }));

        delete account.addressByChain;
        delete account.domainByChain;
        delete account.isMultisigByChain;
      }
    }

    cached.stateVersion = 46;
  }

  if (cached.stateVersion === 46) {
    if (cached.accounts) {
      for (const _account of Object.values(cached.accounts.byId)) {
        const account = _account as Account & {
          ledger?: { index: number };
          byChain: { ton?: { ledgerIndex?: number } };
        };

        if (
          account.type !== 'hardware'
          || !account.byChain.ton
          || !account.ledger // Already migrated
        ) continue;

        account.byChain.ton.ledgerIndex = account.ledger.index;
        delete account.ledger;
      }
    }

    cached.stateVersion = 47;
  }

  if (cached.stateVersion === 47) {
    cached.pushNotifications.enabledAccounts = Object.keys(cached.pushNotifications.enabledAccounts ?? {});
    cached.stateVersion = 48;
  }

  if (cached.stateVersion <= 49) {
    // Android app specific migration
    cached.stateVersion = 50;
  }

  if (cached.stateVersion === 49) {
    // Initialize pinnedSlugs for all accounts
    if (cached.settings?.byAccountId) {
      Object.values(cached.settings.byAccountId).forEach((accountSettings) => {
        if (accountSettings && !accountSettings.pinnedSlugs) {
          accountSettings.pinnedSlugs = [];
        }
      });
    }

    // Remove global isSortByValueEnabled
    if (cached.settings && 'isSortByValueEnabled' in cached.settings) {
      const { isSortByValueEnabled: _, ...restSettings } = cached.settings as any;
      cached.settings = restSettings;
    }

    cached.stateVersion = 50;
  }

  if (cached.stateVersion === 50) {
    clearActivities();
    cached.stateVersion = 51;
  }

  if (cached.stateVersion === 51) {
    if (cached.byAccountId && cached.settings?.byAccountId) {
      for (const accountId of Object.keys(cached.byAccountId)) {
        const accountState = cached.byAccountId[accountId];
        const stateById = accountState.staking?.stateById;
        if (!stateById) continue;

        const stakingSlugs = Object.values(stateById)
          .filter((state: any) => state?.tokenSlug)
          .map((state: any) => `staking-${state.tokenSlug}`);

        if (stakingSlugs.length > 0) {
          const accountSettings = cached.settings.byAccountId[accountId] ??= {} as any;
          const { pinnedSlugs = [] } = accountSettings;
          accountSettings.pinnedSlugs = unique([...stakingSlugs, ...pinnedSlugs]);
        }
      }
    }

    cached.stateVersion = 52;
  }
  if (cached.stateVersion === 52) {
    if (cached.byAccountId) {
      for (const accountId of Object.keys(cached.byAccountId)) {
        if (cached.byAccountId[accountId]?.nfts?.collectionTabs) {
          cached.byAccountId[accountId].nfts.collectionTabs = cached.byAccountId[accountId].nfts.collectionTabs
            ?.map((e) => typeof e === 'string' ? { address: e, chain: 'ton' } : e) || [];
        }
      }
    }
    cached.stateVersion = 53;
  }
  // When adding migration here, increase `STATE_VERSION`
}

function loadMemoryCache(cached: GlobalState) {
  updatePoisoningCacheFromGlobalState(cached);
}

const getUsedTokenSlugs = (reducedGlobal: GlobalState): string[] => {
  const usedTokenSlugs = new Set<string>(Object.keys(getTokenInfo()));

  if (reducedGlobal.currentAccountId) {
    const currentTokenSlug = reducedGlobal.byAccountId[reducedGlobal.currentAccountId]?.currentTokenSlug;
    if (currentTokenSlug) {
      usedTokenSlugs.add(currentTokenSlug);
    }
  }

  Object.values(reducedGlobal.byAccountId).forEach((state) => {
    const { balances, activities, staking } = state;

    Object.keys(balances?.bySlug ?? {}).forEach((slug) => usedTokenSlugs.add(slug));
    Object.keys(activities?.byId ?? {}).forEach((transactionId) => {
      getActivityTokenSlugs(activities!.byId[transactionId]).forEach((slug) => usedTokenSlugs.add(slug));
    });
    Object.keys(activities?.idsBySlug ?? {}).forEach((slug) => usedTokenSlugs.add(slug));
    Object.keys(staking?.stateById ?? {}).forEach((id) => {
      usedTokenSlugs.add(staking!.stateById![id].tokenSlug);
    });
  });

  return Array.from(usedTokenSlugs);
};

function getAccountTokenSlugs(global: GlobalState, accountId: string) {
  const { currentTokenSlug } = selectAccountState(global, accountId) ?? {};
  const tokenSlugs = extractKey(selectAccountTokens(global, accountId) ?? [], 'slug')
    .slice(0, ACTIVITY_TOKENS_LIMIT);

  if (!tokenSlugs.includes(TONCOIN.slug)) {
    tokenSlugs.push(TONCOIN.slug);
  }

  if (currentTokenSlug && !tokenSlugs.includes(currentTokenSlug)) {
    tokenSlugs.push(currentTokenSlug);
  }

  return tokenSlugs;
}

function updateCache(force?: boolean) {
  if (GLOBAL_STATE_CACHE_DISABLED || !isCaching || (!force && getIsHeavyAnimating())) {
    return;
  }

  const global = getGlobalWithoutTemporaryAccount();

  const accountsById = global.accounts?.byId || {};
  const reducedGlobal: GlobalState = {
    ...INITIAL_STATE,
    ...pick(global, [
      'currentAccountId',
      // The temporary account is correctly removed from the state during the initialization phase
      'currentTemporaryViewAccountId',
      'stateVersion',
      'restrictions',
      'pushNotifications',
      'isFullscreen',
      'isManualLockActive',
      'stakingDefault',
      'currencyRates',
      'accountSelectorViewMode',
      'seasonalTheme',
    ]),
    accounts: {
      byId: accountsById,
    },
    byAccountId: reduceByAccountId(global),
    settings: {
      ...global.settings,
      byAccountId: pick(global.settings.byAccountId, Object.keys(accountsById)),
    },
  };

  const usedTokenSlugs = getUsedTokenSlugs(reducedGlobal);

  reducedGlobal.tokenInfo = {
    bySlug: pickTruthy(global.tokenInfo.bySlug, usedTokenSlugs),
  };

  const json = JSON.stringify(reducedGlobal);
  localStorage.setItem(GLOBAL_STATE_CACHE_KEY, json);
}

function getGlobalWithoutTemporaryAccount(): GlobalState {
  const global = getGlobal();
  const temporaryAccountId = global.currentTemporaryViewAccountId;
  if (!temporaryAccountId) return global;

  const accountsById = global.accounts?.byId;
  if (!accountsById || !(temporaryAccountId in accountsById)) {
    return global;
  }

  const newAccountsById = omit(global.accounts!.byId, [temporaryAccountId]);
  const newByAccountId = omit(global.byAccountId, [temporaryAccountId]);
  const newSettingsByAccountId = omit(global.settings.byAccountId, [temporaryAccountId]);
  const orderedAccountIds = global.settings.orderedAccountIds?.filter((id) => id !== temporaryAccountId);

  return {
    ...global,
    currentTemporaryViewAccountId: undefined,
    accounts: {
      ...global.accounts,
      byId: newAccountsById,
    },
    byAccountId: newByAccountId,
    settings: {
      ...global.settings,
      byAccountId: newSettingsByAccountId,
      orderedAccountIds,
    },
  };
}

function reduceByAccountId(global: GlobalState) {
  return Object.entries(global.byAccountId).reduce((acc, [accountId, state]) => {
    if (!global.accounts?.byId[accountId]) {
      return acc;
    }

    acc[accountId] = pick(state, [
      'isBackupRequired',
      'currentTokenSlug',
      'currentTokenPeriod',
      'savedAddresses',
      'staking',
      'activeContentTab',
      'landscapeActionsActiveTabIndex',
      'browserHistory',
      'blacklistedNftAddresses',
      'whitelistedNftAddresses',
      'dappLastOpenedDatesByUrl',
      'dapps',
    ]);

    if (state.nfts?.collectionTabs) {
      acc[accountId].nfts = {
        collectionTabs: state.nfts.collectionTabs,
        wasTelegramGiftsAutoAdded: state.nfts.wasTelegramGiftsAutoAdded,
      };
    }

    const accountTokenSlugs = getAccountTokenSlugs(global, accountId);
    acc[accountId].balances = reduceAccountBalances(state.balances, accountTokenSlugs);
    acc[accountId].activities = reduceAccountActivities(state.activities, accountTokenSlugs);
    acc[accountId].staking = reduceAccountStaking(state.staking);
    acc[accountId].stakingHistory = state.stakingHistory?.length
      ? state.stakingHistory.slice(0, STAKING_HISTORY_LIMIT)
      : undefined;

    return acc;
  }, {} as GlobalState['byAccountId']);
}

function reduceAccountBalances(balances?: AccountState['balances'], tokenSlugs?: string[]) {
  if (!balances?.bySlug || !tokenSlugs) return balances;

  return {
    ...balances,
    bySlug: pick(balances.bySlug, tokenSlugs),
  };
}

function reduceAccountActivities(activities?: AccountState['activities'], tokenSlugs?: string[]) {
  const {
    idsBySlug, newestActivitiesBySlug, byId, idsMain,
  } = activities || {};
  if (!tokenSlugs || !idsBySlug || !byId || !idsMain) return undefined;

  const reducedIdsMain = pickVisibleActivities(idsMain, byId);
  const reducedIdsBySlug = mapValues(pickTruthy(idsBySlug, tokenSlugs), (ids) => pickVisibleActivities(ids, byId));

  const reducedNewestActivitiesBySlug = newestActivitiesBySlug
    ? pick(newestActivitiesBySlug, tokenSlugs)
    : undefined;

  const reducedIds = Object.values(reducedIdsBySlug).concat(reducedIdsMain).flat();
  const reducedById = pick(byId, reducedIds);

  return {
    byId: reducedById,
    idsMain: reducedIdsMain,
    idsBySlug: reducedIdsBySlug,
    newestActivitiesBySlug: reducedNewestActivitiesBySlug,
  };
}

function reduceAccountStaking(staking?: AccountState['staking']) {
  let { stakingId, stateById } = staking ?? {};

  if (stateById && !isEmptyObject(stateById)) {
    stateById = filterValues(stateById, getIsActiveStakingState);

    if (!stakingId || !(stakingId in stateById)) {
      stakingId = Object.values(stateById)[0]?.id;
    }
  }

  return {
    ...staking,
    stateById,
    stakingId,
  };
}

function pickVisibleActivities(ids: string[], byId: Record<string, ApiActivity>) {
  const result: string[] = [];

  let visibleIdCount = 0;

  ids
    .filter((id) => shouldCacheActivity(id, byId))
    .forEach((id) => {
      if (visibleIdCount === ACTIVITIES_LIMIT) return;

      if (!byId[id].shouldHide) {
        visibleIdCount += 1;
      }

      result.push(id);
    });

  return result;
}

function shouldCacheActivity(id: string, byId: Record<string, ApiActivity>) {
  const activity = byId[id];
  return activity
    && !getIsTxIdLocal(id)
    && !getIsActivityPending(activity);
}
