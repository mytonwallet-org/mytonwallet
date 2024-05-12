import type { ApiTonConnectProof } from '../api/tonConnect/types';
import type {
  ApiActivity,
  ApiAnyDisplayError,
  ApiBalanceBySlug,
  ApiBaseCurrency,
  ApiDapp,
  ApiDappPermissions,
  ApiDappTransfer,
  ApiHistoryList,
  ApiLedgerDriver,
  ApiNetwork,
  ApiNft,
  ApiParsedPayload,
  ApiPriceHistoryPeriod,
  ApiSite,
  ApiStakingHistory,
  ApiStakingType,
  ApiSwapAsset,
  ApiToken,
  ApiTransaction,
  ApiTransactionActivity,
  ApiUpdate,
  ApiUpdateDappConnect,
  ApiUpdateDappLoading,
  ApiUpdateDappSendTransactions,
  ApiWalletInfo,
  ApiWalletVersion,
} from '../api/types';
import type { AuthConfig } from '../util/authApi/types';
import type { LedgerWalletInfo } from '../util/ledger/types';

export type AnimationLevel = 0 | 1 | 2;
export type Theme = 'light' | 'dark' | 'system';
export type NotificationType = {
  icon?: string;
  message: string;
};
export type DialogType = {
  title?: string;
  message: string;
};

export type LangCode = 'en' | 'es' | 'ru' | 'zh-Hant' | 'zh-Hans' | 'tr' | 'de' | 'th';

export interface LangItem {
  langCode: LangCode;
  name: string;
  nativeName: string;
  rtl: boolean;
}

export interface LangString {
  value?: string;
}

export type LangPack = Record<string, string | LangString>;

export type StakingStatus = 'active' | 'unstakeRequested';

export type AuthMethod = 'createAccount' | 'importMnemonic' | 'importHardwareWallet';

export enum AppState {
  Auth,
  Main,
  Settings,
  Ledger,
  Inactive,
}

export enum AuthState {
  none,
  createWallet,
  checkPassword,
  createPin,
  confirmPin,
  createBiometrics,
  confirmBiometrics,
  createNativeBiometrics,
  createPassword,
  createBackup,
  disclaimerAndBackup,
  importWalletCheckPassword,
  importWallet,
  importWalletCreatePin,
  importWalletConfirmPin,
  importWalletCreateNativeBiometrics,
  importWalletCreateBiometrics,
  importWalletConfirmBiometrics,
  importWalletCreatePassword,
  disclaimer,
  ready,
  about,
}

export enum BiometricsState {
  None,
  TurnOnPasswordConfirmation,
  TurnOnRegistration,
  TurnOnVerification,
  TurnOnComplete,
  TurnOffWarning,
  TurnOffBiometricConfirmation,
  TurnOffCreatePassword,
  TurnOffComplete,
}

export enum TransferState {
  None,
  WarningHardware,
  Initial,
  Confirm,
  Password,
  ConnectHardware,
  ConfirmHardware,
  Complete,
}

export enum SwapState {
  None,
  Initial,
  Blockchain,
  WaitTokens,
  Password,
  ConnectHardware,
  ConfirmHardware,
  Complete,
  SelectTokenFrom,
  SelectTokenTo,
}

export enum SwapFeeSource {
  In,
  Out,
}

export enum SwapInputSource {
  In,
  Out,
}

export enum SwapErrorType {
  UnexpectedError,
  InvalidPair,
  NotEnoughLiquidity,

  ChangellyMinSwap,
  ChangellyMaxSwap,
}

export enum SwapType {
  OnChain,
  CrosschainFromTon,
  CrosschainToTon,
}

export enum DappConnectState {
  Info,
  Password,
  ConnectHardware,
  ConfirmHardware,
}

export enum HardwareConnectState {
  Connect,
  Connecting,
  Failed,
  ConnectedWithSeveralWallets,
  ConnectedWithSingleWallet,
  WaitingForBrowser,
}

export enum StakingState {
  None,

  StakeInitial,
  StakePassword,
  StakeComplete,

  UnstakeInitial,
  UnstakePassword,
  UnstakeComplete,

  NotEnoughBalance,
}

