import type {
  ApiAccountWithChain,
  ApiActivity,
  ApiActivityTimestamps,
  ApiBalanceBySlug,
  ApiNftUpdate,
  ApiStakingState,
  ApiTonWallet,
  ApiUpdatingStatus,
  ApiVestingInfo,
  ApiWalletWithVersionInfo,
  OnApiUpdate,
} from '../../types';

import {
  IS_CORE_WALLET,
  IS_STAKING_DISABLED,
  LEDGER_WALLET_VERSIONS,
  POPULAR_WALLET_VERSIONS,
  TONCOIN,
} from '../../../config';
import { parseAccountId } from '../../../util/account';
import { getActivityTokenSlugs } from '../../../util/activities';
import { areDeepEqual } from '../../../util/areDeepEqual';
import Deferred from '../../../util/Deferred';
import { focusAwareDelay } from '../../../util/focusAwareDelay';
import { compact, pick } from '../../../util/iteratees';
import { logDebugError } from '../../../util/logs';
import { pause, throttle } from '../../../util/schedulers';
import { fetchStoredAccount, fetchStoredWallet, updateStoredWallet } from '../../common/accounts';
import { getBackendConfigCache, getStakingCommonCache } from '../../common/cache';
import { setupInactiveChainPolling } from '../../common/polling/setupInactiveChainPolling';
import { periodToMs, pollingLoop, withDoubleCheck } from '../../common/polling/utils';
import { swapReplaceCexActivities } from '../../common/swap';
import { txCallbacks } from '../../common/txCallbacks';
import { hexToBytes } from '../../common/utils';
import { FIRST_TRANSACTIONS_LIMIT, MINUTE, SEC } from '../../constants';
import { fetchActivitySlice } from './activities';
import { getWalletFromAddress } from './auth';
import { fetchDomains } from './domains';
import { getAccountNfts, getNftUpdates } from './nfts';
import { RichActivityStream } from './richActivityStream';
import { getBackendStakingState, getStakingStates } from './staking';
import { loadTokenBalances } from './tokens';
import { ActivityStream } from './toncenter';
import { fetchVestings } from './vesting';
import { getWalletInfo, getWalletVersionInfos, isAddressInitialized } from './wallet';

type OnUpdatingStatusChange = (kind: ApiUpdatingStatus['kind'], isUpdating: boolean) => void;

const POLL_DELAY_AFTER_SOCKET = 3 * SEC;
const POLL_MIN_INTERVAL = { focused: 2 * SEC, notFocused: 10 * SEC };
const BALANCE_INTERVAL = { focused: MINUTE, notFocused: 5 * MINUTE };
const INITIALIZATION_INTERVAL = { focused: MINUTE, notFocused: 5 * MINUTE };
const STAKING_INTERVAL = { focused: 5 * SEC, notFocused: 20 * SEC };
const VERSIONS_INTERVAL = { focused: 5 * MINUTE, notFocused: 15 * MINUTE };
const VESTING_INTERVAL = { focused: 10 * SEC, notFocused: MINUTE };
const TON_DNS_INTERVAL = { focused: 15 * SEC, notFocused: 2 * MINUTE };

const NFT_FULL_INTERVAL = { focused: MINUTE, notFocused: 5 * MINUTE };
const DOUBLE_CHECK_NFT_PAUSE = 5 * SEC;

