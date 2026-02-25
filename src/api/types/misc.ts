import type { NftItem } from 'tonapi-sdk-js';
import type { Base58EncodedBytes } from '@solana/kit';

import type { LangCode } from '../../global/types';
import type { ApiTonWalletVersion } from '../chains/ton/types';
import type { DappProtocolType } from '../dappProtocols';
import type { ApiTransactionActivity } from './activities';
import type { ApiParsedPayload } from './payload';
import type { ApiSseOptions } from './storage';
import type { ApiUpdatingStatus } from './updates';

export type ApiChain = 'ton' | 'tron' | 'solana';
export type ApiNetwork = 'mainnet' | 'testnet';
export type ApiLedgerDriver = 'HID' | 'USB';
export type ApiTokenType = 'lp_token' | 'legacy_token' | 'token_2022';
export type ApiDappConnectionType = 'connect' | 'sendTransaction' | 'signData';

export interface AccountIdParsed {
  id: number;
  network: ApiNetwork;
}

export interface ApiInitArgs {
  isElectron?: boolean;
  isIosApp?: boolean;
  isAndroidApp?: boolean;
  langCode?: LangCode;
  referrer?: string;
  accountIds?: string[];
}

export interface ApiToken {
  name: string;
  symbol: string;
  slug: string;
  decimals: number;
  chain: ApiChain;
  type?: ApiTokenType;
  tokenAddress?: string;
  tokenWalletAddress?: string;
  image?: string;
  isPopular?: boolean;
  keywords?: string[];
  cmcSlug?: string;
  color?: string;
  isGaslessEnabled?: boolean;
  isStarsEnabled?: boolean;
  isTiny?: boolean;
  customPayloadApiUrl?: string;
  codeHash?: string;
  /** A small dim label to show in the UI right after the token name */
  label?: string;
  /* Means the token is fetched from the backend by default and already includes price
  and other details (`ApiTokenDetails`), so no separate requests are needed. */
  isFromBackend?: boolean;
}

export type ApiTokenWithPrice = ApiToken & {
  priceUsd: number;
  percentChange24h: number;
};

export type ApiTokenWithMaybePrice = ApiToken & {
  priceUsd: undefined | ApiTokenWithPrice['priceUsd'];
  percentChange24h: undefined | ApiTokenWithPrice['percentChange24h'];
};

export type ApiKnownAddresses = Record<string, ApiKnownAddressInfo>;

export interface ApiKnownAddressInfo {
  name?: string;
  isScam?: boolean;
  isMemoRequired?: boolean;
}

export interface ApiNftSuperCollection {
  id: string;
  name: string;
  icon?: 'gift';
}

export type ApiActivityTimestamps = Record<string, number | undefined>;
export type ApiTransactionType = 'stake' | 'unstake' | 'unstakeRequest'
  | 'callContract' | 'excess' | 'contractDeploy' | 'bounced'
  | 'mint' | 'burn' | 'auctionBid' | 'nftTrade'
  | 'dnsChangeAddress' | 'dnsChangeSite' | 'dnsChangeSubdomains' | 'dnsChangeStorage' | 'dnsDelete' | 'dnsRenew'
  | 'liquidityDeposit' | 'liquidityWithdraw'
  | undefined;

export interface ApiTransaction extends BaseApiTransaction {
  timestamp: number;
  comment?: string;
  encryptedComment?: string;
  /** Trace external message hash normalized. Only for TON. */
  externalMsgHashNorm?: string;
  shouldHide?: boolean;
  type?: ApiTransactionType;
  metadata?: ApiTransactionMetadata;
  nft?: ApiNft;
  /**
   * Transaction confirmation status
   * Both 'pendingTrusted' and 'pending' mean the transaction is awaiting confirmation by the blockchain.
   * - 'pendingTrusted' — awaiting confirmation and trusted (initiated by our app)
   * - 'pending' — awaiting confirmation from an external/unauthenticated source, like TonConnect emulation
   * - 'confirmed' — included in a shardblock but not yet finalized in the masterchain
   */
  status: 'pending' | 'pendingTrusted' | 'confirmed' | 'completed' | 'failed';
}