export enum SettingsState {
  Initial,
  Appearance,
  Assets,
  Dapps,
  Language,
  About,
  Disclaimer,
  NativeBiometricsTurnOn,
  SelectTokenList,
  WalletVersion,
}

export enum ActiveTab {
  Receive,
  Transfer,
  Swap,
  Stake,
}

export enum ContentTab {
  Assets,
  Activity,
  Explore,
  Nft,
  NotcoinVouchers,
}

export enum MediaType {
  Nft,
}

export type UserToken = {
  amount: bigint;
  name: string;
  symbol: string;
  image?: string;
  slug: string;
  price: number;
  priceUsd: number;
  decimals: number;
  change24h: number;
  isDisabled?: boolean;
  canSwap?: boolean;
  keywords?: string[];
  cmcSlug?: string;
  totalValue: string;
  color?: string;
};

export type UserSwapToken = {
  blockchain: string;
  isPopular: boolean;
  contract?: string;
} & Omit<UserToken, 'change24h'>;

export type TokenPeriod = '1D' | '7D' | '1M' | '3M' | '1Y' | 'ALL';

export type PriceHistoryPeriods = Partial<Record<ApiPriceHistoryPeriod, ApiHistoryList>>;

export interface Account {
  title?: string;
  address: string;
  isHardware?: boolean;
  ledger?: {
    index: number;
    driver: ApiLedgerDriver;
  };
}

export interface AssetPairs {
  [slug: string]: {
    isReverseProhibited?: boolean;
  };
}

export interface AccountState {
  balances?: {
    bySlug: ApiBalanceBySlug;
  };
  activities?: {
    isLoading?: boolean;
    byId: Record<string, ApiActivity>;
    idsBySlug?: Record<string, string[]>;
    newestTransactionsBySlug?: Record<string, ApiTransaction>;
    isMainHistoryEndReached?: boolean;
    isHistoryEndReachedBySlug?: Record<string, boolean>;
    localTransactions?: ApiTransactionActivity[];
  };
  nfts?: {
    byAddress: Record<string, ApiNft>;
    orderedAddresses?: string[];
    currentCollectionAddress?: string;
    selectedAddresses?: string[];
  };
  isBackupRequired?: boolean;
  activeDappOrigin?: string;
  currentTokenSlug?: string;
  currentActivityId?: string;
  currentTokenPeriod?: TokenPeriod;
  savedAddresses?: Record<string, string>;
  activeContentTab?: ContentTab;
  landscapeActionsActiveTabIndex?: ActiveTab;

  // Staking
  staking?: {
    type: ApiStakingType;
    balance: bigint;
    apy: number;
    isUnstakeRequested: boolean;
    start: number;
    end: number;
    totalProfit: bigint;
    // liquid
    unstakeRequestedAmount?: bigint;
    tokenBalance?: bigint;
    isInstantUnstakeRequested?: boolean;
  };
  stakingHistory?: ApiStakingHistory;
  browserHistory?: string[];

  isLongUnstakeRequested?: boolean;
}

export interface AccountSettings {
  orderedSlugs?: string[];
  exceptionSlugs?: string[];
  deletedSlugs?: string[];
}

export interface NftTransfer {
  name?: string;
  address: string;
  thumbnail: string;
  collectionName?: string;
}

