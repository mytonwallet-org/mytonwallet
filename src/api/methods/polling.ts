import type {
  ApiAccountAny,
  ApiAccountConfig,
  ApiAccountWithMnemonic,
  ApiActivityTimestamps,
  ApiBackendConfig,
  ApiChain,
  ApiCurrencyRates,
  ApiNetwork,
  ApiSwapAsset,
  ApiTokenDetails,
  ApiTokenWithPrice,
  ApiUpdatingStatus,
  OnApiUpdate,
} from '../types';

import { IS_CORE_WALLET, IS_STAKING_DISABLED, TONCOIN } from '../../config';
import { parseAccountId } from '../../util/account';
import { areDeepEqual } from '../../util/areDeepEqual';
import { omit } from '../../util/iteratees';
import { logDebugError } from '../../util/logs';
import { OrGate } from '../../util/orGate';
import { forbidConcurrency } from '../../util/schedulers';
import { getNativeToken } from '../../util/tokens';
import chains from '../chains';
import {
  doesAccountHaveChain,
  fetchMaybeStoredAccount,
  fetchStoredAccount,
  fetchStoredAccounts,
} from '../common/accounts';
import { tryUpdateKnownAddresses } from '../common/addresses';
import { callBackendGet, callBackendPost } from '../common/backend';
import { setBackendConfigCache } from '../common/cache';
import { pollingLoop } from '../common/polling/utils';
import { getTokensCache, loadTokensCache, sendUpdateTokens, tokensPreload, updateTokens } from '../common/tokens';
import { MINUTE, SEC } from '../constants';
import { storage } from '../storages';
import { resolveDataPreloadPromise } from './preload';
import { tryUpdateStakingCommonData } from './staking';
import { swapGetAssets } from './swap';

const BACKEND_INTERVAL = 30 * SEC;
const LONG_BACKEND_INTERVAL = MINUTE;
const INCORRECT_TIME_DIFF = 30 * SEC;

const ACCOUNT_CONFIG_INTERVAL = { focused: MINUTE, notFocused: 10 * MINUTE };

const MAX_POST_TOKENS = 1500;

let onUpdate: OnApiUpdate;
let stopCommonBackendPolling: NoneToVoidFunction | undefined;
let stopActiveAccountPolling: NoneToVoidFunction | undefined;
const inactiveAccountPolling = createInactiveAccountsPollingManager();
const setUpdatingStatus = createUpdatingStatusManager();

export function initPolling(_onUpdate: OnApiUpdate) {
  onUpdate = _onUpdate;

  void loadTokensCache();

  void Promise.allSettled([
    tryUpdateKnownAddresses(),
    tryUpdateTokens(),
    tryUpdateCurrencyRates(),
    !IS_STAKING_DISABLED && tryUpdateSwapTokens(),
    tryUpdateStakingCommonData(),
  ]).then(() => resolveDataPreloadPromise());

  void tryUpdateConfig();

  stopCommonBackendPolling?.();
  stopCommonBackendPolling = setupCommonBackendPolling();
}

export async function destroyPolling() {
  stopCommonBackendPolling?.();
  stopCommonBackendPolling = undefined;
  removeAllPollingAccounts();
  await setActivePollingAccount(undefined, {});
}

function setupCommonBackendPolling() {
  const stopFns = [
    pollingLoop({
      period: BACKEND_INTERVAL,
      skipInitialPoll: true,
      poll: tryUpdateCurrencyRates,
    }).stop,
    pollingLoop({
      period: LONG_BACKEND_INTERVAL,
      skipInitialPoll: true,
      async poll() {
        await Promise.all([
          tryUpdateTokens(),
          tryUpdateKnownAddresses(),
          !IS_STAKING_DISABLED && tryUpdateStakingCommonData(),
          tryUpdateConfig(),
          tryUpdateSwapTokens(),
        ]);
      },
    }).stop,
  ];

  return () => {
    for (const stopFn of stopFns) {
      stopFn();
    }
  };
}

async function tryUpdateTokens() {
  try {
    const tokens = await callBackendGet<ApiTokenWithPrice[]>('/assets');

    for (const token of tokens) {
      token.isFromBackend = true;
    }

    await tokensPreload.promise;
    const tokensCache = getTokensCache();

    const backendReturnedSlugs = new Set(tokens.map((t) => t.slug));
    const nonBackendTokenAddresses = Object.values(tokensCache.bySlug).reduce((result, token) => {
      // Retrieve details for tokens that are not returned by /assets anymore
      // (i.e. rug pulled and therefore disabled on the backend)
      if ((!token.isFromBackend || !backendReturnedSlugs.has(token.slug)) && token.tokenAddress) {
        result.push(token.tokenAddress);
      }
      return result;
    }, [] as string[]);

    // POST is used to retrieve data due to the potentially large number of addresses
    const nonBackendTokenDetails = nonBackendTokenAddresses.length
      ? await callBackendPost<ApiTokenDetails[]>('/assets', {
        assets: nonBackendTokenAddresses.slice(0, MAX_POST_TOKENS),
      }) : undefined;

    await updateTokens(tokens, () => sendUpdateTokens(onUpdate), nonBackendTokenDetails, true);
  } catch (err) {
    logDebugError('tryUpdateTokens', err);
  }
}

