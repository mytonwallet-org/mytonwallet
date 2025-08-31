import type { SignDataPayload } from '@tonconnect/protocol';
import type { TeactNode } from '../lib/teact/teact';

import type { ApiFetchEstimateDieselResult, ApiTonWalletVersion } from '../api/chains/ton/types';
import type { ApiTonConnectProof } from '../api/tonConnect/types';
import type {
  ApiAccountConfig,
  ApiActivity,
  ApiAnyDisplayError,
  ApiBalanceBySlug,
  ApiBaseCurrency,
  ApiChain,
  ApiCountryCode,
  ApiDapp,
  ApiDappPermissions,
  ApiDappTransfer,
  ApiEmulationResult,
  ApiHistoryList,
  ApiImportAddressByChain,
  ApiLedgerDriver,
  ApiMtwCardType,
  ApiNetwork,
  ApiNft,
  ApiNotificationsAccountValue,
  ApiPriceHistoryPeriod,
  ApiSite,
  ApiSiteCategory,
  ApiStakingHistory,
  ApiStakingState,
  ApiSwapAsset,
  ApiSwapDexLabel,
  ApiSwapEstimateVariant,
  ApiSwapVersion,
  ApiTokenType,
  ApiTokenWithPrice,
  ApiUpdate,
  ApiUpdateDappCloseLoading,
  ApiUpdateDappConnect,
  ApiUpdateDappLoading,
  ApiUpdateDappSendTransactions,
  ApiUpdateDappSignData,
  ApiUpdateWalletVersions,
  ApiVestingInfo,
  ApiWalletWithVersionInfo,
} from '../api/types';
import type { AUTOLOCK_OPTIONS_LIST } from '../config';
import type { AuthConfig } from '../util/authApi/types';
import type { CapacitorPlatform } from '../util/capacitor/platform';
import type { LedgerTransport, LedgerWalletInfo } from '../util/ledger/types';

export type IAnchorPosition = {
  x: number;
  y: number;
};

export type AnimationLevel = 0 | 1 | 2;
export type Theme = 'light' | 'dark' | 'system';
export type AppTheme = 'dark' | 'light';
export type AppLayout = 'portrait' | 'landscape';
export type DialogAction = 'openBluetoothSettings' | 'signOutAll';

export type NotificationType = {
  icon?: string;
  message: string;
};

export type DialogType = {
  title?: string;
  message: string | TeactNode;
  entities?: Record<string, any>;
  noBackdropClose?: boolean;
  isInAppLock?: boolean;
  buttons?: {
    confirm: { title?: string; action?: DialogAction; isDestructive?: boolean };
    cancel?: { title?: string };
  };
};

export type LangCode = 'en' | 'es' | 'ru' | 'zh-Hant' | 'zh-Hans' | 'tr' | 'de' | 'th' | 'uk' | 'pl';

export interface LangItem {
  langCode: LangCode;
  name: string;
  nativeName: string;
  rtl: boolean;
}

export interface LangString {
  zeroValue?: string;
  oneValue?: string;
  twoValue?: string;
  fewValue?: string;
  manyValue?: string;
  otherValue?: string;
}

export type LangPack = Record<string, string | LangString>;

export type StakingStatus = 'active' | 'unstakeRequested';

export type AuthMethod = 'createAccount' | 'importMnemonic' | 'importHardwareWallet';

interface AuthAccount {
  accountId: string;
  addressByChain: Partial<Record<ApiChain, string>>;
  network?: ApiNetwork;
}

type SignOutLevel = 'account' | 'network' | 'all';

export enum AppState {
  Auth,
  Main,
  Explore,
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
  safetyRules,
  mnemonicPage,
  checkWords,
  importViewAccount,
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

export const enum ScamWarningType {
  SeedPhrase = 1,
  DomainLike,
}

export enum SignDataState {
  None,
  Initial,
  Password,
  Complete,
}

export enum DomainRenewalState {
  None,
  Initial,
  Password,
  ConnectHardware,
  ConfirmHardware,
  Complete,
}

export enum DomainLinkingState {
  None,
  Initial,
  Password,
  ConnectHardware,
  ConfirmHardware,
  Complete,
}

export enum SwapState {
  None,
  Initial,
  Blockchain,
  Password,
  WaitTokens,
  Complete,
  SelectTokenFrom,
  SelectTokenTo,
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
  NotEnoughForFee,
  TooSmallAmount,
}

export enum SwapType {
  OnChain,
  CrosschainFromWallet,
  CrosschainToWallet,
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
  WaitingForRemoteTab,
}

export enum StakingState {
  None,