export type GlobalState = {
  DEBUG_capturedId?: number;

  appState: AppState;

  auth: {
    state: AuthState;
    biometricsStep?: 1 | 2;
    method?: AuthMethod;
    isLoading?: boolean;
    mnemonic?: string[];
    mnemonicCheckIndexes?: number[];
    accountId?: string;
    address?: string;
    error?: string;
    password?: string;
    isBackupModalOpen?: boolean;
  };

  biometrics: {
    state: BiometricsState;
    error?: string;
    password?: string;
  };

  nativeBiometricsError?: string;

  hardware: {
    hardwareState?: HardwareConnectState;
    hardwareWallets?: LedgerWalletInfo[];
    hardwareSelectedIndices?: number[];
    isRemoteTab?: boolean;
    isLedgerConnected?: boolean;
    isTonAppConnected?: boolean;
  };

  currentTransfer: {
    state: TransferState;
    isLoading?: boolean;
    tokenSlug?: string;
    toAddress?: string;
    toAddressName?: string;
    resolvedAddress?: string;
    error?: string;
    amount?: bigint;
    fee?: bigint;
    comment?: string;
    binPayload?: string;
    promiseId?: string;
    txId?: string;
    rawPayload?: string;
    parsedPayload?: ApiParsedPayload;
    stateInit?: string;
    shouldEncrypt?: boolean;
    isToNewAddress?: boolean;
    isScam?: boolean;
    nfts?: ApiNft[];
    sentNftsCount?: number;
  };

  currentSwap: {
    state: SwapState;
    slippage: number;
    tokenInSlug?: string;
    tokenOutSlug?: string;
    amountIn?: string;
    amountOut?: string;
    amountOutMin?: string;
    transactionFee?: string;
    networkFee?: number;
    realNetworkFee?: number;
    swapFee?: string;
    priceImpact?: number;
    dexLabel?: string;
    activityId?: string;
    error?: string;
    errorType?: SwapErrorType;
    isLoading?: boolean;
    shouldEstimate?: boolean;
    isEstimating?: boolean;
    inputSource?: SwapInputSource;
    swapType?: SwapType;
    feeSource?: SwapFeeSource;
    toAddress?: string;
    payinAddress?: string;
    payinExtraId?: string;
    pairs?: {
      bySlug: Record<string, AssetPairs>;
    };
    limits?: {
      fromMin?: string;
      fromMax?: string;
    };
    isSettingsModalOpen?: boolean;
  };

  currentSignature?: {
    promiseId: string;
    dataHex: string;
    error?: string;
    isSigned?: boolean;
  };

  exploreSites?: ApiSite[];

  currentDappTransfer: {
    state: TransferState;
    isSse?: boolean;
    promiseId?: string;
    isLoading?: boolean;
    transactions?: ApiDappTransfer[];
    viewTransactionOnIdx?: number;
    fee?: bigint;
    dapp?: ApiDapp;
    error?: string;
  };

  dappConnectRequest?: {
    state: DappConnectState;
    isSse?: boolean;
    promiseId?: string;
    accountId?: string;
    dapp: ApiDapp;
    permissions?: ApiDappPermissions;
    proof?: ApiTonConnectProof;
    error?: string;
  };

  staking: {
    state: StakingState;
    isLoading?: boolean;
    isUnstaking?: boolean;
    amount?: bigint;
    tokenAmount?: bigint;
    fee?: bigint;
    error?: string;
    type?: ApiStakingType;
  };

  stakingInfo: {
    liquid?: {
      instantAvailable: bigint;
    };
  };

  accounts?: {
    byId: Record<string, Account>;
    isLoading?: boolean;
    error?: string;
  };

  tokenInfo: {
    bySlug: Record<string, ApiToken>;
  };

  swapTokenInfo: {
    bySlug: Record<string, ApiSwapAsset>;
  };

  tokenPriceHistory: {
    bySlug: Record<string, PriceHistoryPeriods>;
  };

  byAccountId: Record<string, AccountState>;

  walletVersions?: {
    currentVersion: ApiWalletVersion;
    byId: Record<string, ApiWalletInfo[]>;
  };

  settings: {
    state: SettingsState;
    theme: Theme;
    animationLevel: AnimationLevel;
    langCode: LangCode;
    dapps: ApiDapp[];
    byAccountId: Record<string, AccountSettings>;
    areTinyTransfersHidden?: boolean;
    canPlaySounds?: boolean;
    isInvestorViewEnabled?: boolean;
    isTonProxyEnabled?: boolean;
    isTonMagicEnabled?: boolean;
    isDeeplinkHookEnabled?: boolean;
    isPasswordNumeric?: boolean; // Backwards compatibility for non-numeric passwords from older versions
    isTestnet?: boolean;
    isSecurityWarningHidden?: boolean;
    areTokensWithNoCostHidden: boolean;
    isSortByValueEnabled?: boolean;
    importToken?: {
      isLoading?: boolean;
      token?: UserToken | UserSwapToken;
    };
    authConfig?: AuthConfig;
    baseCurrency?: ApiBaseCurrency;
    isLimitedRegion?: boolean;
  };

  dialogs: DialogType[];
  notifications: NotificationType[];
  currentAccountId?: string;
  isAddAccountModalOpen?: boolean;
  isBackupWalletModalOpen?: boolean;
  isHardwareModalOpen?: boolean;
  isStakingInfoModalOpen?: boolean;
  isQrScannerOpen?: boolean;
  areSettingsOpen?: boolean;
  isAppUpdateAvailable?: boolean;
  confettiRequestedAt?: number;
  isPinAccepted?: boolean;
  isOnRampWidgetModalOpen?: boolean;
  isReceiveModalOpen?: boolean;
  shouldForceAccountEdit?: boolean;
  isIncorrectTimeNotificationReceived?: boolean;
  currentBrowserUrl?: string;

  currentQrScan?: {
    currentTransfer?: GlobalState['currentTransfer'];
    currentSwap?: GlobalState['currentSwap'];
  };

  latestAppVersion?: string;
  stateVersion: number;
  restrictions: {
    isLimitedRegion: boolean;
    isSwapDisabled: boolean;
    isOnRampDisabled: boolean;
    isCopyStorageEnabled?: boolean;
  };

  mediaViewer: {
    mediaId?: string;
    mediaType?: MediaType;
  };

  isLoadingOverlayOpen?: boolean;
};

