import { addCallback, removeCallback } from '../lib/teact/teactn';
import { getGlobal, setGlobal } from '../global';

import type { ApiUpdate } from '../api/types';
import type { AnimationLevel, LangCode, Theme } from '../global/types';

import { TONCOIN } from '../config';
import { INITIAL_STATE } from '../global/initialState';
import { updateCurrencyRates, updateRestrictions, updateSwapTokens, updateTokens } from '../global/reducers/misc';
import { cloneDeep } from '../util/iteratees';
import { initMfaApi } from './api/connector';

let globalReadyPromise: Promise<void> | undefined;
let tokenInfoReadyPromise: Promise<void> | undefined;
let isInitialGlobalSet = false;

const MFA_TOKEN_INFO_TIMEOUT = 5000;

export function initMfaRuntime(params: {
  animationLevel: AnimationLevel;
  langCode?: LangCode;
  theme: Theme;
}) {
  ensureMfaInitialGlobal();
  setGlobal({
    ...getGlobal(),
    settings: {
      ...getGlobal().settings,
      animationLevel: params.animationLevel,
      langCode: params.langCode ?? getGlobal().settings.langCode,
      theme: params.theme,
    },
  });

  return ensureMfaGlobalReady();
}

export function ensureMfaGlobalReady() {
  ensureMfaInitialGlobal();

  if (!globalReadyPromise) {
    globalReadyPromise = initMfaApi(handleMfaApiUpdate, {
      langCode: getGlobal().settings.langCode,
      referrer: new URLSearchParams(window.location.search).get('r') ?? undefined,
    });
  }

  return globalReadyPromise;
}

export async function ensureMfaTokenInfoReady() {
  await ensureMfaGlobalReady();

  const initialTokensBySlug = getGlobal().tokenInfo.bySlug;
  if (isMfaTokenInfoReady(initialTokensBySlug, initialTokensBySlug)) {
    return;
  }

  if (!tokenInfoReadyPromise) {
    tokenInfoReadyPromise = new Promise<void>((resolve) => {
      let isResolved = false;
      const timeoutId = globalThis.setTimeout(() => {
        // eslint-disable-next-line no-console
        console.warn('[MFA] tokenInfo wait timed out');
        finish();
      }, MFA_TOKEN_INFO_TIMEOUT);

      const finish = () => {
        if (isResolved) return;
        isResolved = true;
        removeCallback(onGlobalChange);
        globalThis.clearTimeout(timeoutId);
        resolve();
      };

      const onGlobalChange = (global: ReturnType<typeof getGlobal>) => {
        if (isMfaTokenInfoReady(global.tokenInfo.bySlug, initialTokensBySlug)) {
          // eslint-disable-next-line no-console
          console.info('[MFA] tokenInfo ready');
          finish();
        }
      };
      addCallback(onGlobalChange);
      onGlobalChange(getGlobal());
    }).finally(() => {
      tokenInfoReadyPromise = undefined;
    });
  }

  await tokenInfoReadyPromise;
}

function isMfaTokenInfoReady(
  tokensBySlug = getGlobal().tokenInfo.bySlug,
  initialTokensBySlug?: ReturnType<typeof getGlobal>['tokenInfo']['bySlug'],
) {
  const toncoin = tokensBySlug[TONCOIN.slug];
  const initialToncoin = initialTokensBySlug?.[TONCOIN.slug];

  if (!toncoin?.image) {
    return false;
  }

  return !initialTokensBySlug
    || tokensBySlug !== initialTokensBySlug
    || toncoin !== initialToncoin;
}

function ensureMfaInitialGlobal() {
  if (isInitialGlobalSet) {
    return;
  }

  setGlobal(cloneDeep(INITIAL_STATE));
  isInitialGlobalSet = true;
}

function handleMfaApiUpdate(update: ApiUpdate) {
  let global = getGlobal();

  switch (update.type) {
    case 'updateTokens':
      global = updateTokens(global, update.tokens, true);
      break;

    case 'updateSwapTokens':
      global = updateSwapTokens(global, update.tokens);
      break;

    case 'updateCurrencyRates':
      global = updateCurrencyRates(global, update.rates);
      break;

    case 'updateConfig':
      global = updateRestrictions(global, {
        isLimitedRegion: update.isLimited,
        isCopyStorageEnabled: update.isCopyStorageEnabled,
        supportAccountsCount: update.supportAccountsCount,
        countryCode: update.countryCode,
      });
      global = {
        ...global,
        isAppUpdateRequired: update.isAppUpdateRequired,
        seasonalTheme: update.seasonalTheme,
        swapVersion: update.swapVersion ?? global.swapVersion,
      };
      break;

    default:
      return;
  }

  setGlobal(global);
}