export function setupActivePolling(
  accountId: string,
  account: ApiAccountWithChain<'ton'>,
  onUpdate: OnApiUpdate,
  onUpdatingStatusChange: OnUpdatingStatusChange,
  newestActivityTimestamps: ApiActivityTimestamps,
): NoneToVoidFunction {
  const balanceAndDomainPolling = setupBalanceAndDomainPolling(
    accountId,
    onUpdate,
    onUpdatingStatusChange.bind(undefined, 'balance'),
  );
  const stopActivityPolling = setupActivityPolling(
    accountId,
    account.byChain.ton.address,
    newestActivityTimestamps,
    handleWalletUpdate,
    onUpdate,
    onUpdatingStatusChange.bind(undefined, 'activities'),
  );
  const nftPolling = setupNftPolling(accountId, onUpdate);
  const walletInitializationPolling = setupWalletInitializationPolling(accountId);
  const stopWalletVersionPolling = setupWalletVersionsPolling(accountId, onUpdate);
  const stopTonDnsPolling = setupTonDnsPolling(accountId, onUpdate);
  const stopStakingPolling = setupStakingPolling(accountId, balanceAndDomainPolling.getBalances, onUpdate);
  const stopVestingPolling = setupVestingPolling(accountId, onUpdate);

  async function handleWalletUpdate() {
    // The TON balance updates in `getWalletInfo` several seconds after an activity arrive from the Toncenter socket.
    // This delay is up to 2 seconds, and 1 second is added as a safety margin.
    // We suppose that the other HTTP API data can be delayed, so we delay all socket-triggerred pollings.
    await pause(POLL_DELAY_AFTER_SOCKET);

    // These data change only when the wallet gets new activities. The other pollings don't depend on the wallet content.
    balanceAndDomainPolling.poll();
    nftPolling.poll();
    walletInitializationPolling.poll();
  }

  return () => {
    balanceAndDomainPolling.stop();
    stopActivityPolling();
    nftPolling.stop();
    stopWalletVersionPolling();
    stopTonDnsPolling();
    stopStakingPolling();
    stopVestingPolling();
  };
}

function setupBalanceAndDomainPolling(
  accountId: string,
  onUpdate: OnApiUpdate,
  onUpdatingStatusChange?: (isUpdating: boolean) => void,
) {
  const balanceUpdater = makeBalanceAndDomainUpdater(accountId, onUpdate, onUpdatingStatusChange);

  const polling = pollingLoop({
    period: BALANCE_INTERVAL,
    minDelay: POLL_MIN_INTERVAL,
    poll: balanceUpdater.update,
  });

  return {
    ...polling,
    getBalances: balanceUpdater.get,
  };
}

function makeBalanceAndDomainUpdater(
  accountId: string,
  onUpdate: OnApiUpdate,
  onUpdatingStatusChange?: (isUpdating: boolean) => void,
) {
  const { network } = parseAccountId(accountId);
  let balances: ApiBalanceBySlug | undefined;
  let balancesDeferred = new Deferred();
  let lastDomain: string | false | undefined; // Undefined means unknown, false means no domain

  async function get() {
    await balancesDeferred.promise;
    return balances!;
  }

  async function update() {
    onUpdatingStatusChange?.(true);

    try {
      const wallet = await fetchStoredWallet(accountId, 'ton');
      const [tonBalance, tokenBalances] = await Promise.all([
        getTonBalanceAndCheckDomain(wallet.address),
        loadTokenBalances(network, wallet.address, onUpdate),
      ]);

      const newBalances = {
        [TONCOIN.slug]: tonBalance,
        ...tokenBalances,
      };
      const hasChanged = !areDeepEqual(balances, newBalances);
      balances = newBalances;

      if (hasChanged) {
        onUpdate({
          type: 'updateBalances',
          accountId,
          chain: 'ton',
          balances,
        });
      }

      balancesDeferred.resolve();
    } catch (err) {
      logDebugError('setupBalanceAndDomainPolling update', err);

      // It's important to reject the deferred instead of keeping it unsettled, because otherwise the main polling cycle
      // will stuck and never retry. Creating a new deferred gives the `getBalances` callers another chance on retry.
      balancesDeferred.reject(err);
      balancesDeferred = new Deferred();
    } finally {
      onUpdatingStatusChange?.(false);
    }
  }

  async function getTonBalanceAndCheckDomain(address: string) {
    // Getting the balance and the domain go together, only because they arrive from the same endpoint
    const { balance, domain = false } = await getWalletInfo(network, address);

    if (domain !== lastDomain) {
      onUpdate({
        type: 'updateAccount',
        accountId,
        chain: 'ton',
        domain,
      });
      lastDomain = domain;
    }

    return balance;
  }

  return { get, update };
}