export interface ActionPayloads {
  // Initial
  init: undefined;
  initApi: undefined;
  afterInit: undefined;
  apiUpdate: ApiUpdate;
  resetAuth: undefined;
  startCreatingWallet: undefined;
  afterCheckMnemonic: undefined;
  skipCheckMnemonic: undefined;
  restartCheckMnemonicIndexes: undefined;
  cancelDisclaimer: undefined;
  afterCreatePassword: { password: string; isPasswordNumeric?: boolean };
  startCreatingBiometrics: undefined;
  afterCreateBiometrics: undefined;
  skipCreateBiometrics: undefined;
  cancelCreateBiometrics: undefined;
  afterCreateNativeBiometrics: undefined;
  skipCreateNativeBiometrics: undefined;
  createPin: { pin: string; isImporting: boolean };
  confirmPin: { isImporting: boolean };
  cancelConfirmPin: { isImporting: boolean };
  startImportingWallet: undefined;
  afterImportMnemonic: { mnemonic: string[] };
  startImportingHardwareWallet: { driver: ApiLedgerDriver };
  confirmDisclaimer: undefined;
  afterConfirmDisclaimer: undefined;
  cleanAuthError: undefined;
  openAbout: undefined;
  closeAbout: undefined;
  openAuthBackupWalletModal: undefined;
  closeAuthBackupWalletModal: { isBackupCreated?: boolean } | undefined;
  initializeHardwareWalletConnection: undefined;
  connectHardwareWallet: undefined;
  createHardwareAccounts: undefined;
  loadMoreHardwareWallets: { lastIndex: number };
  createAccount: { password: string; isImporting: boolean; isPasswordNumeric?: boolean };
  afterSelectHardwareWallets: { hardwareSelectedIndices: number[] };
  resetApiSettings: { areAllDisabled?: boolean } | undefined;
  checkAppVersion: undefined;
  importAccountByVersion: { version: ApiWalletVersion };

