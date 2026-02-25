import type { SignDataPayload } from '@tonconnect/protocol';
import type { TeactNode } from '../lib/teact/teact';

import type { ApiTonWalletVersion } from '../api/chains/ton/types';
import type { TonConnectProof } from '../api/dappProtocols/adapters';
import type { StoredDappConnection } from '../api/dappProtocols/storage';
import type {
  ApiAccountConfig,
  ApiActivity,
  ApiAnyDisplayError,
  ApiBackendConfig,
  ApiBalanceBySlug,
  ApiBaseCurrency,
  ApiChain,
  ApiCountryCode,
  ApiCurrencyRates,
  ApiDappPermissions,
  ApiDappTransfer,
  ApiEmulationResult,
  ApiFetchEstimateDieselResult,
  ApiHistoryList,
  ApiImportAddressByChain,
  ApiLedgerDriver,
  ApiLedgerWalletInfo,
  ApiMtwCardType,
  ApiNetwork,
  ApiNft,
  ApiNftCollection,
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
import type { LedgerTransport } from '../util/ledger/types';

export type IAnchorPosition = {
  x: number;
  y: number;
};

export type AnimationLevel = 0 | 1 | 2;
export type Theme = 'light' | 'dark' | 'system';
export type AppTheme = 'dark' | 'light';
export type AppLayout = 'portrait' | 'landscape';
export type DialogAction = 'openBluetoothSettings' | 'signOutAll';

export type DeveloperSettingsUndefinedOverride = '__undefined';
export type DeveloperSettingsOverrideValue<Value> = Exclude<Value, undefined> | DeveloperSettingsUndefinedOverride;

export interface DeveloperSettingsOverrides {
  seasonalTheme?: DeveloperSettingsOverrideValue<ApiBackendConfig['seasonalTheme']>;
}

export type DeveloperSettingsOverrideKey = keyof DeveloperSettingsOverrides;
export type DeveloperSettingsOverridePayload = {
  [Key in DeveloperSettingsOverrideKey]: {
    key: Key;
    value?: DeveloperSettingsOverrides[Key];
  };
}[DeveloperSettingsOverrideKey];

export type ToastType = {
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
  byChain: Partial<Record<ApiChain, AccountChain>>;
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
  about,
  safetyRules,
  mnemonicPage,
  checkWords,
  importViewAccount,
  congratulations,
  importCongratulations,
  ready,
}

export enum AccountSelectorState {
  Cards,
  List,
  Reorder,
  AddAccountInitial,
  AddAccountPassword,
  AddAccountConnectHardware,
  AddAccountSelectHardware,
  AddAccountViewMode,
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
  Initial,
  Confirm,
  Password,
  ConnectHardware,
  ConfirmHardware,
  Complete,
}

export const enum TransactionInfoState {
  None,
  Loading,
  ActivityList,
  ActivityDetail,
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
  /** The swap is on-chain, i.e. performed via a DEX */
  OnChain,
  /** The swap is crosschain (Changelly CEX) and happens within a single account */
  CrosschainInsideWallet,
  /** The swap is crosschain (Changelly CEX), the "in" token is sent from the app, and the "out" token is sent outside */
  CrosschainFromWallet,
  /**
   * The swap is crosschain (Changelly CEX), the "in" token is sent manually by the user from another source, and the
   * "out" token is sent to the user account.
   */
  CrosschainToWallet,
}

export enum DappConnectState {
  Info,
  SelectAccount,
  Password,
  ConnectHardware,
  ConfirmHardware,
}

export enum HardwareConnectState {
  Connect,
  Connecting,
  Failed,
  Connected,
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
  /** A small dim label to show in the UI right after the token name */
  label?: string;
  /** True if this is a staking token (created from ApiStakingState) */
  isStaking?: boolean;
  stakingId?: string;
};

export type UserSwapToken = Omit<UserToken, 'change24h' | 'chain'> & {
  chain: ApiChain | (string & {});
  isPopular: boolean;
};

export type TokenPeriod = '1D' | '7D' | '1M' | '3M' | '1Y' | 'ALL';

export type TokenChartMode = 'price' | 'netWorth';

export type PriceHistoryPeriods = Partial<Record<ApiPriceHistoryPeriod, ApiHistoryList>>;

export type DieselStatus = 'not-available' | 'not-authorized' | 'pending-previous' | 'available' | 'stars-fee';

export type AccountType = 'mnemonic' | 'hardware' | 'view';

export interface AccountChain {
  address: string;
  domain?: string;
  isMultisig?: true;
}

export interface Account {
  title?: string;
  type: AccountType;
  byChain: Partial<Record<ApiChain, AccountChain>>;
  isTemporary?: true;
}

export type AssetPairs = Record<string, {
  isReverseProhibited?: boolean;
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
    currentCollection?: ApiNftCollection;
    selectedNfts?: ApiNft[];
    dnsExpiration?: Record<string, number>;
    linkedAddressByAddress?: Record<string, string>;
    collectionTabs?: ApiNftCollection[];
    wasTelegramGiftsAutoAdded?: boolean;
    isLoadedByAddress?: Record<string, true>;
    isFullLoadingByChain?: Partial<Record<ApiChain, boolean>>;
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
  shouldShowOwnerInNftAttributes?: true;
  dappLastOpenedDatesByUrl?: Record<string, number>;
  isBackupRequired?: boolean;
  currentTokenSlug?: string;
  currentActivityId?: string;
  currentTokenPeriod?: TokenPeriod;
  tokenNetWorthHistory?: Record<string, PriceHistoryPeriods>;
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

  dapps?: StoredDappConnection[];
  currentSiteCategoryId?: number;

  config?: ApiAccountConfig;
  isAppReady?: boolean;
}

export interface AccountSettings {
  pinnedSlugs?: string[];
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

export interface AddressBookItemData {
  name: string;
  address: string;
  chain: ApiChain | undefined;
  domain?: string;
  isHardware?: boolean;
  isSavedAddress?: boolean;
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
    accounts?: AuthAccount[];
    forceAddingTonOnlyAccount?: boolean;
    initialAddAccountState?: AccountSelectorState; // Initial rendering state for the `AddAccountModal` component
    shouldHideAddAccountBackButton?: boolean;
  };

  biometrics: {
    state: BiometricsState;
    error?: string;
    password?: string;
  };

  nativeBiometricsError?: string;

  hardware: {
    hardwareState: HardwareConnectState;
    chain: ApiChain;
    /**
     * If true, `hardwareWallets` will be populated before the `hardwareState` switches to `Connected`.
     * This is slow, so use it only when necessary.
     */
    shouldLoadWallets?: true;
    /** All the wallets belong to `chain` */
    hardwareWallets?: ApiLedgerWalletInfo[];
    isLedgerConnected?: boolean;
    isChainAppConnected?: boolean;
    availableTransports?: LedgerTransport[];
    lastUsedTransport?: LedgerTransport;
    /** Loading flag for paginated wallet fetch (Show More) */
    isLoading?: boolean;
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
    isGasless?: boolean;
    isGaslessWithStars?: boolean;
    scamWarningType?: ScamWarningType;
    isTransferReadonly?: boolean;
    isOfframp?: boolean;
    isNftBurn?: boolean;
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
    /** The address to send the "out" tokens to. Used only when the swap type is `CrosschainFromWallet`. */
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
    maxAmountFromBackend?: string;
    // Fees. Undefined values mean that these fields are unknown.
    networkFee?: string;
    realNetworkFee?: string;
    swapFee?: string;
    swapFeePercent?: number;
    ourFee?: string;
    ourFeePercent?: number;
    dieselFee?: string;
  };

  currentSignature?: {
    promiseId: string;
    dataHex: string;
    error?: string;
    isSigned?: boolean;
  };

  exploreData?: {
    featuredTitle?: string;
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
    dapp?: StoredDappConnection;
    operationChain?: ApiChain;
    error?: string;
    shouldHideTransfers?: boolean;
    // Deal with solana b58/b64 issues based on requested method
    isLegacyOutput?: boolean;
  };

  currentDappSignData: {
    state: SignDataState;
    isSse?: boolean;
    promiseId?: string;
    isLoading?: boolean;
    dapp?: StoredDappConnection;
    operationChain?: ApiChain;
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
    dapp: StoredDappConnection;
    permissions?: ApiDappPermissions;
    proof?: TonConnectProof;
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

  currencyRates: ApiCurrencyRates;

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
    isSeasonalThemingDisabled?: boolean;
    developerSettingsOverrides?: DeveloperSettingsOverrides;
    langCode: LangCode;
    byAccountId: Record<string, AccountSettings>;
    areTinyTransfersHidden?: boolean;
    canPlaySounds?: boolean;
    isInvestorViewEnabled?: boolean;
    isTonProxyEnabled?: boolean;
    isDeeplinkHookEnabled?: boolean;
    isPasswordNumeric?: boolean; // Backwards compatibility for non-numeric passwords from older versions
    isTestnet?: boolean;
    isSecurityWarningHidden?: boolean;
    areTokensWithNoCostHidden: boolean;
    importToken?: {
      isLoading?: boolean;
      token?: UserToken | UserSwapToken;
      error?: string;
    };
    authConfig?: AuthConfig;
    baseCurrency: ApiBaseCurrency;
    isAppLockEnabled?: boolean;
    autolockValue?: AutolockValueType;
    isAutoConfirmEnabled?: boolean;
    isSensitiveDataHidden?: true;
    orderedAccountIds?: string[];
    selectedExplorerIds?: Partial<Record<ApiChain, string>>;
  };

  dialogs: DialogType[];
  toasts: ToastType[];
  currentAccountId?: string;
  currentTemporaryViewAccountId?: string;
  isAccountSelectorOpen?: boolean;
  accountSelectorActiveTab?: number;
  accountSelectorViewMode?: 'cards' | 'list';
  isBackupWalletModalOpen?: boolean;
  isHardwareModalOpen?: boolean;
  isStakingInfoModalOpen?: boolean;
  isQrScannerOpen?: boolean;
  isCustomizeWalletModalOpen?: boolean;
  customizeWalletReturnTo?: 'accountSelector' | 'settings';
  areSettingsOpen?: boolean;
  isExploreOpen?: boolean;
  isAppUpdateAvailable?: boolean;
  // Force show the "Update MyTonWallet" pop-up on all platforms
  isAppUpdateRequired?: boolean;
  seasonalTheme?: ApiBackendConfig['seasonalTheme'];
  isPromotionModalOpen?: boolean;
  confettiRequestedAt?: number;
  isPinAccepted?: boolean;
  chainForOnRampWidgetModal?: ApiChain;
  chainForOffRampWidgetModal?: ApiChain;
  isInvoiceModalOpen?: boolean;
  isReceiveModalOpen?: boolean;
  isVestingModalOpen?: boolean;
  isIncorrectTimeNotificationReceived?: boolean;
  currentBrowserOptions?: {
    url: string;
    title?: string;
    subtitle?: string;
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
    isOffRampDisabled: boolean;
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

  currentTransactionInfo: {
    state: TransactionInfoState;
    txId?: string;
    chain?: ApiChain;
    activities?: ApiActivity[];
    selectedActivityIndex?: number;
    error?: string;
  };

  isLoadingOverlayOpen?: boolean;

  pushNotifications: {
    isAvailable?: boolean;
    userToken?: string;
    platform?: CapacitorPlatform;
    enabledAccounts: string[]; // Values - account ids
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
  afterCongratulations: { isImporting?: boolean };
  skipCheckMnemonic: undefined;
  restartCheckMnemonicIndexes: {
    wordsCount: number;
    preserveIndexes?: number[];
  };
  afterCreatePassword: { password: string; isPasswordNumeric?: boolean };
  startCreatingBiometrics: undefined;
  afterCreateBiometrics: undefined;
  skipCreateBiometrics: { isImporting: boolean };
  cancelCreateBiometrics: undefined;
  afterCreateNativeBiometrics: undefined;
  skipCreateNativeBiometrics: undefined;
  createPin: { pin: string; isImporting: boolean };
  confirmPin: { isImporting: boolean };
  cancelConfirmPin: { isImporting: boolean };
  cancelCheckPassword: undefined;
  startImportingWallet: undefined;
  afterImportMnemonic: { mnemonic: string[] };
  startImportingHardwareWallet: { driver: ApiLedgerDriver };
  confirmDisclaimer: undefined;
  afterConfirmDisclaimer: undefined;
  cleanAuthError: undefined;
  openAbout: undefined;
  closeAbout: undefined;
  openDisclaimer: undefined;
  closeDisclaimer: undefined;
  startImportViewAccount: undefined;
  closeImportViewAccount: undefined;
  openAuthImportWalletModal: undefined;
  closeAuthImportWalletModal: undefined;
  openAuthBackupWalletModal: undefined;
  openMnemonicPage: undefined;
  openCheckWordsPage: undefined;
  closeCheckWordsPage: { isBackupCreated?: boolean } | undefined;
  initializeHardwareWalletModal: undefined;
  initializeHardwareWalletConnection: { transport: LedgerTransport };
  createHardwareAccounts: undefined;
  addHardwareAccounts: { accounts: { accountId: string; byChain: Account['byChain'] }[] };
  loadMoreHardwareWallets: undefined;
  createAccount: { password: string; isImporting: boolean; isPasswordNumeric?: boolean };
  afterSelectHardwareWallets: { hardwareSelectedIndices: number[] };
  resetApiSettings: { areAllDisabled?: boolean } | undefined;
  checkAppVersion: undefined;
  importAccountByVersion: { version: ApiTonWalletVersion; isTestnetSubwalletId?: boolean };
  importViewAccount: { addressByChain: ApiImportAddressByChain };
  openTemporaryViewAccount: { addressByChain: Partial<Record<ApiChain, string>> };
  saveTemporaryAccount: undefined;

  selectToken: { slug?: string } | undefined;
  openBackupWalletModal: undefined;
  closeBackupWalletModal: undefined;
  setIsBackupRequired: { isMnemonicChecked: boolean };
  openHardwareWalletModal: { chain: ApiChain };
  closeHardwareWalletModal: undefined;
  openCustomizeWalletModal: { returnTo?: 'accountSelector' | 'settings' };
  closeCustomizeWalletModal: undefined;
  resetHardwareWalletConnect: { chain: ApiChain; shouldLoadWallets?: boolean };
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
    isTransferReadonly?: boolean;
    isOfframp?: boolean;
  } | undefined;
  changeTransferToken: { tokenSlug: string; withResetAmount?: boolean };
  fetchTransferFee: {
    tokenSlug: string;
    toAddress: string;
    amount?: bigint;
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
    isGasless?: boolean;
    isBase64Data?: boolean;
    binPayload?: string;
    isGaslessWithStars?: boolean;
    stateInit?: string;
    isNftBurn?: boolean;
  };
  submitTransferConfirm: undefined;
  submitTransfer: { password?: string } | undefined;
  clearTransferError: undefined;
  cancelTransfer: { shouldReset?: boolean } | undefined;
  showTransferScamWarning: { type: ScamWarningType };
  dismissTransferScamWarning: undefined;
  showDialog: DialogType;
  dismissDialog: undefined;
  showError: { error?: ApiAnyDisplayError | TeactNode | string };
  showToast: { message: string; icon?: string };
  dismissToast: undefined;
  initLedgerPage: undefined;
  afterSignIn: undefined;
  signOut: { level: SignOutLevel; accountId?: string };
  cancelCaching: undefined;
  afterSignOut: { shouldReset?: boolean } | undefined;
  addAccount: { method: AuthMethod; password: string; isAuthFlow?: boolean };
  addAccount2: { method: AuthMethod; password: string };
  switchAccount: { accountId: string; newNetwork?: ApiNetwork };
  renameAccount: { accountId: string; title: string };
  clearAccountError: undefined;
  clearAccountLoading: undefined;
  setIsAccountLoading: { isLoading: true | undefined };
  verifyHardwareAddress: { chain: ApiChain };
  authorizeDiesel: undefined;
  fetchTransferDieselState: { tokenSlug: string };
  setIsAuthLoading: { isLoading: true | undefined };

  fetchPastActivities: { slug?: string; shouldLoadWithBudget?: boolean };
  showActivityInfo: { id: string };
  showAnyAccountTx: { txId: string; accountId: string; network: ApiNetwork; chain: ApiChain };
  showTokenActivity: { slug: string };
  closeActivityInfo: { id: string };
  fetchActivityDetails: { id: string };

  // External transaction info (deeplink)
  openTransactionInfo:
    | { txId: string; chain: ApiChain; activities?: ApiActivity[] }
    | { txHash: string; chain: ApiChain; activities?: ApiActivity[] };
  closeTransactionInfo: undefined;
  selectTransactionInfoActivity: { index: number };
  fetchNftsFromCollection: { collection: ApiNftCollection };
  clearNftCollectionLoading: { collection: ApiNftCollection };
  openNftCollection: { chain: ApiChain; address: string };
  closeNftCollection: undefined;
  selectNfts: { nfts: ApiNft[] };
  selectAllNfts: { collectionAddress?: string };
  clearNftSelection: { address: string };
  clearNftsSelection: undefined;
  addCollectionTab: { collection: ApiNftCollection; isAuto?: boolean };
  removeCollectionTab: { collection: ApiNftCollection };
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
  openNftAttributesModal: { nft: ApiNft; withOwner?: true };
  closeNftAttributesModal: undefined;

  openExplore: undefined;
  closeExplore: undefined;

  closeAnyModal: undefined;
  submitSignature: { password: string };
  clearSignatureError: undefined;
  cancelSignature: undefined;

  addSavedAddress: { address: string; name: string; chain: ApiChain };
  removeFromSavedAddress: { address: string; chain: ApiChain };
  checkTransferAddress: { address?: string; chain?: ApiChain };

  openAccountSelector: undefined;
  closeAccountSelector: undefined;
  setAccountSelectorTab: { tab: number };
  setAccountSelectorViewMode: { mode: 'cards' | 'list' };
  setCurrentTokenPeriod: { period: TokenPeriod };
  openAddAccountModal: {
    forceAddingTonOnlyAccount?: boolean;
    initialState?: AccountSelectorState;
    shouldHideBackButton?: boolean;
  } | undefined;
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
  toggleSeasonalTheming: { isEnabled?: boolean };
  setDeveloperSettingsOverride: DeveloperSettingsOverridePayload;
  toggleTinyTransfersHidden: { isEnabled?: boolean } | undefined;
  toggleInvestorView: { isEnabled?: boolean } | undefined;
  toggleCanPlaySounds: { isEnabled?: boolean } | undefined;
  toggleTonProxy: { isEnabled: boolean };
  toggleDeeplinkHook: { isEnabled: boolean };
  startChangingNetwork: { network: ApiNetwork };
  changeNetwork: { network: ApiNetwork };
  changeLanguage: { langCode: LangCode };
  setSelectedExplorerId: { chain: ApiChain; explorerId: string };
  closeSecurityWarning: undefined;
  toggleTokensWithNoCost: { isEnabled: boolean };
  pinToken: { slug: string };
  unpinToken: { slug: string };
  toggleTokenVisibility: { slug: string; shouldShow: boolean };
  addToken: { token: UserToken };
  deleteToken: { slug: string };
  importToken: { chain: ApiChain; address: string };
  updateOrderedAccountIds: { orderedAccountIds: string[] };
  rebuildOrderedAccountIds: undefined;
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
  setInMemoryPassword: { password?: string; force?: boolean };
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
  loadExploreSites: { isLandscape: boolean; langCode: LangCode | undefined };
  updateDappLastOpenedAt: { url: string };

  addSiteToBrowserHistory: { url: string };
  removeSiteFromBrowserHistory: { url: string };
  openBrowser: { url: string; title?: string; subtitle?: string };
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

  openOffRampWidgetModal: undefined;
  closeOffRampWidgetModal: undefined;

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
  loadTokenNetWorthHistory: {
    slug: string;
    period: ApiPriceHistoryPeriod;
    currency?: ApiBaseCurrency;
  };

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
  openPromotionModal: undefined;
  closePromotionModal: undefined;
  startCardMinting: { type: ApiMtwCardType };
  submitMintCard: { password?: string } | undefined;
  clearMintCardError: undefined;

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