export interface BaseApiTransaction {
  /** The amount to show in the UI (may mismatch the actual attached TON amount) */
  amount: bigint;
  fromAddress: string;
  toAddress: string;
  slug: string;
  isIncoming: boolean;
  normalizedAddress: string; // Only for TON now
  /**
   * The fee to show in the UI (not the same as the network fee). When not 0, should be shown even for incoming
   * transactions. It means that there was a hidden outgoing transaction with the given fee.
   */
  fee: bigint;
}

export type ApiTransactionMetadata = ApiKnownAddressInfo;

export type ApiMtwCardType = 'black' | 'platinum' | 'gold' | 'silver' | 'standard';
export type ApiMtwCardTextType = 'light' | 'dark';
export type ApiMtwCardBorderShineType = 'up' | 'down' | 'left' | 'right' | 'radioactive';

export interface ApiNftAttribute {
  trait_type: string;
  value: string;
}

export interface ApiNftMetadata {
  attributes?: ApiNftAttribute[];
  lottie?: string;
  imageUrl?: string;
  fragmentUrl?: string;
  mtwCardId?: number;
  mtwCardType?: ApiMtwCardType;
  mtwCardTextType?: ApiMtwCardTextType;
  mtwCardBorderShineType?: ApiMtwCardBorderShineType;
}

export interface ApiNft {
  chain: ApiChain;
  index: number;
  ownerAddress?: string;
  name?: string;
  address: string;
  thumbnail: string;
  image: string;
  description?: string;
  collectionName?: string;
  collectionAddress?: string;
  isOnSale: boolean;
  isHidden?: boolean;
  isOnFragment?: boolean;
  isTelegramGift?: boolean;
  isScam?: boolean;
  metadata: ApiNftMetadata;
  interface: 'default' | 'compressed' | 'mplCore';
  compression?: {
    tree: string;
    dataHash: string;
    creatorHash: string;
    leafId: number;
  };
}

export interface ApiNftCollection {
  chain: ApiChain;
  address: string;
}

export interface ApiDomainData {
  domain: string;
  linkedAddress?: string;
  lastFillUpTime: string;
  nft: NftItem;
}

export type ApiHistoryList = Array<[number, number]>;

export type ApiStakingType = ApiStakingState['type'];
export type ApiBackendStakingType = 'nominators' | 'liquid';

type BaseStakingState = {
  id: string;
  tokenSlug: string;
  annualYield: number;
  yieldType: ApiYieldType;
  balance: bigint;
  pool: string;
  unstakeRequestAmount?: bigint;
};

export type ApiNominatorsStakingState = BaseStakingState & {
  type: 'nominators';
  start: number;
  end: number;
};

export type ApiLiquidStakingState = BaseStakingState & {
  type: 'liquid';
  tokenBalance: bigint;
  instantAvailable: bigint;
  start: number;
  end: number;
};

export type ApiJettonStakingState = BaseStakingState & {
  type: 'jetton';
  tokenAddress: string;
  unclaimedRewards: bigint;
  stakeWalletAddress: string;
  tokenAmount: bigint;
  period: number;
  tvl: bigint;
  dailyReward: bigint;
  poolWallets?: string[];
};

export type ApiEthenaStakingState = BaseStakingState & {
  type: 'ethena';
  tokenBalance: bigint;
  tsUsdeWalletAddress: string;
  unstakeRequestAmount: bigint;
  unlockTime?: number;
  isBoostAvailable?: boolean;
  annualYieldStandard?: number;
  annualYieldVerified?: number;
};

export type ApiYieldType = 'APY' | 'APR';
export type ApiStakingState = ApiNominatorsStakingState
  | ApiLiquidStakingState
  | ApiJettonStakingState
  | ApiEthenaStakingState;
export type ApiToncoinStakingState = ApiNominatorsStakingState | ApiLiquidStakingState;

export interface ApiNominatorsPool {
  address: string;
  apy: number;
  start: number;
  end: number;
}

