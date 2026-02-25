import type { ApiCurrencyRates } from '../api/types';
import type { GlobalState } from './types';
import {
  AppState,
  AuthState,
  BiometricsState,
  DomainLinkingState,
  DomainRenewalState,
  HardwareConnectState,
  SettingsState,
  SignDataState,
  StakingState,
  SwapState,
  TransactionInfoState,
  TransferState,
} from './types';

import {
  ANIMATION_LEVEL_DEFAULT,
  CURRENCIES,
  DEFAULT_AUTOLOCK_OPTION,
  DEFAULT_PRICE_CURRENCY,
  DEFAULT_SLIPPAGE_VALUE,
  DEFAULT_STAKING_STATE,
  DEFAULT_TRANSFER_TOKEN_SLUG,
  INIT_SWAP_ASSETS,
  IS_CORE_WALLET,
  IS_EXPLORER,
  SHOULD_SHOW_ALL_ASSETS_AND_ACTIVITY,
  SWAP_API_VERSION,
  THEME_DEFAULT,
} from '../config';
import { getTokenInfo } from '../util/chain';
import { buildCollectionByKey, mapValues } from '../util/iteratees';
import { IS_IOS_APP, USER_AGENT_LANG_CODE } from '../util/windowEnvironment';

export const STATE_VERSION = 53;

export const INITIAL_STATE: GlobalState = {
  appState: IS_EXPLORER ? AppState.Main : AppState.Auth,

  auth: {
    state: AuthState.none,
  },

  biometrics: {
    state: BiometricsState.None,
  },

  hardware: {
    hardwareState: HardwareConnectState.Connect,
    chain: 'ton',
  },

  currentTransfer: {
    state: TransferState.None,
    tokenSlug: DEFAULT_TRANSFER_TOKEN_SLUG,
  },

  currentDomainRenewal: {
    state: DomainRenewalState.None,
  },

  currentDomainLinking: {
    state: DomainLinkingState.None,
  },

  currentSwap: {
    state: SwapState.None,
    slippage: DEFAULT_SLIPPAGE_VALUE,
  },

  currentDappTransfer: {
    state: TransferState.None,
  },

  currentDappSignData: {
    state: SignDataState.None,
  },

  currentStaking: {
    state: StakingState.None,
  },

  stakingDefault: DEFAULT_STAKING_STATE,

  tokenInfo: {
    bySlug: getTokenInfo(),
  },

  swapTokenInfo: {
    bySlug: buildCollectionByKey(Object.values(INIT_SWAP_ASSETS), 'slug'),
  },

  swapVersion: SWAP_API_VERSION,

  tokenPriceHistory: {
    bySlug: {},
  },

  settings: {
    state: SettingsState.Initial,
    theme: THEME_DEFAULT,
    animationLevel: ANIMATION_LEVEL_DEFAULT,
    areTinyTransfersHidden: !SHOULD_SHOW_ALL_ASSETS_AND_ACTIVITY,
    canPlaySounds: true,
    langCode: USER_AGENT_LANG_CODE,
    byAccountId: {},
    areTokensWithNoCostHidden: !SHOULD_SHOW_ALL_ASSETS_AND_ACTIVITY,
    isAppLockEnabled: true,
    autolockValue: DEFAULT_AUTOLOCK_OPTION,
    baseCurrency: DEFAULT_PRICE_CURRENCY,
  },

  byAccountId: {},

  dialogs: [],
  toasts: [],

  stateVersion: STATE_VERSION,
  currentTemporaryViewAccountId: undefined,

  restrictions: {
    isLimitedRegion: false,
    isSwapDisabled: IS_IOS_APP || IS_CORE_WALLET,
    isOnRampDisabled: IS_IOS_APP || IS_CORE_WALLET,
    isOffRampDisabled: IS_IOS_APP || IS_CORE_WALLET,
    isNftBuyingDisabled: IS_IOS_APP,
  },

  mediaViewer: {},

  currentTransactionInfo: {
    state: TransactionInfoState.None,
  },

  pushNotifications: {
    enabledAccounts: [],
  },

  currencyRates: mapValues(CURRENCIES, (currency) => currency.fallbackRate) as ApiCurrencyRates,
};
