import type {
  ApiAccountAny,
  ApiAccountConfig,
  ApiActivityTimestamps,
  ApiBackendConfig,
  ApiChain,
  ApiCurrencyRates,
  ApiNetwork,
  ApiSwapAsset,
  ApiTokenWithPrice,
  ApiUpdatingStatus,
  OnApiUpdate,
} from '../types';

import { IS_FEATURE_LIMITED, IS_STAKING_DISABLED, NO_MFA, NO_STAKING, NO_SWAP } from '../../config';
import { parseAccountId } from '../../util/account';
import { areDeepEqual } from '../../util/areDeepEqual';
import { omit } from '../../util/iteratees';
import { logDebugError } from '../../util/logs';
import { OrGate } from '../../util/orGate';
import { forbidConcurrency, throttle } from '../../util/schedulers';
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
import {
  forgetAllHeldTokens,
  forgetHeldTokens,
  forgetNetworkHeldTokens,
  forgetOtherNetworksHeldTokens,
  getHeldSlugs,
  recordHeldTokens,
} from '../common/held-tokens';
import { pollingLoop } from '../common/polling/utils';
import {
  buildTokenDetailsPayload,
  fetchBackendTokenDetails,
  getTokensCache,
  loadTokensCache,
  sendUpdateTokens,
  tokensPreload,
  updateTokens,
} from '../common/tokens';
import { MINUTE, SEC } from '../constants';
import { storage } from '../storages';
import { refreshMfaStateAndNotify } from './mfa';
import { resolveDataPreloadPromise } from './preload';
import { tryUpdateStakingCommonData } from './staking';
import { swapGetAssets } from './swap';

const BACKEND_INTERVAL = 30 * SEC;
const LONG_BACKEND_INTERVAL = MINUTE;
const INCORRECT_TIME_DIFF = 30 * SEC;

const ACCOUNT_CONFIG_INTERVAL = { focused: MINUTE, notFocused: 10 * MINUTE };
const MFA_INTERVAL = MINUTE;

/** A backstop for the token details payload, which is normally bounded by the size of the polled portfolios */
const MAX_POST_TOKENS = 1500;
/** Lets the balances of the several polled wallets arrive before the details of their new tokens are requested */
const TOKEN_DETAILS_THROTTLE = 3 * SEC;

let onUpdate: OnApiUpdate;
/** Slugs of the last `GET /assets` response, reused when the details are requested outside `tryUpdateTokens` */
let backendTokenSlugs = new Set<string>();
let stopCommonBackendPolling: NoneToVoidFunction | undefined;
let stopActiveAccountPolling: NoneToVoidFunction | undefined;
const inactiveAccountPolling = createInactiveAccountsPollingManager();
const setUpdatingStatus = createUpdatingStatusManager();