// A good address for testing: UQD5mxRgCuRNLxKxeOjG6r14iSroLF5FtomPnet-sgP5xI-e
function setupActivityPolling(
  accountId: string,
  address: string,
  newestConfirmedActivityTimestamps: ApiActivityTimestamps,
  onRawActivity: NoneToVoidFunction,
  onUpdate: OnApiUpdate,
  onUpdatingStatusChange: (isUpdating: boolean) => void,
) {
  let isStopped = false;
  let rawActivityStream: ActivityStream | undefined;
  let richActivityStream: RichActivityStream | undefined;

  const newestTimestamps = compact(Object.values(newestConfirmedActivityTimestamps));
  let newestConfirmedActivityTimestamp = newestTimestamps.length ? Math.max(...newestTimestamps) : undefined;

  async function loadInitialActivities() {
    try {
      onUpdatingStatusChange(true);
      return await loadInitialConfirmedActivities(accountId, onUpdate);
    } catch (err) {
      logDebugError('loadInitialConfirmedActivities', err);
      return undefined;
    } finally {
      onUpdatingStatusChange(false);
    }
  }

  function onRawActivities(confirmedActivities: ApiActivity[]) {
    if (confirmedActivities.length) {
      onRawActivity();
    }
  }

  function onRichActivities(confirmedActivities: ApiActivity[], pendingActivities: readonly ApiActivity[]) {
    confirmedActivities.slice().reverse().forEach((activity) => {
      txCallbacks.runCallbacks(activity);
    });

    onUpdate({
      type: 'newActivities',
      chain: 'ton',
      activities: confirmedActivities,
      pendingActivities,
      accountId,
    });
  }

  void (async () => {
    const doesNeedInitial = newestConfirmedActivityTimestamp === undefined;
    if (doesNeedInitial) {
      newestConfirmedActivityTimestamp = await loadInitialActivities();
      onRawActivity(); // Just in case, because new activities may have arrived while loading the initial ones
    }

    if (isStopped) return;

    rawActivityStream = new ActivityStream(
      parseAccountId(accountId).network,
      address,
      newestConfirmedActivityTimestamp,
      // If the initial activities are loaded, the polling on start is excessive
      !doesNeedInitial,
    );

    richActivityStream = new RichActivityStream(accountId, rawActivityStream);

    rawActivityStream.onUpdate(onRawActivities);
    richActivityStream.onUpdate(onRichActivities);
    richActivityStream.onLoadingChange(onUpdatingStatusChange);
  })();

  return () => {
    isStopped = true;
    richActivityStream?.destroy();
    rawActivityStream?.destroy();
  };
}

function setupNftPolling(accountId: string, onUpdate: OnApiUpdate) {
  let nftFromSec = Math.round(Date.now() / 1000);

  // The NFT updates may not become available immediately after the socket message.
  // So we check again in a few seconds.
  const updatePartial = withDoubleCheck(
    [DOUBLE_CHECK_NFT_PAUSE],
    async () => {
      try {
        const nftResult = await getNftUpdates(accountId, nftFromSec).catch(logAndRescue);

        if (nftResult) {
          let nftUpdates: ApiNftUpdate[];
          [nftFromSec, nftUpdates] = nftResult;
          nftUpdates
            .filter((update) => !(update.type === 'nftReceived' && update.nft.isHidden))
            .forEach(onUpdate);
        }
      } catch (err) {
        logDebugError('setupNftPolling updatePartial', err);
      }
    },
  );

  const fullPolling = pollingLoop({
    period: NFT_FULL_INTERVAL,
    async poll() {
      updatePartial.cancel();

      try {
        const nfts = await getAccountNfts(accountId).catch(logAndRescue);

        if (nfts) {
          nftFromSec = Math.round(Date.now() / 1000);
          onUpdate({
            type: 'updateNfts',
            accountId,
            nfts,
          });
        }
      } catch (err) {
        logDebugError('setupNftPolling updateFull', err);
      }
    },
  });

  return {
    poll: throttle(
      updatePartial.run,
      () => focusAwareDelay(...periodToMs(POLL_MIN_INTERVAL)),
    ),
    stop() {
      updatePartial.cancel();
      fullPolling.stop();
    },
  };
}

