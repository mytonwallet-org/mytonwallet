import type { SignDataPayload } from '@tonconnect/protocol';

import type { GlobalState } from '../../global/types';
import type { ApiTonWalletVersion } from '../chains/ton/types';
import type { TonConnectProof } from '../dappProtocols/adapters';
import type { StoredDappConnection } from '../dappProtocols/storage';
import type { ApiActivity } from './activities';
import type {
  ApiAccountConfig,
  ApiBackendConfig,
  ApiSwapAsset,
  ApiSwapVersion,
  ApiVestingInfo,
} from './backend';
import type { ApiEmulationResult } from './emulation';
import type { ApiAnyDisplayError } from './errors';
import type {
  ApiBalanceBySlug,
  ApiChain,
  ApiCountryCode,
  ApiCurrencyRates,
  ApiDappConnectionType,
  ApiDappTransfer,
  ApiNft,
  ApiStakingState,
  ApiTokenWithPrice,
  ApiWalletWithVersionInfo,
} from './misc';
import type { ApiCheckTransactionDraftResult } from './transfer';

export type ApiUpdateBalances = {
  type: 'updateBalances';
  accountId: string;
  chain: ApiChain;
  balances: ApiBalanceBySlug;
};

export type ApiUpdateInitialActivities = {
  type: 'initialActivities';
  accountId: string;
  chain: ApiChain;
  mainActivities: ApiActivity[];
  /** The dictionary may contain not all tokens of the given chain */
  bySlug: Record<string, ApiActivity[]>;
};

export type ApiUpdateNewActivities = {
  type: 'newActivities';
  accountId: string;
  chain?: ApiChain;
  activities: ApiActivity[];
  /**
   * The UI must replace all the pending activities in the given chain with the given activities. This is except to
   * local activities, but if a pending activity matchers a local activity, it replaces that local activity.
   *
   * Omitted if the update does not change the list of pending actions (the UI should keep the old list).
   *
   * Doesn't contain activities with the hashes of the current or past confirmed activities.
   *
   * There is no separate update for pending activities, because confirmed activities replace pending activities, so the
   * UI should handle both changes in one update.
   */
  pendingActivities?: readonly ApiActivity[];
};

export type ApiUpdateNewLocalActivities = {
  type: 'newLocalActivities';
  accountId: string;
  activities: ApiActivity[];
};

export type ApiUpdateTokens = {
  type: 'updateTokens';
  tokens: Record<string, ApiTokenWithPrice>;
};

export type ApiUpdateSwapTokens = {
  type: 'updateSwapTokens';
  tokens: Record<string, ApiSwapAsset>;
};

export type ApiUpdateCurrencyRates = {
  type: 'updateCurrencyRates';
  rates: ApiCurrencyRates;
};

export type ApiUpdateCreateTransaction = {
  type: 'createTransaction';
  promiseId: string;
  toAddress: string;
  amount: bigint;
  comment?: string;
  rawPayload?: string;
  stateInit?: string;
  checkResult: ApiCheckTransactionDraftResult;
};

export type ApiUpdateCompleteTransaction = {
  type: 'completeTransaction';
  activityId: string;
};

export type ApiUpdateCreateSignature = {
  type: 'createSignature';
  promiseId: string;
  dataHex: string;
};

export type ApiUpdateShowError = {
  type: 'showError';
  error?: ApiAnyDisplayError | string;
};

export type ApiUpdateStaking = {
  type: 'updateStaking';
  accountId: string;
  states: ApiStakingState[];
  totalProfit: bigint;
  shouldUseNominators?: boolean;
};

export type ApiUpdateDappSignData = {
  type: 'dappSignData';
  promiseId: string;
  accountId: string;
  dapp: StoredDappConnection;
  operationChain: ApiChain;
  payloadToSign: SignDataPayload;
};

export type ApiUpdateDappSendTransactions = {
  type: 'dappSendTransactions';
  promiseId: string;
  accountId: string;
  dapp: StoredDappConnection;
  // Dapp may have many chains, so need to specify current operation chain
  operationChain: ApiChain;
  transactions: ApiDappTransfer[];
  emulation?: Pick<ApiEmulationResult, 'activities' | 'realFee'>;
  /** Unix seconds */
  validUntil?: number;
  vestingAddress?: string;
  // No useful transfers in solana
  shouldHideTransfers?: boolean;
  // Deal with solana b58/b64 issues based on requested method
  isLegacyOutput?: boolean;
};

export type ApiUpdateTonConnectOnline = {
  type: 'tonConnectOnline';
};

export type ApiUpdateDappConnect = {
  type: 'dappConnect';
  identifier?: string;
  promiseId: string;
  accountId: string;
  dapp: StoredDappConnection;
  permissions: {
    address: boolean;
    proof: boolean;
  };
  proof?: TonConnectProof;
};

export type ApiUpdateDappConnectComplete = {
  type: 'dappConnectComplete';
};

export type ApiUpdateDappDisconnect = {
  type: 'dappDisconnect';
  accountId: string;
  url: string;
};

export type ApiUpdateDappLoading = {
  type: 'dappLoading';
  connectionType: ApiDappConnectionType;
  isSse?: boolean;
  accountId?: string;
};

export type ApiUpdateDappCloseLoading = {
  type: 'dappCloseLoading';
  connectionType: ApiDappConnectionType;
};

export type ApiUpdateDapps = {
  type: 'updateDapps';
};