  selectToken: { slug?: string } | undefined;
  openBackupWalletModal: undefined;
  closeBackupWalletModal: undefined;
  setIsBackupRequired: { isMnemonicChecked: boolean };
  openHardwareWalletModal: undefined;
  closeHardwareWalletModal: undefined;
  resetHardwareWalletConnect: undefined;
  setTransferScreen: { state: TransferState };
  setTransferAmount: { amount?: bigint };
  setTransferToAddress: { toAddress?: string };
  setTransferComment: { comment?: string };
  setTransferShouldEncrypt: { shouldEncrypt?: boolean };
  startTransfer: {
    isPortrait?: boolean;
    tokenSlug?: string;
    amount?: bigint;
    toAddress?: string;
    comment?: string;
    nfts?: ApiNft[];
    binPayload?: string;
  } | undefined;
  changeTransferToken: { tokenSlug: string };
  fetchFee: {
    tokenSlug: string;
    amount: bigint;
    toAddress: string;
    comment?: string;
    shouldEncrypt?: boolean;
    binPayload?: string;
  };
  fetchNftFee: {
    toAddress: string;
    nftAddresses: string[];
    comment?: string;
  };
  submitTransferInitial: {
    tokenSlug: string;
    amount: bigint;
    toAddress: string;
    comment?: string;
    shouldEncrypt?: boolean;
    nftAddresses?: string[];
  };
  submitTransferConfirm: undefined;
  submitTransferPassword: { password: string };
  submitTransferHardware: undefined;
  clearTransferError: undefined;
  cancelTransfer: { shouldReset?: boolean } | undefined;
  showDialog: { title?: string; message: string };
  dismissDialog: undefined;
  showError: { error?: ApiAnyDisplayError | string };
  showNotification: { message: string; icon?: string };
  dismissNotification: undefined;
  initLedgerPage: undefined;
  afterSignIn: { isFirstLogin: boolean } | undefined;
  signOut: { isFromAllAccounts?: boolean } | undefined;
  cancelCaching: undefined;
  afterSignOut: { isFromAllAccounts?: boolean } | undefined;
  addAccount: { method: AuthMethod; password: string; isAuthFlow?: boolean };
  addAccount2: { method: AuthMethod; password: string };
  switchAccount: { accountId: string; newNetwork?: ApiNetwork };
  renameAccount: { accountId: string; title: string };
  clearAccountError: undefined;
  validatePassword: { password: string };
  verifyHardwareAddress: undefined;

  fetchTokenTransactions: { limit: number; slug: string; shouldLoadWithBudget?: boolean };
  fetchAllTransactions: { limit: number; shouldLoadWithBudget?: boolean };
  resetIsHistoryEndReached: { slug: string } | undefined;
  fetchNfts: undefined;
  showActivityInfo: { id: string };
  closeActivityInfo: { id: string };
  openNftCollection: { address: string };
  closeNftCollection: undefined;
  selectNfts: { addresses: string[] };
  clearNftSelection: { address: string };
  clearNftsSelection: undefined;

  submitSignature: { password: string };
  clearSignatureError: undefined;
  cancelSignature: undefined;

  addSavedAddress: { address: string; name: string };
  removeFromSavedAddress: { address: string };

  setCurrentTokenPeriod: { period: TokenPeriod };
  openAddAccountModal: undefined;
  closeAddAccountModal: undefined;

  setLandscapeActionsActiveTabIndex: { index: ActiveTab };
  setActiveContentTab: { tab: ContentTab };

  requestConfetti: undefined;
  setIsPinAccepted: undefined;
  clearIsPinAccepted: undefined;

  requestOpenQrScanner: undefined;
  closeQrScanner: undefined;
  handleQrCode: { data: string };

  // Staking
  startStaking: { isUnstaking?: boolean } | undefined;
  setStakingScreen: { state: StakingState };
  submitStakingInitial: { amount?: bigint; isUnstaking?: boolean } | undefined;
  submitStakingPassword: { password: string; isUnstaking?: boolean };
  clearStakingError: undefined;
  cancelStaking: undefined;
  fetchStakingHistory: { limit?: number; offset?: number } | undefined;
  fetchStakingFee: { amount: bigint };
  openStakingInfo: undefined;
  closeStakingInfo: undefined;