export interface ApiBackendStakingState {
  balance: bigint;
  totalProfit: bigint;
  type?: ApiBackendStakingType;
  nominatorsPool: ApiNominatorsPool;
  loyaltyType?: ApiLoyaltyType;
  shouldUseNominators?: boolean;
  stakedAt?: number;
  ethena: {
    /**
     * - undefined — never passed the verification;
     * - true — passed the verification and eligible for the boosted APY;
     * - false — passed the verification and not eligible for the boosted APY;
     */
    isVerified?: boolean;
    isBoostAvailable?: boolean;
  };
  liquid?: {
    unstakeRequestAmount?: string;
  };
}

export type ApiStakingHistory = {
  timestamp: number;
  profit: string;
}[];

export interface ApiDappPermissions {
  isAddressRequired?: boolean;
  isPasswordRequired?: boolean;
}

export type ApiDappRequest = {
  url: string | undefined; // `undefined` is a special case for SSE connect request
  isUrlEnsured?: boolean;
  accountId?: string;
  identifier?: string;
  sseOptions?: ApiSseOptions;
};

export interface ApiTransferToSign {
  chain: ApiChain;
  toAddress: string;
  amount: bigint;
  rawPayload?: string;
  payload?: ApiParsedPayload;
  stateInit?: string;
}

export interface ApiDappTransfer extends ApiTransferToSign {
  isScam?: boolean;
  /** Whether the transfer should be treated with cautiousness, because its payload is unclear */
  isDangerous: boolean;
  normalizedAddress: string;
  /** The transfer address to show in the UI */
  displayedToAddress: string;
  networkFee: bigint;
}

export interface ApiSignedTransfer<T extends DappProtocolType = any> {
  chain: T extends 'tonConnect' ? 'ton' : ApiChain;
  payload: T extends 'tonConnect' ? {
    base64: string;
    seqno: number;
  } : {
    signature: string;
    base58Tx: Base58EncodedBytes;
  };
}

/**
 * The `fee` field should contain the final (real) fee, because we want to show the real fee in local transactions
 */
export type ApiLocalTransactionParams = Omit<
  ApiTransactionActivity,
  'timestamp' | 'isIncoming' | 'normalizedAddress' | 'kind' | 'shouldLoadDetails' | 'status'
> & {
  normalizedAddress?: string;
  isIncoming?: boolean;
  status?: ApiTransactionActivity['status'];
};

export type ApiBaseCurrency = 'USD' | 'EUR' | 'RUB' | 'CNY' | 'BTC' | 'TON';

/** 1 USD equivalent to the amount of the other currency, e.g. 1 USD = 0.00000866 BTC */
export type ApiCurrencyRates = Record<ApiBaseCurrency, string>;

export enum ApiLiquidUnstakeMode {
  Default,
  Instant,
  BestRate,
}

export type ApiLoyaltyType = 'black' | 'platinum' | 'gold' | 'silver' | 'standard';

export type ApiBalanceBySlug = Record<string, bigint>;

export type ApiWalletInfo = {
  /** The user-friendly address of this wallet (may differ from the requested address) */
  address: string;
  /** Undefined when the address is not initialized or not a wallet */
  version?: ApiTonWalletVersion;
  balance: bigint;
  isInitialized: boolean;
  seqno: number;
  lastTxId?: string;
  domain?: string;
};

export type ApiWalletWithVersionInfo = ApiWalletInfo & Required<Pick<ApiWalletInfo, 'version'>> & {
  /** Whether the wallet is with testnet subwallet ID. `undefined` if the wallet is not a W5 wallet
   Previously we had a bug that caused W5 testnet wallets to be created with mainnet subwallet ID.
   To protect from replay attacks, we need to use specific subwallet ID for testnet wallets.
   For backward compatibility, we need to support both subwallet IDs on testnet.
  */
  isTestnetSubwalletId?: boolean;
};

