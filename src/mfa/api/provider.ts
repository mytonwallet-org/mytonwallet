import type {
  ApiBackendConfig,
  ApiCurrencyRates,
  ApiEmulationResult,
  ApiInitArgs,
  ApiNetwork,
  ApiSwapAsset,
  ApiTokenDetails,
  ApiTokenWithPrice,
  OnApiUpdate,
} from '../../api/types';

import { SWAP_API_VERSION } from '../../config';
import { createPostMessageInterface } from '../../util/createPostMessageInterface';
import { omit } from '../../util/iteratees';
import { logDebugError } from '../../util/logs';
import { parseEmulation } from '../../api/chains/ton/emulation';
import { fetchEmulateTrace } from '../../api/chains/ton/toncenter/emulation';
import { getNftSuperCollectionsByCollectionAddress, tryUpdateKnownAddresses } from '../../api/common/addresses';
import { callBackendGet, callBackendPost } from '../../api/common/backend';
import { setBackendConfigCache } from '../../api/common/cache';
import { initClientId } from '../../api/common/other';
import { pollingLoop } from '../../api/common/polling/utils';
import {
  getTokensCache,
  loadTokensCache,
  sendUpdateTokens,
  tokensPreload,
  updateTokens,
} from '../../api/common/tokens';
import { MINUTE, SEC } from '../../api/constants';
import { setEnvironment } from '../../api/environment';
import { configureStorage, createStorage, withStorage } from '../../api/storages';

const BACKEND_INTERVAL = 30 * SEC;
const LONG_BACKEND_INTERVAL = MINUTE;
const MAX_POST_TOKENS = 1500;

let onUpdate: OnApiUpdate;
let stopCommonBackendPolling: NoneToVoidFunction | undefined;
let knownAddressesReadyPromise: Promise<void> | undefined;
let areKnownAddressesReady = false;

createPostMessageInterface({
  init,
  ping,
  emulateMfaMessage,
});

async function init(_onUpdate: OnApiUpdate, args: ApiInitArgs) {
  onUpdate = _onUpdate;

  const runtimeStorage = createStorage(args.storage);

  configureStorage(args.storage);
  setEnvironment(args);

  await withStorage(runtimeStorage, async () => {
    await initClientId();
  });

  void loadTokensCache();

  void Promise.allSettled([
    updateMfaKnownAddresses(),
    updateMfaTokens(),
    updateMfaCurrencyRates(),
    updateMfaSwapTokens(),
    updateMfaConfig(),
  ]);

  stopCommonBackendPolling?.();
  stopCommonBackendPolling = setupCommonBackendPolling();
}

function ping() {
  return true;
}

async function emulateMfaMessage(
  network: ApiNetwork,
  walletAddress: string,
  boc: string,
): Promise<Pick<ApiEmulationResult, 'activities' | 'realFee'>> {
  const emulation = await fetchEmulateTrace(network, boc);
  await ensureKnownAddressesReady();
  const nftSuperCollectionsByCollectionAddress = await getNftSuperCollectionsByCollectionAddress();
  const { activities, realFee } = parseEmulation(
    network,
    walletAddress,
    emulation,
    nftSuperCollectionsByCollectionAddress,
  );

  return { activities, realFee };
}

function setupCommonBackendPolling() {
  const stopFns = [
    pollingLoop({
      period: BACKEND_INTERVAL,
      skipInitialPoll: true,
      poll: updateMfaCurrencyRates,
    }).stop,
    pollingLoop({
      period: LONG_BACKEND_INTERVAL,
      skipInitialPoll: true,
      async poll() {
        await Promise.all([
          updateMfaTokens(),
          updateMfaKnownAddresses(),
          updateMfaConfig(),
          updateMfaSwapTokens(),
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

async function updateMfaTokens() {
  try {
    const tokens = await callBackendGet<ApiTokenWithPrice[]>('/assets');

    for (const token of tokens) {
      token.isFromBackend = true;
    }

    await tokensPreload.promise;
    const tokensCache = getTokensCache();
    const backendReturnedSlugs = new Set(tokens.map((token) => token.slug));
    const nonBackendTokenAddresses = Object.values(tokensCache.bySlug).reduce((result, token) => {
      if ((!token.isFromBackend || !backendReturnedSlugs.has(token.slug)) && token.tokenAddress) {
        result.push(token.tokenAddress);
      }

      return result;
    }, [] as string[]);
    const nonBackendTokenDetails = nonBackendTokenAddresses.length
      ? await callBackendPost<ApiTokenDetails[]>('/assets', {
        assets: nonBackendTokenAddresses.slice(0, MAX_POST_TOKENS),
      })
      : undefined;

    await updateTokens(tokens, () => sendUpdateTokens(onUpdate), nonBackendTokenDetails, true);
  } catch (err) {
    logDebugError('updateMfaTokens', err);
  }
}

async function updateMfaCurrencyRates() {
  try {
    const currencyRates = await callBackendGet<{ rates: ApiCurrencyRates }>('/currency-rates');

    onUpdate({
      type: 'updateCurrencyRates',
      rates: currencyRates.rates,
    });
  } catch (err) {
    logDebugError('updateMfaCurrencyRates', err);
  }
}

async function updateMfaSwapTokens() {
  try {
    const assets = await callBackendGet<ApiSwapAsset[]>('/swap/assets');

    await tokensPreload.promise;

    const tokens = assets.reduce((result: Record<string, ApiSwapAsset>, asset) => {
      result[asset.slug] = {
        ...omit(asset as any, ['blockchain']) as ApiSwapAsset,
        chain: 'blockchain' in asset ? asset.blockchain as string : asset.chain,
        tokenAddress: 'contract' in asset && asset.contract !== 'TON'
          ? asset.contract as string
          : asset.tokenAddress,
      };

      return result;
    }, {});

    onUpdate({
      type: 'updateSwapTokens',
      tokens,
    });
  } catch (err) {
    logDebugError('updateMfaSwapTokens', err);
  }
}

async function updateMfaConfig() {
  try {
    const config = await callBackendGet<ApiBackendConfig>('/utils/get-config');
    setBackendConfigCache(config);

    onUpdate({
      type: 'updateConfig',
      isLimited: config.isLimited,
      isCopyStorageEnabled: config.isCopyStorageEnabled ?? false,
      supportAccountsCount: config.supportAccountsCount,
      countryCode: config.country,
      isAppUpdateRequired: config.isUpdateRequired,
      swapVersion: config.swapVersion ?? SWAP_API_VERSION,
      seasonalTheme: config.seasonalTheme,
      knowledgeBaseVersion: config.knowledgeBaseVersion,
      preferredAgent: config.preferredAgent,
    });
  } catch (err) {
    logDebugError('updateMfaConfig', err);
  }
}

async function updateMfaKnownAddresses() {
  await tryUpdateKnownAddresses();
  areKnownAddressesReady = true;
}

function ensureKnownAddressesReady() {
  if (areKnownAddressesReady) {
    return Promise.resolve();
  }

  knownAddressesReadyPromise ??= updateMfaKnownAddresses()
    .finally(() => {
      knownAddressesReadyPromise = undefined;
    });

  return knownAddressesReadyPromise;
}
