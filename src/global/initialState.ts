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
  TransferState,
} from './types';

import {
  ANIMATION_LEVEL_DEFAULT,
  DEFAULT_AUTOLOCK_OPTION,
  DEFAULT_SLIPPAGE_VALUE,
  DEFAULT_STAKING_STATE,
  DEFAULT_TRANSFER_TOKEN_SLUG,
  INIT_SWAP_ASSETS,
  IS_CORE_WALLET,
  SHOULD_SHOW_ALL_ASSETS_AND_ACTIVITY,
  SWAP_API_VERSION,
  THEME_DEFAULT,
  TOKEN_INFO,
} from '../config';
import { IS_IOS_APP, USER_AGENT_LANG_CODE } from '../util/windowEnvironment';

export const STATE_VERSION = 46;

export const INITIAL_STATE: GlobalState = {
  appState: AppState.Auth,

  auth: {
    state: AuthState.none,
  },

  biometrics: {
    state: BiometricsState.None,
  },

  hardware: {
    hardwareState: HardwareConnectState.Connect,
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
    bySlug: TOKEN_INFO,
  },

  swapTokenInfo: {
    bySlug: INIT_SWAP_ASSETS,
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
    isSortByValueEnabled: true,
    isAppLockEnabled: true,
    autolockValue: DEFAULT_AUTOLOCK_OPTION,
  },

  byAccountId: {},

  dialogs: [],
  notifications: [],

  stateVersion: STATE_VERSION,
  restrictions: {
    isLimitedRegion: false,
    isSwapDisabled: IS_IOS_APP || IS_CORE_WALLET,
    isOnRampDisabled: IS_IOS_APP || IS_CORE_WALLET,
    isNftBuyingDisabled: IS_IOS_APP,
  },

  mediaViewer: {},

  pushNotifications: {
    enabledAccounts: {},
  },
};
