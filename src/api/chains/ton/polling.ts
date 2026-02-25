import type {
  ApiAccountWithChain,
  ApiActivity,
  ApiActivityTimestamps,
  ApiBalanceBySlug,
  ApiNftUpdate,
  ApiStakingState,
  ApiTonWallet,
  ApiVestingInfo,
  ApiWalletWithVersionInfo,
  OnApiUpdate,
  OnUpdatingStatusChange,
} from '../../types';

import { IS_CORE_WALLET, IS_STAKING_DISABLED, POPULAR_WALLET_VERSIONS, TONCOIN } from '../../../config';
import { parseAccountId } from '../../../util/account';
import { getActivityTokenSlugs } from '../../../util/activities';
import { areDeepEqual } from '../../../util/areDeepEqual';
import { focusAwareDelay } from '../../../util/focusAwareDelay';
import { compact, pick } from '../../../util/iteratees';
import { logDebugError } from '../../../util/logs';
import { pause, throttle } from '../../../util/schedulers';
import { fetchStoredAccount, fetchStoredWallet, updateStoredWallet } from '../../common/accounts';
import { getBackendConfigCache, getStakingCommonCache } from '../../common/cache';
import { getConcurrencyLimiter } from '../../common/polling/setupInactiveChainPolling';
import {
  activeWalletTiming,
  inactiveWalletTiming,
  periodToMs,
  pollingLoop,
  withDoubleCheck,
} from '../../common/polling/utils';
import { swapReplaceActivities } from '../../common/swap';
import { sendUpdateTokens } from '../../common/tokens';
import { txCallbacks } from '../../common/txCallbacks';
import { hexToBytes } from '../../common/utils';
import { BalanceStream } from '../../common/websocket/balanceStream';
import { FIRST_TRANSACTIONS_LIMIT, MINUTE, SEC } from '../../constants';
import { getToncenterSocket } from './toncenter/socket';
import { fetchActivitySlice } from './activities';
import { getWalletFromAddress } from './auth';
import { LEDGER_WALLET_VERSIONS } from './constants';
import { fetchDomains } from './domains';
import { getNftUpdates, streamAllAccountNfts } from './nfts';
import { RichActivityStream } from './richActivityStream';
import { getBackendStakingState, getStakingStates } from './staking';
import { importUnknownTokens } from './tokens';
import { ActivityStream } from './toncenter';
import { fetchVestings } from './vesting';
import { fetchBalances, getWalletInfo, getWalletVersionInfos, isAddressInitialized } from './wallet';

const POLL_DELAY_AFTER_SOCKET = 3 * SEC;
const POLL_MIN_INTERVAL = { focused: 2 * SEC, notFocused: 10 * SEC };
const DOMAIN_INTERVAL = { focused: MINUTE, notFocused: 5 * MINUTE };
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
  const balancePolling = setupBalancePolling(
    accountId,
    account.byChain.ton.address,
    true,
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
  const domainPolling = setupDomainPolling(accountId, account.byChain.ton.address, onUpdate);
  const nftPolling = setupNftPolling(accountId, onUpdate);
  const walletInitializationPolling = setupWalletInitializationPolling(accountId);
  const stopWalletVersionPolling = setupWalletVersionsPolling(accountId, onUpdate);
  const stopTonDnsPolling = setupTonDnsPolling(accountId, nftPolling.firstFullLoadPromise, onUpdate);
  const stopStakingPolling = setupStakingPolling(accountId, balancePolling.getBalances, onUpdate);
  const stopVestingPolling = setupVestingPolling(accountId, onUpdate);

  async function handleWalletUpdate() {
    // The TON balance updates in `getWalletInfo` several seconds after an activity arrive from the Toncenter socket.
    // This delay is up to 2 seconds, and 1 second is added as a safety margin.
    // We suppose that the other HTTP API data can be delayed, so we delay all socket-triggerred pollings.
    await pause(POLL_DELAY_AFTER_SOCKET);

    // These data change only when the wallet gets new activities. The other pollings don't depend on the wallet content.
    domainPolling.poll();
    nftPolling.poll();
    walletInitializationPolling.poll();
  }

  return () => {
    balancePolling.stop();
    stopActivityPolling();
    domainPolling.stop();
    nftPolling.stop();
    stopWalletVersionPolling();
    stopTonDnsPolling();
    stopStakingPolling();
    stopVestingPolling();
  };
}