function setupStakingPolling(accountId: string, getBalances: () => Promise<ApiBalanceBySlug>, onUpdate: OnApiUpdate) {
  if (IS_STAKING_DISABLED || parseAccountId(accountId).network !== 'mainnet') {
    return () => {};
  }

  let lastStates: ApiStakingState[] | undefined;

  return pollingLoop({
    period: STAKING_INTERVAL,
    async poll() {
      try {
        const [common, balances, backendState] = await Promise.all([
          getStakingCommonCache(),
          getBalances(),
          getBackendStakingState(accountId),
        ]);
        const states = await getStakingStates(accountId, common, backendState, balances);

        const { shouldUseNominators, totalProfit } = backendState;

        if (!areDeepEqual(states, lastStates)) {
          lastStates = states;
          onUpdate({
            type: 'updateStaking',
            accountId,
            states,
            totalProfit,
            shouldUseNominators,
          });
        }
      } catch (err) {
        logDebugError('setupStakingPolling', err);
      }
    },
  }).stop;
}

async function loadInitialConfirmedActivities(accountId: string, onUpdate: OnApiUpdate) {
  let mainActivities = await fetchActivitySlice({ accountId, limit: FIRST_TRANSACTIONS_LIMIT });
  mainActivities = await swapReplaceCexActivities(accountId, mainActivities, undefined, true);

  const bySlug = {
    // Loading the TON history is a side effect of loading the main history.
    // Because there is no way to load TON activities without loading activities of other tokens.
    [TONCOIN.slug]: mainActivities.filter((activity) => getActivityTokenSlugs(activity).includes(TONCOIN.slug)),
  };

  const newestActivityTimestamp = mainActivities[0]?.timestamp;

  onUpdate({
    type: 'initialActivities',
    chain: 'ton',
    accountId,
    mainActivities,
    bySlug,
  });

  return newestActivityTimestamp;
}

function logAndRescue(err: Error) {
  logDebugError('Polling error', err);

  return undefined;
}

function setupWalletVersionsPolling(accountId: string, onUpdate: OnApiUpdate) {
  const { network } = parseAccountId(accountId);
  let lastResult: ApiWalletWithVersionInfo[] | undefined;

  return pollingLoop({
    period: VERSIONS_INTERVAL,
    async poll() {
      try {
        const { type: accountType, byChain: { ton: tonWallet } } = await fetchStoredAccount(accountId);
        if (accountType === 'bip39' || !tonWallet) {
          return 'stop';
        }

        const { publicKey, version, isInitialized } = tonWallet;

        if (!publicKey) {
          if (!isInitialized) {
            // Keep polling because `publicKey` may arrive later (for example, when the view wallet becomes initialized)
            return undefined;
          }

          // This happens when this address is not a wallet address (for example, a contract address)
          onUpdate({
            type: 'updateWalletVersions',
            accountId,
            currentVersion: version,
            versions: [],
          });
          return 'stop';
        }

        const publicKeyBytes = hexToBytes(publicKey);
        let versions = (accountType === 'ledger' ? LEDGER_WALLET_VERSIONS : POPULAR_WALLET_VERSIONS)
          .filter((value) => value !== version);

        // For W5 wallets, always include W5 to show subwallet ID variants for testnet
        if (version === 'W5') {
          versions = [...versions, 'W5'];
        }
        const versionInfos: ApiWalletWithVersionInfo[] = (await getWalletVersionInfos(
          network, publicKeyBytes, versions,
        )).map(({ wallet, ...rest }) => rest);

        // Filter out the current wallet (including the current W5 subwallet ID variant)
        const filteredVersions = versionInfos
          .filter((v) => v.address !== tonWallet.address);

        if (!areDeepEqual(versionInfos, lastResult)) {
          lastResult = versionInfos;
          onUpdate({
            type: 'updateWalletVersions',
            accountId,
            currentVersion: version,
            versions: filteredVersions,
          });
        }
      } catch (err) {
        logDebugError('setupWalletVersionsPolling', err);
      }

      return undefined;
    },
  }).stop;
}

