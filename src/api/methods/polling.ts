import type {
  ApiAccountAny,
  ApiAccountConfig,
  ApiActivityTimestamps,
  ApiBackendConfig,
  ApiChain,
  ApiCurrencyRates,
  ApiForeignStakingPromotion,
  ApiInfoBannerPromotion,
  ApiNetwork,
  ApiSwapAsset,
  ApiUpdateAccountBanners,
  ApiUpdateAccountConfig,
  ApiUpdateBalances,
  ApiUpdateConfig,
  ApiUpdatingStatus,
  OnApiUpdate,
} from '../types';

import { NO_EXTRA_FEATURES } from '../../config';
import { parseAccountId } from '../../util/account';
import { parseAgentProtocolVersion } from '../../util/agent/agentOverride';
import { areDeepEqual } from '../../util/areDeepEqual';
import { getChainConfig, getOrderedAccountChains } from '../../util/chain';
import { toDecimal } from '../../util/decimals';
import { formatNumber } from '../../util/formatNumber';
import { omit } from '../../util/iteratees';
import { logDebugError } from '../../util/logs';
import { OrGate } from '../../util/orGate';
import { createTaskQueue, throttle } from '../../util/schedulers';
import { getNativeToken } from '../../util/tokens';
import chains from '../chains';
import {
  doesAccountHaveChain,
  fetchMaybeStoredAccount,
  fetchStoredAccount,
  fetchStoredAccounts,
  getCurrentAccountId,
} from '../common/accounts';
import { tryUpdateKnownAddresses } from '../common/addresses';
import { callBackendGet, callBackendPost } from '../common/backend';
import { getStakingCommonCache, setBackendConfigCache } from '../common/cache';
import {
  forgetAllHeldTokens,
  forgetHeldTokens,
  forgetNetworkHeldTokens,
  forgetOtherNetworksHeldTokens,
  recordHeldTokens,
} from '../common/heldTokens';
import { pollingLoop } from '../common/polling/utils';
import {
  buildTokenSlug,
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
import { canBuildForeignUnstakeTransaction } from './foreignStakingUnstakeBuilders';
import {
  requireAgentV2Lifecycle,
  requireMfaMethods,
  requireStakingMethods,
  requireSwapMethods,
} from './optional';
import { resolveDataPreloadPromise } from './preload';

const BACKEND_INTERVAL = 30 * SEC;
const LONG_BACKEND_INTERVAL = MINUTE;
const SWAP_ASSETS_INTERVAL = { focused: 10 * MINUTE, notFocused: 10 * MINUTE };
const KNOWN_ADDRESSES_INTERVAL = { focused: 5 * MINUTE, notFocused: 5 * MINUTE };
const INCORRECT_TIME_DIFF = 30 * SEC;

const ACCOUNT_CONFIG_INTERVAL = { focused: MINUTE, notFocused: 10 * MINUTE };
const FOREIGN_STAKING_INTERVAL = { focused: 15 * MINUTE, notFocused: 30 * MINUTE };
const MFA_INTERVAL = MINUTE;

/** Lets the balances of the several polled wallets arrive before the details of their new tokens are requested */
const TOKEN_DETAILS_THROTTLE = 3 * SEC;

let onUpdate: OnApiUpdate;
let stopCommonBackendPolling: NoneToVoidFunction | undefined;
let stopActiveAccountPolling: NoneToVoidFunction | undefined;
let activeAccountConfigPolling: ReturnType<typeof setupAccountConfigPolling> | undefined;
let activeForeignStakingPolling: ReturnType<typeof setupForeignStakingPolling> | undefined;
const foreignPromotionsByAccount = new Map<string, ApiForeignStakingPromotion>();
let configUpdateGeneration = 0;
let activeAccountPollingGeneration = 0;
const inactiveAccountPolling = createInactiveAccountsPollingManager();
const setUpdatingStatus = createUpdatingStatusManager();

export function initPolling(_onUpdate: OnApiUpdate) {
  const swapAssetsResponse: { text?: string; isStopped?: boolean; isLoading?: boolean } = {};
  const knownAddressesResponse: { text?: string; isStopped?: boolean; isLoading?: boolean } = {};

  // Every chain reports the balances of both the active and the inactive accounts through this callback, which makes it
  // the one place where the set of held tokens can be tracked without touching the chain implementations
  onUpdate = (update) => {
    if (update.type === 'updateBalances') {
      if (recordHeldTokens(update.accountId, update.balances)) {
        refreshTokenDetails();
      }
      activeForeignStakingPolling?.onBalanceUpdate(update);
    }

    _onUpdate(update);
  };

  pauseTokenUpdates();
  void loadTokensCache();

  void Promise.allSettled([
    tryUpdateKnownAddresses(knownAddressesResponse),
    tryUpdateTokens(),
    tryUpdateCurrencyRates(),
    !NO_EXTRA_FEATURES && tryUpdateSwapTokens(swapAssetsResponse),
    !NO_EXTRA_FEATURES && requireStakingMethods().tryUpdateStakingCommonData(),
  ]).then(() => resolveDataPreloadPromise());

  void tryUpdateConfig();

  stopCommonBackendPolling?.();
  stopCommonBackendPolling = setupCommonBackendPolling(swapAssetsResponse, knownAddressesResponse);
}

export async function destroyPolling() {
  configUpdateGeneration += 1;
  stopCommonBackendPolling?.();
  stopCommonBackendPolling = undefined;
  const didDeactivate = await setActivePollingAccount(undefined, {});
  if (didDeactivate) {
    forgetAllHeldTokens();
    foreignPromotionsByAccount.clear();
  }
}

function setupCommonBackendPolling(
  swapAssetsResponse: { text?: string; isStopped?: boolean; isLoading?: boolean },
  knownAddressesResponse: { text?: string; isStopped?: boolean; isLoading?: boolean },
) {
  const knownAddressesPolling = pollingLoop({
    period: KNOWN_ADDRESSES_INTERVAL,
    minDelay: LONG_BACKEND_INTERVAL,
    skipInitialPoll: true,
    poll: () => tryUpdateKnownAddresses(knownAddressesResponse, true),
  });
  const swapAssetsPolling = !NO_EXTRA_FEATURES ? pollingLoop({
    period: SWAP_ASSETS_INTERVAL,
    minDelay: LONG_BACKEND_INTERVAL,
    skipInitialPoll: true,
    poll: () => tryUpdateSwapTokens(swapAssetsResponse, true),
  }) : undefined;

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
        if (knownAddressesResponse.text === undefined && !knownAddressesResponse.isLoading) {
          knownAddressesPolling.poll();
        }
        if (swapAssetsResponse.text === undefined && !swapAssetsResponse.isLoading) {
          swapAssetsPolling?.poll();
        }
        await Promise.all([
          tryUpdateTokens(),
          !NO_EXTRA_FEATURES && requireStakingMethods().tryUpdateStakingCommonData(),
          tryUpdateConfig(),
        ]);
      },
    }).stop,
    knownAddressesPolling.stop,
    swapAssetsPolling?.stop,
  ];

  return () => {
    swapAssetsResponse.isStopped = true;
    knownAddressesResponse.isStopped = true;
    for (const stopFn of stopFns) {
      stopFn?.();
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

async function tryUpdateSwapTokens(
  lastResponse: { text?: string; isStopped?: boolean; isLoading?: boolean },
  shouldSkipUnchanged = false,
) {
  if (lastResponse.isLoading) return;
  lastResponse.isLoading = true;
  try {
    const text = await requireSwapMethods().swapGetAssetsText();
    if (lastResponse.isStopped || (shouldSkipUnchanged && text === lastResponse.text)) return;

    const assets: ApiSwapAsset[] = JSON.parse(text);

    await tokensPreload.promise;
    if (lastResponse.isStopped) return;

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
    lastResponse.text = text;
  } catch (err) {
    logDebugError('tryUpdateSwapTokens', err);
  } finally {
    lastResponse.isLoading = false;
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
  const generation = ++activeAccountPollingGeneration;
  stopActivePolling();

  if (!accountId) {
    await inactiveAccountPolling?.setActiveAccount(undefined);
    return generation === activeAccountPollingGeneration;
  }

  const account = await fetchStoredAccount(accountId);
  if (generation !== activeAccountPollingGeneration) return false;
  setupActivePolling(accountId, account, newestActivityTimestamps, shouldResetBalances);
  await inactiveAccountPolling?.setActiveAccount(accountId);
  return generation === activeAccountPollingGeneration;
}

export async function resumeCurrentAccountPollingAfterWorkerStart() {
  const generation = ++activeAccountPollingGeneration;
  stopActivePolling();

  const accountId = await getCurrentAccountId();
  if (generation !== activeAccountPollingGeneration) return false;
  if (!accountId) return undefined;

  const account = await fetchMaybeStoredAccount(accountId);
  if (generation !== activeAccountPollingGeneration) return false;
  if (!account) return undefined;

  setupActivePolling(accountId, account, {});
  await inactiveAccountPolling?.setActiveAccount(accountId);
  return generation === activeAccountPollingGeneration;
}

function stopActivePolling() {
  stopActiveAccountPolling?.();
  stopActiveAccountPolling = undefined;
  activeAccountConfigPolling = undefined;
  activeForeignStakingPolling = undefined;
}

function setupActivePolling(
  accountId: string,
  account: ApiAccountAny,
  newestActivityTimestamps: ApiActivityTimestamps,
  shouldResetBalances?: boolean,
) {
  const accountChains = getOrderedAccountChains(account.byChain);
  let isStopped = false;
  let serverInfoBanners: ApiInfoBannerPromotion[] = [];
  let foreignPromotion = foreignPromotionsByAccount.get(accountId);
  let lastBanners: Omit<ApiUpdateAccountBanners, 'type' | 'accountId'> | undefined;

  function updateBanners() {
    if (isStopped) return;
    const homeBanners = [
      ...(foreignPromotion ? [buildForeignStakingHomeBanner(foreignPromotion)] : []),
      ...serverInfoBanners,
    ].filter((promotion, index, all) => all.findIndex(({ id }) => id === promotion.id) === index);
    const banners = {
      homeBanners,
      stakingBanners: foreignPromotion ? [foreignPromotion] : [],
    };
    if (areDeepEqual(banners, lastBanners)) return;
    lastBanners = banners;
    onUpdate({ type: 'updateAccountBanners', accountId, ...banners });
  }

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
    ? setupAccountConfigPolling(accountId, account, (infoBanners) => {
      serverInfoBanners = infoBanners;
      updateBanners();
    })
    : undefined;
  activeForeignStakingPolling = !NO_EXTRA_FEATURES
    ? setupForeignStakingPolling(accountId, account, (promotion) => {
      if (isStopped) return;
      foreignPromotion = promotion;
      if (promotion) foreignPromotionsByAccount.set(accountId, promotion);
      else foreignPromotionsByAccount.delete(accountId);
      updateBanners();
    })
    : undefined;

  const stopPollingFns = [
    activeAccountConfigPolling?.stop,
    activeForeignStakingPolling?.stop,
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
    isStopped = true;
    for (const stopFn of stopPollingFns) {
      stopFn?.();
    }
  };
}

/** Call it every time a new account is created */
export function addPollingAccount(accountId: string, account: ApiAccountAny) {
  void inactiveAccountPolling?.addAccount(accountId, account);
}

/** Call it every time an account is removed (except for cases in the other remove...account functions) */
export async function removePollingAccount(accountId: string) {
  await inactiveAccountPolling.removeAccount(accountId);
  foreignPromotionsByAccount.delete(accountId);
  forgetHeldTokens(accountId);
}

/** Call it every time all accounts of a network are removed */
export async function removeNetworkPollingAccounts(network: ApiNetwork) {
  await inactiveAccountPolling.removeNetworkAccounts(network);
  for (const accountId of foreignPromotionsByAccount.keys()) {
    if (parseAccountId(accountId).network === network) foreignPromotionsByAccount.delete(accountId);
  }
  forgetNetworkHeldTokens(network);
}

/** Call it every time all accounts are removed */
export async function removeAllPollingAccounts() {
  await inactiveAccountPolling.removeAllAccounts();
  foreignPromotionsByAccount.clear();
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
  return activeAccountConfigPolling?.poll();
}

export function pollForeignStakingPromotion() {
  return activeForeignStakingPolling?.poll();
}

async function fetchForeignStakingPromotion(accountId: string): Promise<ApiForeignStakingPromotion | undefined> {
  const commonByChain = new Map<ApiChain, Awaited<ReturnType<typeof getStakingCommonCache>>>();
  const foreignStaking = await requireStakingMethods().fetchStakingForeign(accountId);
  for (const entry of foreignStaking) {
    for (const provider of entry.providers) {
      if (!canBuildForeignUnstakeTransaction(entry, provider) || !Number.isFinite(provider.apy)) continue;
      let common = commonByChain.get(entry.chain);
      if (!common) {
        common = await getStakingCommonCache(entry.chain);
        commonByChain.set(entry.chain, common);
      }
      if (provider.apy >= common.liquid.apy) continue;

      const nativeToken = getNativeToken(entry.chain);
      const amount = formatNumber(toDecimal(provider.amountNative, nativeToken.decimals));
      return {
        id: `foreign-staking:${entry.chain}:${provider.name}`,
        kind: 'foreignStaking',
        foreignStaking: {
          chain: entry.chain,
          providerName: provider.name,
          amount,
          symbol: nativeToken.symbol,
          apy: provider.apy,
          stakingApy: common.liquid.apy,
        },
        infoBanner: {
          title: '🔒 %amount% %symbol% locked in another staking',
          textValues: { '%amount%': amount, '%symbol%': nativeToken.symbol },
          description: 'Unstake them to restake with **higher returns**.',
          actionButton: {
            title: 'Unstake',
            onClickAction: 'unstakeForeign',
            chain: entry.chain,
            providerName: provider.name,
          },
        },
        linkedBannerId: `foreign-staking:${entry.chain}`,
      };
    }
  }

  return undefined;
}

function buildForeignStakingHomeBanner(promotion: ApiForeignStakingPromotion): ApiInfoBannerPromotion {
  return {
    id: promotion.linkedBannerId,
    kind: 'infoBanner',
    infoBanner: {
      title: '💎 More profitable staking available',
      textValues: { '%symbol%': promotion.foreignStaking.symbol },
      description: 'Tap to restake your %symbol% with higher returns.',
      actionButton: { title: 'Restake Now', onClickAction: 'openEarn' },
    },
  };
}

function setupForeignStakingPolling(
  accountId: string,
  account: ApiAccountAny,
  onStakingBanner: (promotion: ApiForeignStakingPromotion | undefined) => void,
) {
  if (account.type === 'view' || parseAccountId(accountId).network !== 'mainnet') {
    return undefined;
  }

  const lastBalanceByChain = new Map<ApiChain, bigint>();
  const polling = pollingLoop({
    period: FOREIGN_STAKING_INTERVAL,
    async poll() {
      if (!hasForeignStakingBalance()) return;

      try {
        const promotion = await fetchForeignStakingPromotion(accountId);
        if (hasForeignStakingBalance()) onStakingBanner(promotion);
      } catch (err) {
        logDebugError('setupForeignStakingPolling', err);
      }
    },
  });

  function hasForeignStakingBalance() {
    return [...lastBalanceByChain.values()].some((balance) => balance > 0n);
  }

  return {
    ...polling,
    onBalanceUpdate(update: ApiUpdateBalances) {
      if (update.accountId !== accountId) return;

      const { foreignStakingTokenAddresses } = getChainConfig(update.chain);
      if (!foreignStakingTokenAddresses?.length) return;

      const balance = foreignStakingTokenAddresses.reduce((sum, address) => (
        sum + (update.balances[buildTokenSlug(update.chain, address)] ?? 0n)
      ), 0n);
      const lastBalance = lastBalanceByChain.get(update.chain);
      if (balance === lastBalance) return;
      lastBalanceByChain.set(update.chain, balance);
      if (!hasForeignStakingBalance()) onStakingBanner(undefined);
      else pollForeignStakingPromotion();
    },
  };
}

function setupAccountConfigPolling(
  accountId: string,
  account: ApiAccountAny,
  onInfoBanners: (infoBanners: ApiInfoBannerPromotion[]) => void,
) {
  let lastResult: ApiUpdateAccountConfig['accountConfig'] | undefined;

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
        const response = await callBackendPost<ApiAccountConfig>('/account-config', {
          ...partialAccount,
          langCode,
        });
        const { infoBanners, ...accountConfig } = response;
        const serverInfoBanners = Array.isArray(infoBanners) ? infoBanners.filter((banner) => (
          banner?.kind === 'infoBanner'
          && typeof banner.infoBanner === 'object'
          && typeof banner.infoBanner?.title === 'string'
          && typeof banner.infoBanner.description === 'string'
          && typeof banner.infoBanner.actionButton?.title === 'string'
          && banner.infoBanner.actionButton.onClickAction === 'openEarn'
        )) : [];

        if (!areDeepEqual(accountConfig, lastResult)) {
          lastResult = accountConfig;
          onUpdate({
            type: 'updateAccountConfig',
            accountId,
            accountConfig,
          });
        }
        onInfoBanners(serverInfoBanners);
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
  const mutations = createTaskQueue(1);
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
    activeAccountId = undefined;
  }

  return {
    setActiveAccount: mutations.wrap(setActiveAccount),
    addAccount: mutations.wrap(addAccount),
    removeAccount: mutations.wrap(removeAccount),
    removeNetworkAccounts: mutations.wrap(removeNetworkAccounts),
    removeAllAccounts: mutations.wrap(removeAllAccounts),
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