async function tryUpdateCurrencyRates() {
  try {
    const currencyRates = await callBackendGet<{ rates: ApiCurrencyRates }>('/currency-rates');
    onUpdate({
      type: 'updateCurrencyRates',
      rates: currencyRates.rates,
    });
  } catch (err) {
    logDebugError('tryUpdateCurrencyRates', err);
  }
}

async function tryUpdateSwapTokens() {
  try {
    const assets = await swapGetAssets();

    await tokensPreload.promise;

    const tokens = assets.reduce((acc: Record<string, ApiSwapAsset>, asset) => {
      acc[asset.slug] = {
        // Fix legacy variable names
        ...omit(asset as any, ['blockchain']) as ApiSwapAsset,
        chain: 'blockchain' in asset ? asset.blockchain as string : asset.chain,
        tokenAddress: 'contract' in asset && asset.contract !== TONCOIN.symbol
          ? asset.contract as string
          : asset.tokenAddress,
      };
      return acc;
    }, {});

    onUpdate({
      type: 'updateSwapTokens',
      tokens,
    });
  } catch (err) {
    logDebugError('tryUpdateSwapTokens', err);
  }
}

export async function tryUpdateConfig() {
  try {
    const config = await callBackendGet<ApiBackendConfig>('/utils/get-config');
    setBackendConfigCache(config);

    const {
      isLimited,
      isCopyStorageEnabled = false,
      supportAccountsCount = 1,
      now: serverUtc,
      country: countryCode,
      swapVersion,
      seasonalTheme,
      isUpdateRequired: isAppUpdateRequired,
    } = config;

    onUpdate({
      type: 'updateConfig',
      isLimited,
      isCopyStorageEnabled,
      supportAccountsCount,
      countryCode,
      isAppUpdateRequired,
      swapVersion,
      seasonalTheme,
    });

    const localUtc = (new Date()).getTime();
    if (Math.abs(serverUtc - localUtc) > INCORRECT_TIME_DIFF) {
      onUpdate({
        type: 'incorrectTime',
      });
    }
  } catch (err) {
    logDebugError('tryUpdateConfig', err);
  }
}

/** Call it every time the active account changes */
export async function setActivePollingAccount(
  accountId: string | undefined,
  newestActivityTimestamps: ApiActivityTimestamps,
) {
  stopActiveAccountPolling?.();
  stopActiveAccountPolling = undefined;

  if (accountId) {
    const account = await fetchStoredAccount(accountId);

    const stopPollingFns = [
      !IS_CORE_WALLET && setupAccountConfigPolling(accountId, account).stop,

      ...(Object.keys(chains) as (keyof typeof chains)[]).map((chain) => {
        if (doesAccountHaveChain(account, chain)) {
          return chains[chain].setupActivePolling(
            accountId,
            account,
            onUpdate,
            setUpdatingStatus.bind(undefined, accountId, chain),
            pickChainTimestamps(newestActivityTimestamps, chain),
          );
        }
      }),
    ];

    stopActiveAccountPolling = () => {
      for (const stopFn of stopPollingFns) {
        if (stopFn) {
          stopFn();
        }
      }
    };
  }

  // Setting up inactive account polling at the end in order to give the active account polling a higher priority in the connection queue
  inactiveAccountPolling?.setActiveAccount(accountId);
}

/** Call it every time a new account is created */
export function addPollingAccount(accountId: string, account: ApiAccountAny) {
  inactiveAccountPolling?.addAccount(accountId, account);
}

/** Call it every time an account is removed (except for cases in the other remove...account functions) */
export function removePollingAccount(accountId: string) {
  inactiveAccountPolling?.removeAccount(accountId);
}

/** Call it every time all accounts of a network are removed */
export function removeNetworkPollingAccounts(network: ApiNetwork) {
  inactiveAccountPolling?.removeNetworkAccounts(network);
}

/** Call it every time all accounts are removed */
export function removeAllPollingAccounts() {
  inactiveAccountPolling?.removeAllAccounts();
}

function setupAccountConfigPolling(accountId: string, account: ApiAccountAny) {
  let lastResult: ApiAccountConfig | undefined;

  const partialAccount = omit(account as ApiAccountWithMnemonic, ['mnemonicEncrypted']);

  return pollingLoop({
    period: ACCOUNT_CONFIG_INTERVAL,
    async poll() {
      try {
        const langCode = await storage.getItem('langCode');
        const accountConfig = await callBackendPost<ApiAccountConfig>('/account-config', {
          ...partialAccount,
          langCode,
        });

        if (!areDeepEqual(accountConfig, lastResult)) {
          lastResult = accountConfig;
          onUpdate({
            type: 'updateAccountConfig',
            accountId,
            accountConfig,
          });
        }
      } catch (err) {
        logDebugError('setupBackendAccountPolling', err);
      }
    },
  });
}