export type ApiUpdateDappTransferComplete = {
  type: 'dappTransferComplete';
  accountId: string;
};

export type ApiUpdateDappSignDataComplete = {
  type: 'dappSignDataComplete';
  accountId: string;
};

export type ApiUpdatePrepareTransaction = {
  type: 'prepareTransaction';
  toAddress: string;
  amount?: bigint;
  comment?: string;
  binPayload?: string;
  stateInit?: string;
};

export type ApiUpdateProcessDeeplink = {
  type: 'processDeeplink';
  url: string;
};

export type ApiUpdateNfts = {
  type: 'updateNfts';
  accountId: string;
  nfts: ApiNft[];
  chain: ApiChain;
  collectionAddress?: string;
  isFullLoading?: boolean;
  /** Complete set of addresses seen during a streaming session. Sent with the final `isFullLoading: false` update. */
  streamedAddresses?: string[];
};

export type ApiUpdateNftReceived = {
  type: 'nftReceived';
  accountId: string;
  nftAddress: string;
  nft: ApiNft;
};

export type ApiUpdateNftSent = {
  type: 'nftSent';
  accountId: string;
  nftAddress: string;
  newOwnerAddress: string;
};

export type ApiUpdateNftPutUpForSale = {
  type: 'nftPutUpForSale';
  accountId: string;
  nftAddress: string;
};

export type ApiNftUpdate = ApiUpdateNftReceived | ApiUpdateNftSent | ApiUpdateNftPutUpForSale;

export type ApiUpdateAccount = {
  type: 'updateAccount';
  accountId: string;
  chain: ApiChain;
  address?: string;
  /** `false` means that the account has no domain; `undefined` means that the domain has not changed */
  domain?: string | false;
  isMultisig?: boolean;
};

export type ApiUpdateConfig = {
  type: 'updateConfig';
  isLimited: boolean;
  isCopyStorageEnabled: boolean;
  supportAccountsCount?: number;
  countryCode?: ApiCountryCode;
  isAppUpdateRequired: boolean;
  swapVersion?: ApiSwapVersion;
  seasonalTheme: ApiBackendConfig['seasonalTheme'];
};

export type ApiUpdateWalletVersions = {
  type: 'updateWalletVersions';
  accountId: string;
  currentVersion: ApiTonWalletVersion;
  versions: ApiWalletWithVersionInfo[];
};

export type ApiOpenUrl = {
  type: 'openUrl';
  url: string;
  isExternal?: boolean;
  title?: string;
  subtitle?: string;
};

export type ApiRequestReconnect = {
  type: 'requestReconnectApi';
};

export type ApiUpdateIncorrectTime = {
  type: 'incorrectTime';
};

export type ApiUpdateVesting = {
  type: 'updateVesting';
  accountId: string;
  vestingInfo: ApiVestingInfo[];
};

export type ApiUpdatingStatus = {
  type: 'updatingStatus';
  kind: 'balance' | 'activities';
  accountId: string;
  isUpdating?: boolean;
};

export type ApiUpdateSettings = {
  type: 'updateSettings';
  settings: Partial<GlobalState['settings']>;
};

export type ApiMigrateCoreApplication = {
  type: 'migrateCoreApplication';
  isTestnet?: boolean;
  accountId: string;
  address: string;
  secondAccountId: string;
  secondAddress: string;
  isTonProxyEnabled?: boolean;
};

export type ApiUpdateAccountConfig = {
  type: 'updateAccountConfig';
  accountId: string;
  accountConfig: ApiAccountConfig;
};

export type ApiUpdateAccountDomainData = {
  type: 'updateAccountDomainData';
  accountId: string;
  expirationByAddress: Record<string, number>;
  linkedAddressByAddress: Record<string, string>;
  nfts: Record<string, ApiNft>;
};

export type ApiUpdate =
  | ApiUpdateBalances
  | ApiUpdateInitialActivities
  | ApiUpdateNewActivities
  | ApiUpdateNewLocalActivities
  | ApiUpdateTokens
  | ApiUpdateSwapTokens
  | ApiUpdateCurrencyRates
  | ApiUpdateCreateTransaction
  | ApiUpdateCompleteTransaction
  | ApiUpdateCreateSignature
  | ApiUpdateStaking
  | ApiUpdateDappSendTransactions
  | ApiUpdateTonConnectOnline
  | ApiUpdateDappConnect
  | ApiUpdateDappConnectComplete
  | ApiUpdateDappDisconnect
  | ApiUpdateDappLoading
  | ApiUpdateDappCloseLoading
  | ApiUpdateDappSignData
  | ApiUpdateDapps
  | ApiUpdateDappTransferComplete
  | ApiUpdateDappSignDataComplete
  | ApiUpdatePrepareTransaction
  | ApiUpdateProcessDeeplink
  | ApiUpdateShowError
  | ApiUpdateNfts
  | ApiNftUpdate
  | ApiUpdateAccount
  | ApiUpdateConfig
  | ApiUpdateWalletVersions
  | ApiOpenUrl
  | ApiRequestReconnect
  | ApiUpdateIncorrectTime
  | ApiUpdateVesting
  | ApiUpdatingStatus
  | ApiUpdateSettings
  | ApiMigrateCoreApplication
  | ApiUpdateAccountConfig
  | ApiUpdateAccountDomainData;

export type OnApiUpdate = (update: ApiUpdate) => void;