  StakeInitial,
  StakePassword,
  StakeConnectHardware,
  StakeConfirmHardware,
  StakeComplete,

  UnstakeInitial,
  UnstakePassword,
  UnstakeConnectHardware,
  UnstakeConfirmHardware,
  UnstakeComplete,

  ClaimPassword,
  ClaimConnectHardware,
  ClaimConfirmHardware,
  ClaimComplete,
}

export enum VestingUnfreezeState {
  Password,
  ConnectHardware,
  ConfirmHardware,
}

export enum SettingsState {
  Initial,
  PushNotifications,
  Appearance,
  Assets,
  Security,
  Dapps,
  Language,
  About,
  Disclaimer,
  NativeBiometricsTurnOn,
  SelectTokenList,
  WalletVersion,
  LedgerConnectHardware,
  LedgerSelectWallets,
  HiddenNfts,
  BackupWallet,
}

export enum MintCardState {
  Initial,
  Password,
  ConnectHardware,
  ConfirmHardware,
  Done,
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
  chain: ApiChain;
  tokenAddress?: string;
  isDisabled?: boolean;
  canSwap?: boolean;
  keywords?: string[];
  cmcSlug?: string;
  totalValue: string;
  type?: ApiTokenType;
  color?: string;
  codeHash?: string;
};

export type UserSwapToken = Omit<UserToken, 'change24h' | 'chain'> & {
  chain: ApiChain | (string & {});
  isPopular: boolean;
};

export type TokenPeriod = '1D' | '7D' | '1M' | '3M' | '1Y' | 'ALL';

export type PriceHistoryPeriods = Partial<Record<ApiPriceHistoryPeriod, ApiHistoryList>>;

export type DieselStatus = 'not-available' | 'not-authorized' | 'pending-previous' | 'available' | 'stars-fee';

export type AccountType = 'mnemonic' | 'hardware' | 'view';

export interface Account {
  title?: string;
  type: AccountType;
  addressByChain: Partial<Record<ApiChain, string>>;
  domainByChain?: Partial<Record<ApiChain, string>>;
  isMultisigByChain?: Partial<Record<ApiChain, boolean>>;
  ledger?: {
    index: number;
    driver: ApiLedgerDriver;
  };
}

export type AssetPairs = Record<string, {
  isReverseProhibited?: boolean;
  isMultichain?: boolean;
}>;

export interface AccountState {
  balances?: {
    bySlug: ApiBalanceBySlug;
  };
  activities?: {
    byId: Record<string, ApiActivity>;
    /**
     * The array values are sorted by the activity type (newest to oldest).
     * Undefined means that the activities haven't been loaded, [] means that there are no activities.
     */
    idsMain?: string[];
    /** The record values follow the same rules as `idsMain` */
    idsBySlug?: Record<string, string[]>;
    newestActivitiesBySlug?: Record<string, ApiActivity>;
    isMainHistoryEndReached?: boolean;
    isHistoryEndReachedBySlug?: Record<string, boolean>;
    localActivityIds?: string[];
    /** Doesn't include the local activities */
    pendingActivityIds?: Partial<Record<ApiChain, string[]>>;
    /**
     * May be false when the actual activities are actually loaded (when the app has been loaded from the cache).
     * The initial activities should be considered loaded if `idsMain` is not undefined.
     */
    areInitialActivitiesLoaded?: Partial<Record<ApiChain, boolean>>;
  };
  nfts?: {
    byAddress?: Record<string, ApiNft>;
    orderedAddresses?: string[];
    currentCollectionAddress?: string;
    selectedAddresses?: string[];
    dnsExpiration?: Record<string, number>;
    linkedAddressByAddress?: Record<string, string>;
    collectionTabs?: string[];
    wasTelegramGiftsAutoAdded?: boolean;
  };
  blacklistedNftAddresses?: string[];
  whitelistedNftAddresses?: string[];
  selectedNftsToHide?: {
    addresses: string[];
    isCollection: boolean;
  };
  isUnhideNftModalOpen?: boolean;
  selectedNftToUnhide?: {
    address: ApiNft['address'];
    name: ApiNft['name'];
  };
  currentNftForAttributes?: ApiNft;
  dappLastOpenedDatesByUrl?: Record<string, number>;
  isBackupRequired?: boolean;
  currentTokenSlug?: string;
  currentActivityId?: string;
  currentTokenPeriod?: TokenPeriod;
  savedAddresses?: SavedAddress[];
  activeContentTab?: ContentTab;
  landscapeActionsActiveTabIndex?: ActiveTab;
  activitiesUpdateStartedAt?: number;
  balanceUpdateStartedAt?: number;