export function initPolling(_onUpdate: OnApiUpdate) {
  // Every chain reports the balances of both the active and the inactive accounts through this callback, which makes it
  // the one place where the set of held tokens can be tracked without touching the chain implementations
  onUpdate = (update) => {
    if (update.type === 'updateBalances' && recordHeldTokens(update.accountId, update.balances)) {
      refreshTokenDetails();
    }

    _onUpdate(update);
  };

  void loadTokensCache();

  void Promise.allSettled([
    tryUpdateKnownAddresses(),
    tryUpdateTokens(),
    tryUpdateCurrencyRates(),
    !IS_STAKING_DISABLED && !NO_SWAP && tryUpdateSwapTokens(),
    !NO_STAKING && tryUpdateStakingCommonData(),
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
          !IS_STAKING_DISABLED && !NO_STAKING && tryUpdateStakingCommonData(),
          tryUpdateConfig(),
          !NO_SWAP && tryUpdateSwapTokens(),
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
    const langCode = await storage.getItem('langCode');
    const tokens = await callBackendGet<ApiTokenWithPrice[]>('/assets', { langCode });

    for (const token of tokens) {
      token.isFromBackend = true;
    }

    await tokensPreload.promise;

    backendTokenSlugs = new Set(tokens.map((t) => t.slug));

    const nonBackendTokenDetails = await fetchNonBackendTokenDetails(langCode);

    await updateTokens(tokens, () => sendUpdateTokens(onUpdate), nonBackendTokenDetails, true);
  } catch (err) {
    logDebugError('tryUpdateTokens', err);
  }
}

async function fetchNonBackendTokenDetails(langCode?: string) {
  const tokensCache = getTokensCache();
  // POST is used to retrieve data because the addresses may not fit into a URL
  const tokenAddresses = buildTokenDetailsPayload(Object.values(tokensCache.bySlug), {
    backendSlugs: backendTokenSlugs,
    heldSlugs: getHeldSlugs(),
    maxCount: MAX_POST_TOKENS,
  });

  return tokenAddresses.length ? fetchBackendTokenDetails(tokenAddresses, langCode) : undefined;
}

/**
 * `tryUpdateTokens` runs before the first balances arrive, so the tokens discovered on the wallets afterwards would
 * wait for the next poll to get their price and type. This catches them up.
 */
const refreshTokenDetails = throttle(async () => {
  try {
    await tokensPreload.promise;
    const langCode = await storage.getItem('langCode');
    const tokenDetails = await fetchNonBackendTokenDetails(langCode);

    if (tokenDetails?.length) {
      await updateTokens([], () => sendUpdateTokens(onUpdate), tokenDetails, true);
    }
  } catch (err) {
    logDebugError('refreshTokenDetails', err);
  }
}, TOKEN_DETAILS_THROTTLE, false);

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

    // FIXME: TON renaming
    const tokens = assets.reduce((acc: Record<string, ApiSwapAsset>, asset) => {
      acc[asset.slug] = {
        // Fix legacy variable names
        ...omit(asset as any, ['blockchain']) as ApiSwapAsset,
        chain: 'blockchain' in asset ? asset.blockchain as string : asset.chain,
        tokenAddress: 'contract' in asset && asset.contract !== 'TON'
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
      knowledgeBaseVersion,
      preferredAgent,
      allowedOnOffRampCurrencies,
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
      knowledgeBaseVersion,
      preferredAgent,
      allowedOnOffRampCurrencies,
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
  shouldResetBalances?: boolean,
) {
  stopActiveAccountPolling?.();
  stopActiveAccountPolling = undefined;

  if (accountId) {
    const account = await fetchStoredAccount(accountId);

    const stopPollingFns = [
      !IS_FEATURE_LIMITED ? setupAccountConfigPolling(accountId, account).stop : undefined,
      !NO_MFA && doesAccountHaveChain(account, 'ton') ? setupMfaPolling(accountId).stop : undefined,

      ...(Object.keys(chains) as (keyof typeof chains)[]).map((chain) => {
        if (doesAccountHaveChain(account, chain)) {
          return chains[chain].setupActivePolling(
            accountId,
            account,
            onUpdate,
            setUpdatingStatus.bind(undefined, accountId, chain),
            pickChainTimestamps(newestActivityTimestamps, chain),
            shouldResetBalances,
          );
        }
      }),
    ];

    stopActiveAccountPolling = () => {
      for (const stopFn of stopPollingFns) {
        stopFn?.();
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
  forgetHeldTokens(accountId);
}

/** Call it every time all accounts of a network are removed */
export function removeNetworkPollingAccounts(network: ApiNetwork) {
  inactiveAccountPolling?.removeNetworkAccounts(network);
  forgetNetworkHeldTokens(network);
}

/** Call it every time all accounts are removed */
export function removeAllPollingAccounts() {
  inactiveAccountPolling?.removeAllAccounts();
  forgetAllHeldTokens();
}

function setupAccountConfigPolling(accountId: string, account: ApiAccountAny) {
  let lastResult: ApiAccountConfig | undefined;

  // The endpoint reads the account type and the chain addresses only, while `authToken` is a bearer credential for
  // our own API - it has no business riding a polling loop's request body once a swap has put it on the wallet.
  const { byChain } = account;
  const partialAccount = {
    ...account,
    ...(byChain.ton && { byChain: { ...byChain, ton: omit(byChain.ton, ['authToken']) } }),
  };

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

function setupMfaPolling(accountId: string) {
  return pollingLoop({
    period: MFA_INTERVAL,
    async poll() {
      try {
        await refreshMfaStateAndNotify(accountId);
      } catch (err) {
        logDebugError('setupMfaPolling', err);
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
    // The other network is no longer polled, so its held tokens would linger in the details payload forever
    forgetOtherNetworksHeldTokens(network);
    const accounts = await fetchStoredAccounts();
    const otherAccountIds = Object.keys(accounts).filter((accountId) => (
      accountId !== activeAccountId
      && parseAccountId(accountId).network === network
    ));
    otherAccountIds.map((accountId) => startAccountPolling(accountId, accounts[accountId]));
  }

  function startAccountPolling(accountId: string, account: ApiAccountAny) {
    if (stopByAccount[accountId]) return;

    const stopFns = [
      !NO_MFA && doesAccountHaveChain(account, 'ton') ? setupMfaPolling(accountId).stop : undefined,
      ...(Object.keys(chains) as (keyof typeof chains)[]).map((chain) => {
        if (doesAccountHaveChain(account, chain)) {
          return chains[chain].setupInactivePolling(accountId, account, onUpdate);
        }
      }),
    ];

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
