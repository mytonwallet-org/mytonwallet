import type {
  ApiAccountAny,
  ApiAccountConfig,
  ApiActivityTimestamps,
  ApiBackendConfig,
  ApiChain,
  ApiCurrencyRates,
  ApiNetwork,
  ApiSwapAsset,
  ApiUpdateConfig,
  ApiUpdatingStatus,
  OnApiUpdate,
} from '../types';

import { NO_EXTRA_FEATURES } from '../../config';
import { parseAccountId } from '../../util/account';
import { parseAgentProtocolVersion } from '../../util/agent/agentOverride';
import { areDeepEqual } from '../../util/areDeepEqual';
import { getChainConfig, getOrderedAccountChains } from '../../util/chain';
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
  recordHeldTokens,
} from '../common/heldTokens';
import { pollingLoop } from '../common/polling/utils';
import {
  fetchNonBackendTokenDetails,
  loadTokensCache,
  pauseTokenUpdates,
  resumeTokenUpdates,
  sendUpdateTokens,
  tokensPreload,
  updateTokens,
  updateTokensFromBackend,
} from '../common/tokens';
import { MINUTE, SEC } from '../constants';
import { storage } from '../storages';
import {
  requireAgentV2Lifecycle,
  requireMfaMethods,
  requireStakingMethods,
  requireSwapMethods,
} from './optional';
import { resolveDataPreloadPromise } from './preload';

const BACKEND_INTERVAL = 30 * SEC;
const LONG_BACKEND_INTERVAL = MINUTE;
const INCORRECT_TIME_DIFF = 30 * SEC;

const ACCOUNT_CONFIG_INTERVAL = { focused: MINUTE, notFocused: 10 * MINUTE };
const MFA_INTERVAL = MINUTE;

/** Lets the balances of the several polled wallets arrive before the details of their new tokens are requested */
const TOKEN_DETAILS_THROTTLE = 3 * SEC;

let onUpdate: OnApiUpdate;
let stopCommonBackendPolling: NoneToVoidFunction | undefined;
let stopActiveAccountPolling: NoneToVoidFunction | undefined;
let activeAccountConfigPolling: ReturnType<typeof setupAccountConfigPolling> | undefined;
let configUpdateGeneration = 0;
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

  pauseTokenUpdates();
  void loadTokensCache();

  void Promise.allSettled([
    tryUpdateKnownAddresses(),
    tryUpdateTokens(),
    tryUpdateCurrencyRates(),
    !NO_EXTRA_FEATURES && tryUpdateSwapTokens(),
    !NO_EXTRA_FEATURES && requireStakingMethods().tryUpdateStakingCommonData(),
  ]).then(() => resolveDataPreloadPromise());

  void tryUpdateConfig();

  stopCommonBackendPolling?.();
  stopCommonBackendPolling = setupCommonBackendPolling();
}

export async function destroyPolling() {
  configUpdateGeneration += 1;
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
          !NO_EXTRA_FEATURES && requireStakingMethods().tryUpdateStakingCommonData(),
          tryUpdateConfig(),
          !NO_EXTRA_FEATURES && tryUpdateSwapTokens(),
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
    await updateTokensFromBackend(onUpdate, { langCode, shouldNarrowToHeldTokens: true });
  } catch (err) {
    logDebugError('tryUpdateTokens', err);
  } finally {
    await tokensPreload.promise;
    resumeTokenUpdates();
  }
}

/**
 * `tryUpdateTokens` runs before the first balances arrive, so the tokens discovered on the wallets afterwards would
 * wait for the next poll to get their price and type. This catches them up.
 */
const refreshTokenDetails = throttle(async () => {
  try {
    await tokensPreload.promise;
    const langCode = await storage.getItem('langCode');
    const tokenDetails = await fetchNonBackendTokenDetails({ langCode, shouldNarrowToHeldTokens: true });

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
    const assets = await requireSwapMethods().swapGetAssets();

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
  const generation = ++configUpdateGeneration;
  try {
    const rawConfig = await callBackendGet<ApiBackendConfig>('/utils/get-config');
    if (generation !== configUpdateGeneration) return;

    const config = {
      ...rawConfig,
      agentProtocolVersion: parseAgentProtocolVersion(rawConfig.agentProtocolVersion),
    };
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
      agentProtocolVersion,
      preferredAgent,
      allowedOnOffRampCurrencies,
    } = config;

    const updateConfig: ApiUpdateConfig = {
      type: 'updateConfig',
      isLimited,
      isCopyStorageEnabled,
      supportAccountsCount,
      countryCode,
      isAppUpdateRequired,
      swapVersion,
      seasonalTheme,
      knowledgeBaseVersion,
      agentProtocolVersion,
      preferredAgent,
      allowedOnOffRampCurrencies,
    };

    if (!NO_EXTRA_FEATURES) {
      const lifecycle = requireAgentV2Lifecycle();
      const reconciliation = lifecycle.reconcileAgentV2ProtocolVersion(agentProtocolVersion);
      updateConfig.agentProtocolVersion = lifecycle.resolveAgentV2ProtocolVersionForRouting(agentProtocolVersion);
      void reconciliation.then(() => {
        if (generation !== configUpdateGeneration) return;

        const reconciledVersion = lifecycle.resolveAgentV2ProtocolVersionForRouting(agentProtocolVersion);
        if (reconciledVersion === updateConfig.agentProtocolVersion) return;
        onUpdate({
          ...updateConfig,
          agentProtocolVersion: reconciledVersion,
        });
      }).catch((err) => logDebugError('reconcileAgentV2ProtocolVersion', err));
    }

    onUpdate(updateConfig);

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
  activeAccountConfigPolling = undefined;

  if (accountId) {
    const account = await fetchStoredAccount(accountId);
    const accountChains = getOrderedAccountChains(account.byChain);

    // These accounts have no NFT polling to finish the initial loading state.
    if (!accountChains.some((chain) => getChainConfig(chain).isNftSupported)) {
      for (const chain of accountChains) {
        onUpdate({
          type: 'updateNfts',
          accountId,
          chain,
          nfts: [],
        });
      }
    }

    activeAccountConfigPolling = canPollAccountConfig(account)
      ? setupAccountConfigPolling(accountId, account)
      : undefined;

    const stopPollingFns = [
      activeAccountConfigPolling?.stop,
      !NO_EXTRA_FEATURES && doesAccountHaveChain(account, 'ton') ? setupMfaPolling(accountId).stop : undefined,

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

/**
 * The endpoint answers a `view` account with an empty config, and keys every other type by its TON
 * address. An account of another type that carries no TON address therefore has nothing to ask for,
 * and asking anyway is a request the backend can only reject.
 */
function canPollAccountConfig(account: ApiAccountAny) {
  return account.type === 'view' || doesAccountHaveChain(account, 'ton');
}

/**
 * Polls the active account config right away. The loop never polls in parallel, so a poll already in flight finishes
 * first and can't overwrite this result. Does nothing if the active account has no config polling.
 */
export function pollAccountConfig() {
  activeAccountConfigPolling?.poll();
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
        await requireMfaMethods().refreshMfaStateAndNotify(accountId);
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
      !NO_EXTRA_FEATURES && doesAccountHaveChain(account, 'ton') ? setupMfaPolling(accountId).stop : undefined,
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