function setupBalancePolling(
  accountId: string,
  address: string,
  isActive: boolean,
  onUpdate: OnApiUpdate,
  onUpdatingStatusChange?: (isUpdating: boolean) => void,
) {
  const { network } = parseAccountId(accountId);

  const balanceStream = new BalanceStream(
    'ton',
    getToncenterSocket(network),
    network,
    address,
    () => sendUpdateTokens(onUpdate),
    isActive ? activeWalletTiming : inactiveWalletTiming,
    fetchBalances,
    importUnknownTokens,
    isActive ? undefined : getConcurrencyLimiter('ton', network),
  );

  balanceStream.onUpdate((balances) => {
    onUpdate({
      type: 'updateBalances',
      accountId,
      chain: 'ton',
      balances,
    });
  });

  if (onUpdatingStatusChange) {
    balanceStream.onLoadingChange(onUpdatingStatusChange);
  }

  return {
    stop() {
      balanceStream.destroy();
    },
    getBalances() {
      return balanceStream.getBalances();
    },
  };
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
      {
        ...activeWalletTiming,
        // If the initial activities are loaded, the polling on start is excessive
        pollOnStart: !doesNeedInitial,
      },
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

function setupDomainPolling(accountId: string, address: string, onUpdate: OnApiUpdate) {
  const { network } = parseAccountId(accountId);
  let domain: string | false | undefined; // Undefined means unknown, false means no domain

  return pollingLoop({
    period: DOMAIN_INTERVAL,
    minDelay: POLL_MIN_INTERVAL,
    async poll() {
      try {
        const { domain: newDomain = false } = await getWalletInfo(network, address);

        if (newDomain !== domain) {
          domain = newDomain;
          onUpdate({
            type: 'updateAccount',
            accountId,
            chain: 'ton',
            domain,
          });
        }
      } catch (err) {
        logDebugError('setupDomainPolling', err);
      }
    },
  });
}

function setupNftPolling(accountId: string, onUpdate: OnApiUpdate) {
  let nftFromSec = Math.round(Date.now() / 1000);
  let abortController: AbortController | undefined;
  let firstFullLoadResolve: NoneToVoidFunction | undefined;
  const firstFullLoadPromise = new Promise<void>((resolve) => {
    firstFullLoadResolve = resolve;
  });

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
      abortController?.abort();
      abortController = new AbortController();

      const streamedAddresses: string[] = [];

      try {
        await streamAllAccountNfts(accountId, {
          signal: abortController.signal,
          onBatch: (batchNfts) => {
            batchNfts.forEach((nft) => streamedAddresses.push(nft.address));
            onUpdate({
              type: 'updateNfts',
              accountId,
              chain: 'ton',
              nfts: batchNfts,
              isFullLoading: true,
            });
          },
        });

        if (abortController.signal.aborted) return;

        nftFromSec = Math.round(Date.now() / 1000);
      } catch (err) {
        logDebugError('setupNftPolling updateFull', err);
      } finally {
        if (!abortController.signal.aborted) {
          onUpdate({
            type: 'updateNfts',
            accountId,
            nfts: [],
            chain: 'ton',
            isFullLoading: false,
            streamedAddresses,
          });
        }
      }

      firstFullLoadResolve?.();
      firstFullLoadResolve = undefined;
    },
  });

  return {
    firstFullLoadPromise,
    poll: throttle(
      updatePartial.run,
      () => focusAwareDelay(...periodToMs(POLL_MIN_INTERVAL)),
    ),
    stop() {
      abortController?.abort();
      updatePartial.cancel();
      fullPolling.stop();
      firstFullLoadResolve?.();
      firstFullLoadResolve = undefined;
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
  mainActivities = await swapReplaceActivities(accountId, mainActivities, undefined, true);

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
        let versions = (
          accountType === 'ledger'
            ? Object.keys(LEDGER_WALLET_VERSIONS) as (keyof typeof LEDGER_WALLET_VERSIONS)[]
            : POPULAR_WALLET_VERSIONS
        )
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

function setupTonDnsPolling(
  accountId: string,
  waitForNftLoad: Promise<void> | undefined,
  onUpdate: OnApiUpdate,
) {
  let lastResult: Awaited<ReturnType<typeof fetchDomains>> | undefined;

  return pollingLoop({
    period: TON_DNS_INTERVAL,
    async poll() {
      if (waitForNftLoad) {
        await waitForNftLoad;
        waitForNftLoad = undefined;
      }

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
  const balancePolling = setupBalancePolling(accountId, account.byChain.ton.address, false, onUpdate);
  return balancePolling.stop;
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