// Country codes from ISO-3166-1 spec
export type ApiCountryCode = 'AF' | 'AX' | 'AL' | 'DZ' | 'AS' | 'AD' | 'AO' | 'AI' | 'AQ' | 'AG' | 'AR'
  | 'AM' | 'AW' | 'AU' | 'AT' | 'AZ' | 'BS' | 'BH' | 'BD' | 'BB' | 'BY' | 'BE' | 'BZ' | 'BJ' | 'BM'
  | 'BT' | 'BO' | 'BQ' | 'BA' | 'BW' | 'BV' | 'BR' | 'IO' | 'BN' | 'BG' | 'BF' | 'BI' | 'CV' | 'KH'
  | 'CM' | 'CA' | 'KY' | 'CF' | 'TD' | 'CL' | 'CN' | 'CX' | 'CC' | 'CO' | 'KM' | 'CG' | 'CD' | 'CK'
  | 'CR' | 'CI' | 'HR' | 'CU' | 'CW' | 'CY' | 'CZ' | 'DK' | 'DJ' | 'DM' | 'DO' | 'EC' | 'EG' | 'SV'
  | 'GQ' | 'ER' | 'EE' | 'SZ' | 'ET' | 'FK' | 'FO' | 'FJ' | 'FI' | 'FR' | 'GF' | 'PF' | 'TF' | 'GA'
  | 'GM' | 'GE' | 'DE' | 'GH' | 'GI' | 'GR' | 'GL' | 'GD' | 'GP' | 'GU' | 'GT' | 'GG' | 'GN' | 'GW'
  | 'GY' | 'HT' | 'HM' | 'VA' | 'HN' | 'HK' | 'HU' | 'IS' | 'IN' | 'ID' | 'IR' | 'IQ' | 'IE' | 'IM'
  | 'IL' | 'IT' | 'JM' | 'JP' | 'JE' | 'JO' | 'KZ' | 'KE' | 'KI' | 'KP' | 'KR' | 'KW' | 'KG' | 'LA'
  | 'LV' | 'LB' | 'LS' | 'LR' | 'LY' | 'LI' | 'LT' | 'LU' | 'MO' | 'MG' | 'MW' | 'MY' | 'MV' | 'ML'
  | 'MT' | 'MH' | 'MQ' | 'MR' | 'MU' | 'YT' | 'MX' | 'FM' | 'MD' | 'MC' | 'MN' | 'ME' | 'MS' | 'MA'
  | 'MZ' | 'MM' | 'NA' | 'NR' | 'NP' | 'NL' | 'NC' | 'NZ' | 'NI' | 'NE' | 'NG' | 'NU' | 'NF' | 'MP'
  | 'NO' | 'OM' | 'PK' | 'PW' | 'PS' | 'PA' | 'PG' | 'PY' | 'PE' | 'PH' | 'PN' | 'PL' | 'PT' | 'PR'
  | 'QA' | 'MK' | 'RO' | 'RU' | 'RW' | 'RE' | 'BL' | 'SH' | 'KN' | 'LC' | 'MF' | 'PM' | 'VC' | 'WS'
  | 'SM' | 'ST' | 'SA' | 'SN' | 'RS' | 'SC' | 'SL' | 'SG' | 'SX' | 'SK' | 'SI' | 'SB' | 'SO' | 'ZA'
  | 'GS' | 'SS' | 'ES' | 'LK' | 'SD' | 'SR' | 'SJ' | 'SE' | 'CH' | 'SY' | 'TW' | 'TJ' | 'TZ' | 'TH'
  | 'TL' | 'TG' | 'TK' | 'TO' | 'TT' | 'TN' | 'TR' | 'TM' | 'TC' | 'TV' | 'UG' | 'UA' | 'AE' | 'GB'
  | 'US' | 'UM' | 'UY' | 'UZ' | 'VU' | 'VE' | 'VN' | 'VG' | 'VI' | 'WF' | 'EH' | 'YE' | 'ZM' | 'ZW';

/** Each string value can be either an address or a domain name */
export type ApiImportAddressByChain = Partial<Record<ApiChain, string>>;

export type ApiNftMarketplace = 'fragment' | 'getgems';

export type OnUpdatingStatusChange = (kind: ApiUpdatingStatus['kind'], isUpdating: boolean) => void;