function setupTonDnsPolling(accountId: string, onUpdate: OnApiUpdate) {
  let lastResult: Awaited<ReturnType<typeof fetchDomains>> | undefined;

  return pollingLoop({
    period: TON_DNS_INTERVAL,
    async poll() {
      try {
        const result = await fetchDomains(accountId);

        if (!areDeepEqual(result, lastResult)) {
          lastResult = result;

          onUpdate({
            type: 'updateAccountDomainData',
            accountId,
            ...pick(result, [
              'expirationByAddress',
              'linkedAddressByAddress',
              'nfts',
            ]),
          });
        }
      } catch (err) {
        logDebugError('setupTonDnsPolling', err);
      }
    },
  }).stop;
}

function setupVestingPolling(accountId: string, onUpdate: OnApiUpdate) {
  if (IS_CORE_WALLET) {
    return () => {};
  }

  let lastVestingInfo: ApiVestingInfo[] | undefined;

  return pollingLoop({
    period: VESTING_INTERVAL,
    async prepare() {
      const { isVestingEnabled } = await getBackendConfigCache();
      return isVestingEnabled;
    },
    async poll(isEnabled) {
      if (!isEnabled) {
        return 'stop';
      }

      try {
        const vestingInfo = await fetchVestings(accountId);

        if (!areDeepEqual(lastVestingInfo, vestingInfo)) {
          lastVestingInfo = vestingInfo;
          onUpdate({
            type: 'updateVesting',
            accountId,
            vestingInfo,
          });
        }
      } catch (err) {
        logDebugError('setupVestingPolling', err);
      }

      return undefined;
    },
  }).stop;
}

export function setupInactivePolling(
  accountId: string,
  account: ApiAccountWithChain<'ton'>,
  onUpdate: OnApiUpdate,
): NoneToVoidFunction {
  const { network } = parseAccountId(accountId);
  const { address } = account.byChain.ton;

  const balanceUpdater = makeBalanceAndDomainUpdater(accountId, onUpdate);

  return setupInactiveChainPolling('ton', network, address, balanceUpdater.update);
}

function setupWalletInitializationPolling(accountId: string) {
  return pollingLoop({
    period: INITIALIZATION_INTERVAL,
    minDelay: POLL_MIN_INTERVAL,
    async poll() {
      try {
        const wallet = await fetchStoredWallet(accountId, 'ton');

        if (wallet.isInitialized) {
          return 'stop';
        }

        const { network } = parseAccountId(accountId);
        const doesNeedPublicKey = !wallet.publicKey;
        let walletUpdate: Partial<ApiTonWallet> | undefined;

        if (doesNeedPublicKey) {
          // This branch isn't used always, because it makes more network requests than the other
          const updatedWallet = await getWalletFromAddress(network, wallet.address);
          if (!('error' in updatedWallet) && updatedWallet.wallet.isInitialized) {
            // It's important to load and save `version` along with `publicKey` because the app couldn't get the proper
            // wallet version without knowing the `publicKey`.
            walletUpdate = pick(updatedWallet.wallet, ['isInitialized', 'publicKey', 'version']);
          }
        } else {
          const isInitialized = await isAddressInitialized(network, wallet.address);
          if (isInitialized) {
            walletUpdate = { isInitialized };
          }
        }

        if (walletUpdate) {
          await updateStoredWallet(accountId, 'ton', walletUpdate);
        }
      } catch (err) {
        logDebugError('checkWalletInitialization', err);
      }
    },
  });
}