  // Staking
  staking?: {
    stakingId?: string;
    stateById?: Record<string, ApiStakingState>;
    totalProfit?: bigint;
    shouldUseNominators?: boolean;
  };

  vesting?: {
    info: ApiVestingInfo[];
    isLoading?: boolean;
    isConfirmRequested?: boolean;
    error?: string;
    unfreezeRequestedIds?: { id: number; partId: number }[];
    unfreezeState?: VestingUnfreezeState;
  };

  stakingHistory?: ApiStakingHistory;
  browserHistory?: string[];

  isDieselAuthorizationStarted?: boolean;
  isLongUnstakeRequested?: boolean;
  isCardMinting?: boolean;
  receiveModalChain?: ApiChain;
  invoiceTokenSlug?: string;

  dapps?: ApiDapp[];
  currentSiteCategoryId?: number;

  config?: ApiAccountConfig;
}

export interface AccountSettings {
  orderedSlugs?: string[];
  alwaysShownSlugs?: string[];
  alwaysHiddenSlugs?: string[];
  deletedSlugs?: string[];
  importedSlugs?: string[];
  // These NFTs should be saved in the settings for immediate use after launching the application,
  // without synchronizing the wallet history or complex state caching
  cardBackgroundNft?: ApiNft;
  accentColorNft?: ApiNft;
  accentColorIndex?: number;
  isAllowSuspiciousActions?: boolean;
}

export interface SavedAddress {
  name: string;
  address: string;
  chain: ApiChain;
}

export interface NftTransfer {
  name?: string;
  address: string;
  thumbnail: string;
  collectionName?: string;
}

export type GlobalState = {
  DEBUG_randomId?: number;

  appState: AppState;

  auth: {
    state: AuthState;
    biometricsStep?: 1 | 2;
    method?: AuthMethod;
    isLoading?: boolean;
    mnemonic?: string[];
    mnemonicCheckIndexes?: number[];
    hardwareSelectedIndices?: number[];
    error?: string;
    password?: string;
    isImportModalOpen?: boolean;
    firstNetworkAccount?: AuthAccount;
    secondNetworkAccount?: AuthAccount;
    forceAddingTonOnlyAccount?: boolean;
  };

  biometrics: {
    state: BiometricsState;
    error?: string;
    password?: string;
  };

  nativeBiometricsError?: string;

  hardware: {
    hardwareState: HardwareConnectState;
    hardwareWallets?: LedgerWalletInfo[];
    isLedgerConnected?: boolean;
    isTonAppConnected?: boolean;
    availableTransports?: LedgerTransport[];
    lastUsedTransport?: LedgerTransport;
  };

  currentTransfer: {
    state: TransferState;
    isLoading?: boolean;
    // Should be ignored when `nfts` is defined and not empty
    tokenSlug: string;
    toAddress?: string;
    toAddressName?: string;
    resolvedAddress?: string;
    error?: string;
    // Should be ignored when `nfts` is defined and not empty
    amount?: bigint;
    // Every time this field value changes, the `amount` value should be actualized using `preserveMaxTransferAmount`
    fee?: bigint;
    realFee?: bigint;
    comment?: string;
    binPayload?: string;
    /**
     * This is the legacy dapp transaction sending mechanism. The transaction originates in the `sendTransaction`
     * function of the `src/api/extensionMethods/legacy.ts` file.
     */
    promiseId?: string;
    txId?: string;
    rawPayload?: string;
    stateInit?: string;
    shouldEncrypt?: boolean;
    isToNewAddress?: boolean;
    isScam?: boolean;
    nfts?: ApiNft[];
    sentNftsCount?: number;
    isMemoRequired?: boolean;
    // Every time this field value changes, the `amount` value should be actualized using `preserveMaxTransferAmount`
    diesel?: ApiFetchEstimateDieselResult;
    withDiesel?: boolean;
    isGaslessWithStars?: boolean;
    // This field is used to display a scam warning in the UI only because `Dialogs` are not displayed in iOS
    // due to NBS specifics. Undefined means closed.
    scamWarningType?: ScamWarningType;
  };

  currentSwap: {
    isMaxAmount?: boolean;
    state: SwapState;
    swapId?: string;
    slippage: number;
    tokenInSlug?: string;
    tokenOutSlug?: string;
    amountIn?: string;
    amountOut?: string;
    amountOutMin?: string;
    priceImpact?: number;
    activityId?: string;
    error?: string;
    errorType?: SwapErrorType;
    shouldResetOnClose?: boolean;
    isLoading?: boolean;
    /**
     * When is `true`, does several things: shows the estimating indicator in the UI, blocks the form submission, and
     * instructs the UI and the actions to perform an estimation regardless.
     */
    isEstimating?: boolean;
    inputSource?: SwapInputSource;
    toAddress?: string;
    payinAddress?: string;
    payoutAddress?: string;
    payinExtraId?: string;
    limits?: {
      fromMin?: string;
      fromMax?: string;
    };
    dieselStatus?: DieselStatus;
    estimates?: ApiSwapEstimateVariant[];
    // This property is necessary to ensure that when the DEX with the best rate changes,
    // the user's selection remains unchanged
    isDexLabelChanged?: true;
    currentDexLabel?: ApiSwapDexLabel;
    bestRateDexLabel?: ApiSwapDexLabel;
    // Fees. Undefined values mean that these fields are unknown.
    networkFee?: string;
    realNetworkFee?: string;
    swapFee?: string;
    swapFeePercent?: number;
    ourFee?: string;
    ourFeePercent?: number;
    dieselFee?: string;
    shouldShowAllPairs?: boolean;
  };

  currentSignature?: {
    promiseId: string;
    dataHex: string;
    error?: string;
    isSigned?: boolean;
  };

  exploreData?: {
    categories: ApiSiteCategory[];
    sites: ApiSite[];
  };

  currentDappTransfer: {
    state: TransferState;
    isSse?: boolean;
    promiseId?: string;
    isLoading?: boolean;
    transactions?: ApiDappTransfer[];
    /** What else should happen after submitting the transactions (in addition to the transactions) */
    emulation?: Pick<ApiEmulationResult, 'activities' | 'realFee'>;
    /** Unix seconds */
    validUntil?: number;
    vestingAddress?: string;
    viewTransactionOnIdx?: number;
    dapp?: ApiDapp;
    error?: string;
  };

  currentDappSignData: {
    state: SignDataState;
    isSse?: boolean;
    promiseId?: string;
    isLoading?: boolean;
    dapp?: ApiDapp;
    payloadToSign?: SignDataPayload;
    error?: string;
  };

  currentDomainRenewal: {
    addresses?: string[];
    state: DomainRenewalState;
    isLoading?: boolean;
    error?: string;
    // There's only one commission because the transaction has no change
    realFee?: bigint;
    txId?: string;
  };

  currentDomainLinking: {
    address?: string;
    state: DomainLinkingState;
    isLoading?: boolean;
    error?: string;
    realFee?: bigint;
    walletAddress?: string;
    walletAddressName?: string;
    resolvedWalletAddress?: string;
    txId?: string;
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

  currentStaking: {
    state: StakingState;
    isLoading?: boolean;
    isUnstaking?: boolean;
    amount?: bigint;
    tokenAmount?: bigint;
    fee?: bigint;
    error?: string;
  };

  stakingDefault: ApiStakingState;

  accounts?: {
    byId: Record<string, Account>;
    isLoading?: boolean;
    error?: string;
  };

  tokenInfo: {
    bySlug: Record<string, ApiTokenWithPrice>;
  };

  swapTokenInfo: {
    bySlug: Record<string, ApiSwapAsset>;
    /** Whether the API has loaded and provided the tokens */
    isLoaded?: true;
  };

  swapVersion: ApiSwapVersion;

  swapPairs?: {
    bySlug: Record<string, AssetPairs>;
  };

  tokenPriceHistory: {
    bySlug: Record<string, PriceHistoryPeriods>;
  };

  byAccountId: Record<string, AccountState>;

  walletVersions?: {
    currentVersion: ApiTonWalletVersion;
    byId: Record<string, ApiWalletWithVersionInfo[]>;
  };

  settings: {
    state: SettingsState;
    theme: Theme;
    animationLevel: AnimationLevel;
    langCode: LangCode;
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
    isAppLockEnabled?: boolean;
    autolockValue?: AutolockValueType;
    isAutoConfirmEnabled?: boolean;
    isSensitiveDataHidden?: true;
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
  isExploreOpen?: boolean;
  isAppUpdateAvailable?: boolean;
  // Force show the "Update MyTonWallet" pop-up on all platforms
  isAppUpdateRequired?: boolean;
  confettiRequestedAt?: number;
  isPinAccepted?: boolean;
  chainForOnRampWidgetModal?: ApiChain;
  isInvoiceModalOpen?: boolean;
  isReceiveModalOpen?: boolean;
  isVestingModalOpen?: boolean;
  shouldForceAccountEdit?: boolean;
  isIncorrectTimeNotificationReceived?: boolean;
  currentBrowserOptions?: {
    url: string;
    title?: string;
    subtitle?: string;
    keepNBSOpen?: boolean;
  };

  currentMintCard?: {
    type?: ApiMtwCardType;
    state?: MintCardState;
    error?: string;
    isLoading?: boolean;
  };

  currentQrScan?: {
    currentTransfer?: GlobalState['currentTransfer'];
    currentSwap?: GlobalState['currentSwap'];
    currentDomainLinking?: GlobalState['currentDomainLinking'];
  };

  latestAppVersion?: string;
  stateVersion: number;
  restrictions: {
    isLimitedRegion: boolean;
    isSwapDisabled: boolean;
    isOnRampDisabled: boolean;
    isNftBuyingDisabled: boolean;
    isCopyStorageEnabled?: boolean;
    supportAccountsCount?: number;
    countryCode?: ApiCountryCode;
  };

  mediaViewer: {
    mediaId?: string;
    mediaType?: MediaType;
    txId?: string;
    hiddenNfts?: 'user' | 'scam';
    noGhostAnimation?: boolean;
  };

  isLoadingOverlayOpen?: boolean;

  pushNotifications: {
    isAvailable?: boolean;
    userToken?: string;
    platform?: CapacitorPlatform;
    enabledAccounts: Record<string, Partial<ApiNotificationsAccountValue>>;
  };

  isAppLockActive?: boolean;
  isManualLockActive?: boolean;
  appLockHideBiometrics?: boolean;
  // The app is open in fullscreen mode in Telegram MiniApp on mobile
  isFullscreen?: boolean;
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
  restartCheckMnemonicIndexes: { worldsCount: number };
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
  startImportViewAccount: undefined;
  closeImportViewAccount: undefined;
  openAuthImportWalletModal: undefined;
  closeAuthImportWalletModal: undefined;
  openAuthBackupWalletModal: undefined;
  openMnemonicPage: undefined;
  openCreateBackUpPage: undefined;
  openCheckWordsPage: undefined;
  closeCheckWordsPage: { isBackupCreated?: boolean } | undefined;
  initializeHardwareWalletModal: undefined;
  initializeHardwareWalletConnection: { transport: LedgerTransport };
  createHardwareAccounts: undefined;
  addHardwareAccounts: {
    wallets: ({ accountId: string; address: string; walletInfo: LedgerWalletInfo } | undefined)[];
  };
  loadMoreHardwareWallets: { lastIndex: number };
  createAccount: { password: string; isImporting: boolean; isPasswordNumeric?: boolean; version?: ApiTonWalletVersion };
  afterSelectHardwareWallets: { hardwareSelectedIndices: number[] };
  resetApiSettings: { areAllDisabled?: boolean } | undefined;
  checkAppVersion: undefined;
  importAccountByVersion: { version: ApiTonWalletVersion };
  importViewAccount: { addressByChain: ApiImportAddressByChain };

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
    stateInit?: string;
  } | undefined;
  changeTransferToken: { tokenSlug: string; withResetAmount?: boolean };
  fetchTransferFee: {
    tokenSlug: string;
    toAddress: string;
    comment?: string;
    shouldEncrypt?: boolean;
    binPayload?: string;
    stateInit?: string;
  };
  fetchNftFee: {
    toAddress: string;
    nfts: ApiNft[];
    comment?: string;
  };
  submitTransferInitial: {
    tokenSlug: string;
    amount: bigint;
    toAddress: string;
    comment?: string;
    shouldEncrypt?: boolean;
    nfts?: ApiNft[];
    withDiesel?: boolean;
    isBase64Data?: boolean;
    binPayload?: string;
    isGaslessWithStars?: boolean;
    stateInit?: string;
  };
  submitTransferConfirm: undefined;
  submitTransfer: { password?: string } | undefined;
  clearTransferError: undefined;
  cancelTransfer: { shouldReset?: boolean } | undefined;
  showTransferScamWarning: { type: ScamWarningType };
  dismissTransferScamWarning: undefined;
  showDialog: DialogType;
  dismissDialog: undefined;
  showError: { error?: ApiAnyDisplayError | string };
  showNotification: { message: string; icon?: string };
  dismissNotification: undefined;
  initLedgerPage: undefined;
  afterSignIn: undefined;
  signOut: { level: SignOutLevel };
  cancelCaching: undefined;
  afterSignOut: { shouldReset?: boolean } | undefined;
  addAccount: { method: AuthMethod; password: string; isAuthFlow?: boolean };
  addAccount2: { method: AuthMethod; password: string };
  switchAccount: { accountId: string; newNetwork?: ApiNetwork };
  renameAccount: { accountId: string; title: string };
  clearAccountError: undefined;
  clearAccountLoading: undefined;
  setIsAccountLoading: { isLoading: true | undefined };
  verifyHardwareAddress: undefined;
  authorizeDiesel: undefined;
  fetchTransferDieselState: { tokenSlug: string };
  setIsAuthLoading: { isLoading: true | undefined };

  fetchPastActivities: { slug?: string; shouldLoadWithBudget?: boolean };
  showActivityInfo: { id: string };
  showAnyAccountTx: { txId: string; accountId: string; network: ApiNetwork };
  showAnyAccountTokenActivity: { slug: string; accountId: string; network: ApiNetwork };
  showTokenActivity: { slug: string };
  closeActivityInfo: { id: string };
  fetchActivityDetails: { id: string };
  fetchNftsFromCollection: { collectionAddress: string };
  openNftCollection: { address: string };
  closeNftCollection: undefined;
  selectNfts: { addresses: string[] };
  selectAllNfts: { collectionAddress?: string };
  clearNftSelection: { address: string };
  clearNftsSelection: undefined;
  addCollectionTab: { collectionAddress: string; isAuto?: boolean };
  removeCollectionTab: { collectionAddress: string };
  burnNfts: { nfts: ApiNft[] };
  addNftsToBlacklist: { addresses: ApiNft['address'][] };
  addNftsToWhitelist: { addresses: ApiNft['address'][] };
  removeNftSpecialStatus: { address: ApiNft['address'] };
  openUnhideNftModal: {
    address: ApiNft['address'];
    name: ApiNft['name'];
  };
  closeUnhideNftModal: undefined;
  openHideNftModal: {
    addresses: ApiNft['address'][];
    isCollection: boolean;
  };
  closeHideNftModal: undefined;
  openNftAttributesModal: { nft: ApiNft };
  closeNftAttributesModal: undefined;

  openExplore: undefined;
  closeExplore: undefined;

  closeAnyModal: undefined;
  submitSignature: { password: string };
  clearSignatureError: undefined;
  cancelSignature: undefined;

  addSavedAddress: { address: string; name: string; chain: ApiChain };
  removeFromSavedAddress: { address: string; chain: ApiChain };
  checkTransferAddress: { address?: string };

  setCurrentTokenPeriod: { period: TokenPeriod };
  openAddAccountModal: { forceAddingTonOnlyAccount: boolean } | undefined;
  closeAddAccountModal: undefined;

  setLandscapeActionsActiveTabIndex: { index: ActiveTab };
  setActiveContentTab: { tab: ContentTab };

  // BottomBar actions
  switchToWallet: undefined;
  switchToExplore: undefined;
  switchToSettings: undefined;

  requestConfetti: undefined;
  setIsPinAccepted: undefined;
  clearIsPinAccepted: undefined;

  requestOpenQrScanner: undefined;
  closeQrScanner: undefined;
  handleQrCode: { data: string };

  // Staking
  startStaking: { tokenSlug: string } | undefined;
  startUnstaking: { stakingId: string } | undefined;
  setStakingScreen: { state: StakingState };
  submitStakingInitial: { amount?: bigint; isUnstaking?: boolean } | undefined;
  submitStaking: { password?: string; isUnstaking?: boolean } | undefined;
  clearStakingError: undefined;
  cancelStaking: undefined;
  fetchStakingHistory: undefined;
  fetchStakingFee: { amount: bigint };
  openStakingInfo: undefined;
  openAnyAccountStakingInfo: { accountId: string; network: ApiNetwork; stakingId: string };
  closeStakingInfo: undefined;
  changeCurrentStaking: { stakingId: string; shouldReopenModal?: boolean };
  startStakingClaim: { stakingId: string } | undefined;
  submitStakingClaim: { password?: string } | undefined;
  cancelStakingClaim: undefined;
  openStakingInfoOrStart: undefined;

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
  updateOrderedSlugs: { orderedSlugs: string[] };
  rebuildOrderedSlugs: undefined;
  toggleTokenVisibility: { slug: string; shouldShow: boolean };
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
  setAppLockValue: { value?: AutolockValueType; isEnabled: boolean };
  setIsManualLockActive: { isActive?: boolean; shouldHideBiometrics?: boolean };
  setIsAutoConfirmEnabled: { isEnabled: boolean };
  setIsAllowSuspiciousActions: { isEnabled: boolean };
  setInMemoryPassword: { password?: string; isFinalCall?: boolean; force?: boolean };
  openSettingsHardwareWallet: undefined;
  apiUpdateWalletVersions: ApiUpdateWalletVersions;

  // Account Settings
  setCardBackgroundNft: { nft: ApiNft };
  clearCardBackgroundNft: undefined;
  checkCardNftOwnership: undefined;
  installAccentColorFromNft: { nft: ApiNft };
  clearAccentColorFromNft: undefined;

  // TON Connect common
  apiUpdateDappLoading: ApiUpdateDappLoading;
  apiUpdateDappCloseLoading: ApiUpdateDappCloseLoading;

  // TON Connect connection
  submitDappConnectRequestConfirm: { accountId: string; password?: string };
  clearDappConnectRequestError: undefined;
  cancelDappConnectRequestConfirm: undefined;
  setDappConnectRequestState: { state: DappConnectState };
  apiUpdateDappConnect: ApiUpdateDappConnect;

  // TON Connect transfer
  setDappTransferScreen: { state: TransferState };
  showDappTransferTransaction: { transactionIdx: number };
  submitDappTransferConfirm: undefined;
  submitDappTransfer: { password?: string } | undefined;
  clearDappTransferError: undefined;
  cancelDappTransfer: undefined;
  closeDappTransfer: undefined;
  apiUpdateDappSendTransaction: ApiUpdateDappSendTransactions;

  // TON Connect SignData
  setDappSignDataScreen: { state: SignDataState };
  submitDappSignDataConfirm: undefined;
  submitDappSignData: { password?: string } | undefined;
  clearDappSignDataError: undefined;
  cancelDappSignData: undefined;
  closeDappSignData: undefined;
  apiUpdateDappSignData: ApiUpdateDappSignData;

  getDapps: undefined;
  deleteAllDapps: undefined;
  deleteDapp: { url: string; uniqueId: string };
  loadExploreSites: { isLandscape: boolean };
  updateDappLastOpenedAt: { url: string };

  addSiteToBrowserHistory: { url: string };
  removeSiteFromBrowserHistory: { url: string };
  openBrowser: { url: string; title?: string; subtitle?: string; keepNBSOpen?: boolean };
  closeBrowser: undefined;
  openSiteCategory: { id: number };
  closeSiteCategory: undefined;
  switchAccountAndOpenUrl: {
    accountId?: string;
    network?: ApiNetwork;
    url: string;
    isExternal?: boolean;
    title?: string;
    subtitle?: string;
  };

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
  setDefaultSwapParams: { tokenInSlug?: string; tokenOutSlug?: string; withResetAmount?: boolean } | undefined;
  switchSwapTokens: undefined;
  setSwapTokenIn: { tokenSlug: string };
  setSwapTokenOut: { tokenSlug: string };
  setSwapAmountIn: { amount?: string; isMaxAmount?: boolean };
  setSwapAmountOut: { amount?: string };
  setSlippage: { slippage: number };
  estimateSwap: undefined;
  setSwapScreen: { state: SwapState };
  clearSwapError: undefined;
  submitSwapCex: { password: string };
  setSwapCexAddress: { toAddress: string };
  addSwapToken: { token: UserSwapToken };
  toggleSwapSettingsModal: { isOpen: boolean };
  updatePendingSwaps: undefined;
  setSwapDex: { dexLabel: ApiSwapDexLabel };

  openOnRampWidgetModal: { chain: ApiChain };
  closeOnRampWidgetModal: undefined;

  // MediaViewer
  openMediaViewer: {
    mediaId: string;
    mediaType: MediaType;
    txId?: string;
    hiddenNfts?: 'user' | 'scam';
    noGhostAnimation?: boolean;
  };
  closeMediaViewer: undefined;

  openReceiveModal: { chain: ApiChain } | undefined;
  closeReceiveModal: undefined;
  setReceiveActiveTab: { chain: ApiChain };
  openInvoiceModal: { tokenSlug: string } | undefined;
  changeInvoiceToken: { tokenSlug: string };
  closeInvoiceModal: undefined;

  loadPriceHistory: { slug: string; period: ApiPriceHistoryPeriod; currency?: ApiBaseCurrency };

  showIncorrectTimeError: undefined;

  openLoadingOverlay: undefined;
  closeLoadingOverlay: undefined;

  loadMycoin: undefined;
  openVestingModal: undefined;
  closeVestingModal: undefined;
  startClaimingVesting: undefined;
  submitClaimingVesting: { password?: string } | undefined;
  clearVestingError: undefined;
  cancelClaimingVesting: undefined;

  openMintCardModal: undefined;
  closeMintCardModal: undefined;
  startCardMinting: { type: ApiMtwCardType };
  submitMintCard: { password?: string } | undefined;
  clearMintCardError: undefined;

  submitAppLockActivityEvent: undefined;

  toggleNotifications: { isEnabled: boolean };
  renameNotificationAccount: { accountId: string };
  toggleNotificationAccount: { accountId: string };
  createNotificationAccount: { accountId: string; withAbort?: boolean };
  tryAddNotificationAccount: { accountId: string };
  deleteNotificationAccount: { accountId: string; withAbort?: boolean };
  deleteAllNotificationAccounts: undefined | { accountIds: string[] };
  registerNotifications: { userToken: string; platform: CapacitorPlatform };

  openFullscreen: undefined;
  closeFullscreen: undefined;
  setAppLayout: { layout: AppLayout };

  setIsSensitiveDataHidden: { isHidden: boolean };

  openDomainRenewalModal: { accountId?: string; network?: ApiNetwork; addresses: string[] };
  startDomainsRenewal: undefined;
  checkDomainsRenewalDraft: { nfts: ApiNft[] };
  submitDomainsRenewal: { password?: string } | undefined;
  clearDomainsRenewalError: undefined;
  cancelDomainsRenewal: undefined;

  openDomainLinkingModal: { address: string };
  startDomainLinking: undefined;
  checkDomainLinkingDraft: { nft: ApiNft };
  submitDomainLinking: { password?: string } | undefined;
  clearDomainLinkingError: undefined;
  cancelDomainLinking: undefined;

  checkLinkingAddress: { address?: string };
  setDomainLinkingWalletAddress: { address?: string };
  setIsAppLockActive: { isActive: boolean };
}

export enum LoadMoreDirection {
  Forwards,
  Backwards,
}

export type AutolockValueType = (typeof AUTOLOCK_OPTIONS_LIST[number])['value'];