  // Settings
  openSettings: undefined;
  openSettingsWithState: { state: SettingsState };
  setSettingsState: { state?: SettingsState };
  closeSettings: undefined;
  setTheme: { theme: Theme };
  setAnimationLevel: { level: AnimationLevel };
  toggleTinyTransfersHidden: { isEnabled?: boolean } | undefined;
  toggleInvestorView: { isEnabled?: boolean } | undefined;
  toggleCanPlaySounds: { isEnabled?: boolean } | undefined;
  toggleTonProxy: { isEnabled: boolean };
  toggleTonMagic: { isEnabled: boolean };
  toggleDeeplinkHook: { isEnabled: boolean };
  startChangingNetwork: { network: ApiNetwork };
  changeNetwork: { network: ApiNetwork };
  changeLanguage: { langCode: LangCode };
  closeSecurityWarning: undefined;
  toggleTokensWithNoCost: { isEnabled: boolean };
  toggleSortByValue: { isEnabled: boolean };
  initTokensOrder: undefined;
  updateDeletionListForActiveTokens: { accountId: string } | undefined;
  sortTokens: { orderedSlugs: string[] };
  toggleExceptionToken: { slug: string };
  addToken: { token: UserToken };
  deleteToken: { slug: string };
  importToken: { address: string; isSwap?: boolean };
  resetImportToken: undefined;
  closeBiometricSettings: undefined;
  openBiometricsTurnOn: undefined;
  openBiometricsTurnOffWarning: undefined;
  openBiometricsTurnOff: undefined;
  enableBiometrics: { password: string };
  disableBiometrics: { password: string; isPasswordNumeric?: boolean };
  enableNativeBiometrics: { password: string };
  disableNativeBiometrics: undefined;
  changeBaseCurrency: { currency: ApiBaseCurrency };
  clearNativeBiometricsError: undefined;
  copyStorageData: undefined;

  // TON Connect
  submitDappConnectRequestConfirm: { accountId: string; password?: string };
  submitDappConnectRequestConfirmHardware: { accountId: string };
  clearDappConnectRequestError: undefined;
  cancelDappConnectRequestConfirm: undefined;
  setDappConnectRequestState: { state: DappConnectState };
  showDappTransfer: { transactionIdx: number };
  setDappTransferScreen: { state: TransferState };
  clearDappTransferError: undefined;
  submitDappTransferConfirm: undefined;
  submitDappTransferPassword: { password: string };
  submitDappTransferHardware: undefined;
  cancelDappTransfer: undefined;
  closeDappTransfer: undefined;

  getDapps: undefined;
  deleteAllDapps: undefined;
  deleteDapp: { origin: string };
  loadExploreSites: undefined;

  addSiteToBrowserHistory: { url: string };
  removeSiteFromBrowserHistory: { url: string };
  openBrowser: { url: string };
  closeBrowser: undefined;

  apiUpdateDappConnect: ApiUpdateDappConnect;
  apiUpdateDappSendTransaction: ApiUpdateDappSendTransactions;
  apiUpdateDappLoading: ApiUpdateDappLoading;
  apiUpdateDappCloseLoading: undefined;

  // Swap
  submitSwap: { password: string };
  startSwap: {
    state?: SwapState;
    tokenInSlug?: string;
    tokenOutSlug?: string;
    amountIn?: string;
    toAddress?: string;
  } | undefined;
  cancelSwap: { shouldReset?: boolean } | undefined;
  setDefaultSwapParams: { tokenInSlug?: string; tokenOutSlug?: string } | undefined;
  switchSwapTokens: undefined;
  setSwapTokenIn: { tokenSlug: string };
  setSwapTokenOut: { tokenSlug: string };
  setSwapAmountIn: { amount?: string };
  setSwapAmountOut: { amount?: string };
  setSlippage: { slippage: number };
  loadSwapPairs: { tokenSlug: string; shouldForceUpdate?: boolean };
  estimateSwap: { shouldBlock: boolean };
  setSwapScreen: { state: SwapState };
  clearSwapError: undefined;
  estimateSwapCex: { shouldBlock: boolean };
  submitSwapCexFromTon: { password: string };
  submitSwapCexToTon: { password: string };
  setSwapType: { type: SwapType };
  setSwapCexAddress: { toAddress: string };
  addSwapToken: { token: UserSwapToken };
  toggleSwapSettingsModal: { isOpen: boolean };

  openOnRampWidgetModal: undefined;
  closeOnRampWidgetModal: undefined;

  // MediaViewer
  openMediaViewer: { mediaId: string; mediaType: MediaType };
  closeMediaViewer: undefined;

  openReceiveModal: undefined;
  closeReceiveModal: undefined;

  loadPriceHistory: { slug: string; period: ApiPriceHistoryPeriod; currency?: ApiBaseCurrency };

  showIncorrectTimeError: undefined;

  openLoadingOverlay: undefined;
  closeLoadingOverlay: undefined;
}

export enum LoadMoreDirection {
  Forwards,
  Backwards,
}