/**
 * Returns a stateful function that receives updating statuses from multiple chains and merges them together into a
 * single set of consistent 'updatingStatus' events for the UI.
 */
function createUpdatingStatusManager() {
  const updatingStatuses = new Map<string, OrGate<ApiChain>>();

  return (accountId: string, chain: ApiChain, kind: ApiUpdatingStatus['kind'], isUpdating: boolean) => {
    const key = `${accountId} ${kind}`;
    let chainsBeingUpdated = updatingStatuses.get(key);
    if (!chainsBeingUpdated) {
      chainsBeingUpdated = new OrGate<ApiChain>((isUpdating) => {
        onUpdate({ type: 'updatingStatus', kind, accountId, isUpdating });
      });
      updatingStatuses.set(key, chainsBeingUpdated);
    }

    chainsBeingUpdated.toggle(chain, isUpdating);
  };
}

/**
 * Manages polling for the inactive accounts.
 * The goal is polling the accounts from the network of the current active account, but not the active account itself.
 *
 * @todo: Deduplicate polling the same addresses, if multiple accounts have it
 */
function createInactiveAccountsPollingManager() {
  const stopByAccount: Record<string, NoneToVoidFunction> = {};
  let activeAccountId: string | undefined;

  async function setActiveAccount(accountId: string | undefined) {
    if (accountId === activeAccountId) {
      return;
    }

    if (accountId === undefined) {
      stopAllPollings();
      return;
    }

    if (!activeAccountId || parseAccountId(accountId).network !== parseAccountId(activeAccountId).network) {
      await switchNetwork(accountId);
      return;
    }

    const previousActiveAccountId = activeAccountId;
    activeAccountId = accountId;

    // Stop polling the now active account
    stopByAccount[activeAccountId]?.();
    delete stopByAccount[activeAccountId];

    // Start polling the previous active account
    const previousActiveAccount = await fetchMaybeStoredAccount(previousActiveAccountId);
    if (previousActiveAccount) { // The previously active account may get removed at this moment
      startAccountPolling(previousActiveAccountId, previousActiveAccount);
    }
  }

  function addAccount(accountId: string, account: ApiAccountAny) {
    const isActiveAccount = accountId === activeAccountId;
    const isCurrentNetwork = activeAccountId
      && parseAccountId(accountId).network === parseAccountId(activeAccountId).network;

    if (!isActiveAccount && isCurrentNetwork) {
      startAccountPolling(accountId, account);
    }
  }

  function removeAccount(accountId: string) {
    stopByAccount[accountId]?.();
    delete stopByAccount[accountId];
  }

  function removeNetworkAccounts(network: ApiNetwork) {
    if (activeAccountId && parseAccountId(activeAccountId).network === network) {
      // Inactive account polling must poll only the network of the active account, so removing the network means removing all account
      stopAllPollings();
    }
  }

  function removeAllAccounts() {
    stopAllPollings();
  }

  async function switchNetwork(newActiveAccountId: string) {
    stopAllPollings();
    activeAccountId = newActiveAccountId;
    const { network } = parseAccountId(activeAccountId);
    const accounts = await fetchStoredAccounts();
    const otherAccountIds = Object.keys(accounts).filter((accountId) => (
      accountId !== activeAccountId
      && parseAccountId(accountId).network === network
    ));
    otherAccountIds.map((accountId) => startAccountPolling(accountId, accounts[accountId]));
  }

  function startAccountPolling(accountId: string, account: ApiAccountAny) {
    if (stopByAccount[accountId]) return;

    const stopFns = (Object.keys(chains) as (keyof typeof chains)[]).map((chain) => {
      if (doesAccountHaveChain(account, chain)) {
        return chains[chain].setupInactivePolling(accountId, account, onUpdate);
      }
    });

    stopByAccount[accountId] = () => {
      for (const stopChain of stopFns) {
        stopChain?.();
      }
    };
  }

  function stopAllPollings() {
    for (const [accountId, stopAccountPolling] of Object.entries(stopByAccount)) {
      stopAccountPolling();
      delete stopByAccount[accountId];
    }
  }

  const preventRaceCondition = forbidConcurrency as
    <Args extends unknown[]>(task: (...args: Args) => unknown) => (...args: Args) => void;

  return {
    setActiveAccount: preventRaceCondition(setActiveAccount),
    addAccount: preventRaceCondition(addAccount),
    removeAccount: preventRaceCondition(removeAccount),
    removeNetworkAccounts: preventRaceCondition(removeNetworkAccounts),
    removeAllAccounts: preventRaceCondition(removeAllAccounts),
  };
}

function pickChainTimestamps(bySlug: ApiActivityTimestamps, chain: ApiChain) {
  const { slug: nativeSlug } = getNativeToken(chain);
  return Object.entries(bySlug).reduce((newBySlug, [slug, timestamp]) => {
    if (slug === nativeSlug || slug.startsWith(`${chain}-`)) {
      newBySlug[slug] = timestamp;
    }
    return newBySlug;
  }, {} as ApiActivityTimestamps);
}
