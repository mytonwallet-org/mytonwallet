import type { ApiChain, ApiNetwork, ApiToken, ApiTokenWithPrice } from '../api/types';

import {
  MYCOIN_MAINNET,
  MYCOIN_TESTNET,
  SOLANA,
  SOLANA_USDT_MAINNET,
  SOLANA_USDС_MAINNET,
  TON_TSUSDE,
  TON_USDE,
  TON_USDT_MAINNET,
  TON_USDT_TESTNET,
  TONCOIN,
  TRC20_USDT_MAINNET,
  TRC20_USDT_TESTNET,
  TRX,
} from '../config';
import formatTonTransferUrl from './ton/formatTransferUrl';
import { buildCollectionByKey, compact } from './iteratees';
import withCache from './withCache';

export type ExplorerLink = {
  url: string;
  param: string;
} | string;

export interface BaseExplorerConfig {
  id: string;
  name: string;
  baseUrl: Record<ApiNetwork, ExplorerLink>;
}
export interface ExplorerConfig extends BaseExplorerConfig {
  /** Use `{base}` as the base URL placeholder and `{address}` as the wallet address placeholder */
  address: string;
  /** Use `{base}` as the base URL placeholder and `{address}` as the token address placeholder */
  token: string;
  /** Use `{base}` as the base URL placeholder and `{hash}` as the transaction hash placeholder */
  transaction: string;
  /** Use `{base}` as the base URL placeholder and `{address}` as the NFT address placeholder */
  nft?: string;
  /** Use `{base}` as the base URL placeholder and `{address}` as the NFT collection address placeholder */
  nftCollection?: string;
  doConvertHashFromBase64: boolean;
}

export interface MarketplaceConfig extends BaseExplorerConfig {
  nft: string;
  /** Use `{base}` as the base URL placeholder and `{address}` as the NFT collection address placeholder */
  nftCollection?: string;
}

/**
 * Describes the chain features that distinguish it from other chains in the multichain-polymorphic parts of the code.
 */
export interface ChainConfig {
  /** The blockchain title to show in the UI */
  title: string;
  /** Whether the chain supports domain names that resolve to regular addresses */
  isDnsSupported: boolean;
  /** Whether MyTonWallet supports purchasing crypto in that blockchain with a bank card in Russia */
  canBuyWithCardInRussia: boolean;
  /** Whether the chain supports sending asset transfers with a comment */
  isTransferPayloadSupported: boolean;
  /** Whether the chain supports comment encrypting */
  isEncryptedCommentSupported: boolean;
  /** Whether the chain supports sending the full balance of the native token (the fee is taken from the sent amount) */
  canTransferFullNativeBalance: boolean;
  /** Whether Ledger support is implemented for this chain */
  isLedgerSupported: boolean;
  /** Regular expression for wallet and contract addresses in the chain */
  addressRegex: RegExp;
  /** The same regular expression but matching any prefix of a valid address */
  addressPrefixRegex: RegExp;
  /** The native token of the chain, i.e. the token that pays the fees */
  nativeToken: ApiToken;
  /** Whether our own backend socket (src/api/common/backendSocket.ts) supports this chain */
  doesBackendSocketSupport: boolean;
  /** Whether the SDK allows to import tokens by address */
  canImportTokens: boolean;
  /** If `true`, the Send form UI will show a scam warning if the wallet has tokens but not enough gas to sent them */
  shouldShowScamWarningIfNotEnoughGas: boolean;
  /** Whether our own backend supports push notifications for addresses in this chain */
  doesSupportPushNotifications: boolean;
  /** A random but valid address for checking transfer fees */
  feeCheckAddress: string;
  /** A swap configuration used to buy the native token in this chain */
  buySwap: {
    tokenInSlug: string;
    /** Amount as perceived by the user */
    amountIn: string;
  };
  /** The slug of the USDT token in this chain, if it has USDT */
  usdtSlug: Record<ApiNetwork, string | undefined>;
  /** The token slugs of this chain added to new accounts by default. */
  defaultEnabledSlugs: Record<ApiNetwork, string[]>;
  /** The token slugs of this chain supported by the crosschain (CEX) swap mechanism. */
  crosschainSwapSlugs: string[];
  /**
   * The tokens to fill the token cache until it's loaded from the backend.
   * Should include the tokens from the above lists, and the staking tokens.
   */
  tokenInfo: (ApiToken & Partial<ApiTokenWithPrice>)[];
  /**
   * Configuration of available explorers for the chain.
   * The configuration does not contain data for NFT addresses, they must be configured separately.
   */
  explorers: ExplorerConfig[];

  /**
   * Configuration of available NFT marketplaces on chain.
   * Implements structure of config for explorers, but NFT-related fields only.
   * Empty, if NFTs are not supported
   */
  marketplaces: MarketplaceConfig[];
  /** Whether the chain supports NFTs */
  isNftSupported: boolean;
  /** Max number of NFTs to request per pagination batch (for NFT-supporting chains) */
  nftBatchLimit?: number;
  /** Pause in ms between NFT pagination batches (for NFT-supporting chains) */
  nftBatchPauseMs?: number;
  /** Whether the chain supports net worth details */
  isNetWorthSupported: boolean;
  /** Builds a link to transfer assets in this chain. If not set, the chain won't have the Deposit Link modal. */
  formatTransferUrl?(address: string, amount?: bigint, text?: string, jettonAddress?: string): string;
}

const CHAIN_CONFIG: Record<ApiChain, ChainConfig> = {
  ton: {
    title: 'TON',
    isDnsSupported: true,
    canBuyWithCardInRussia: true,
    isTransferPayloadSupported: true,
    isEncryptedCommentSupported: true,
    canTransferFullNativeBalance: true,
    isLedgerSupported: true,
    isNftSupported: true,
    addressRegex: /^([-\w_]{48}|0:[\da-h]{64})$/i,
    addressPrefixRegex: /^([-\w_]{1,48}|0:[\da-h]{0,64})$/i,
    nativeToken: TONCOIN,
    doesBackendSocketSupport: true,
    canImportTokens: true,
    shouldShowScamWarningIfNotEnoughGas: false,
    doesSupportPushNotifications: true,
    feeCheckAddress: 'UQBE5NzPPnfb6KAy7Rba2yQiuUnihrfcFw96T-p5JtZjAl_c',
    buySwap: {
      tokenInSlug: TRC20_USDT_MAINNET.slug,
      amountIn: '100',
    },
    usdtSlug: {
      mainnet: TON_USDT_MAINNET.slug,
      testnet: TON_USDT_TESTNET.slug,
    },
    defaultEnabledSlugs: {
      mainnet: [TONCOIN.slug, TON_USDT_MAINNET.slug],
      testnet: [TONCOIN.slug, TON_USDT_TESTNET.slug],
    },
    crosschainSwapSlugs: [TONCOIN.slug, TON_USDT_MAINNET.slug],
    tokenInfo: [
      TONCOIN,
      TON_USDT_MAINNET,
      TON_USDT_TESTNET,
      MYCOIN_MAINNET,
      MYCOIN_TESTNET,
      TON_USDE,
      TON_TSUSDE,
    ],
    explorers: [
      {
        id: 'tonscan',
        name: 'Tonscan',
        baseUrl: {
          mainnet: 'https://tonscan.org/',
          testnet: 'https://testnet.tonscan.org/',
        },
        address: '{base}address/{address}',
        token: '{base}jetton/{address}',
        transaction: '{base}tx/{hash}',
        nft: '{base}nft/{address}',
        nftCollection: '{base}collection/{address}',
        doConvertHashFromBase64: true,
      },
      {
        id: 'tonviewer',
        name: 'Tonviewer',
        baseUrl: {
          mainnet: 'https://tonviewer.com/',
          testnet: 'https://testnet.tonviewer.com/',
        },
        address: '{base}{address}?address',
        token: '{base}{address}?jetton',
        transaction: '{base}transaction/{hash}',
        nft: '{base}{address}?nft',
        nftCollection: '{base}{address}?collection',
        doConvertHashFromBase64: true,
      },
    ],
    marketplaces: [{
      id: 'getgems',
      name: 'Getgems',
      baseUrl: {
        mainnet: 'https://getgems.io/',
        testnet: 'https://testnet.getgems.io/',
      },
      nft: '{base}nft/{address}',
      nftCollection: '{base}collection/{address}',
    }],
    nftBatchLimit: 500,
    nftBatchPauseMs: 1000,
    isNetWorthSupported: true,
    formatTransferUrl: formatTonTransferUrl,
  },
  tron: {
    title: 'TRON',
    isDnsSupported: false,
    canBuyWithCardInRussia: false,
    isTransferPayloadSupported: false,
    isEncryptedCommentSupported: false,
    canTransferFullNativeBalance: false,
    isLedgerSupported: false,
    isNftSupported: false,
    addressRegex: /^T[1-9A-HJ-NP-Za-km-z]{33}$/,
    addressPrefixRegex: /^T[1-9A-HJ-NP-Za-km-z]{0,33}$/,
    nativeToken: TRX,
    doesBackendSocketSupport: true,
    canImportTokens: false,
    shouldShowScamWarningIfNotEnoughGas: true,
    doesSupportPushNotifications: false,
    feeCheckAddress: 'TW2LXSebZ7Br1zHaiA2W1zRojDkDwjGmpw',
    buySwap: {
      tokenInSlug: TONCOIN.slug,
      amountIn: '10',
    },
    usdtSlug: {
      mainnet: TRC20_USDT_MAINNET.slug,
      testnet: TRC20_USDT_TESTNET.slug,
    },
    defaultEnabledSlugs: {
      mainnet: [TRX.slug, TRC20_USDT_MAINNET.slug],
      testnet: [TRX.slug, TRC20_USDT_TESTNET.slug],
    },
    crosschainSwapSlugs: [TRX.slug, TRC20_USDT_MAINNET.slug],
    tokenInfo: [
      TRX,
      TRC20_USDT_MAINNET,
      TRC20_USDT_TESTNET,
    ],
    explorers: [
      {
        id: 'tronscan',
        name: 'Tronscan',
        baseUrl: {
          mainnet: 'https://tronscan.org/#/',
          testnet: 'https://shasta.tronscan.org/#/',
        },
        address: '{base}address/{address}',
        token: '{base}token20/{address}',
        transaction: '{base}transaction/{hash}',
        doConvertHashFromBase64: false,
      },
    ],
    marketplaces: [],
    isNetWorthSupported: false,
  },
  solana: {
    title: 'Solana',
    isDnsSupported: false,
    canBuyWithCardInRussia: false,
    isTransferPayloadSupported: true,
    isEncryptedCommentSupported: false,
    canTransferFullNativeBalance: false,
    isLedgerSupported: false,
    isNftSupported: true,
    addressRegex: /^[1-9A-HJ-NP-Za-km-z]{32,44}$/,
    addressPrefixRegex: /^[1-9A-HJ-NP-Za-km-z]{0,44}$/,
    nativeToken: SOLANA,
    doesBackendSocketSupport: false,
    canImportTokens: false,
    shouldShowScamWarningIfNotEnoughGas: false,
    feeCheckAddress: '35YT7tt9edJbroEKaC3T3XY4cLNWKtVzmyTEfW8LHPEA',
    buySwap: {
      tokenInSlug: SOLANA_USDT_MAINNET.slug,
      amountIn: '100',
    },
    usdtSlug: {
      mainnet: SOLANA_USDT_MAINNET.slug,
      testnet: undefined,
    },
    defaultEnabledSlugs: {
      mainnet: [SOLANA.slug, SOLANA_USDT_MAINNET.slug, SOLANA_USDС_MAINNET.slug],
      testnet: [SOLANA.slug],
    },
    crosschainSwapSlugs: [SOLANA.slug, SOLANA_USDT_MAINNET.slug],
    tokenInfo: [
      SOLANA,
      SOLANA_USDT_MAINNET,
    ],
    explorers: [{
      id: 'solscan',
      name: 'Solscan',
      baseUrl: {
        mainnet: 'https://solscan.io/',
        testnet: {
          url: 'https://solscan.io/',
          param: '?cluster=devnet',
        },
      },
      address: '{base}account/{address}',
      token: '{base}token/{address}',
      transaction: '{base}tx/{hash}',
      nft: '{base}token/{address}',
      // Сollections on solana are grouping by master token address
      nftCollection: '{base}token/{address}',
      doConvertHashFromBase64: false,
    }],
    marketplaces: [{
      id: 'magicEden',
      name: 'Magic Eden',
      baseUrl: {
        mainnet: 'https://magiceden.io/',
        testnet: '', // No testnet support
      },
      nft: '{base}item-details/{address}',
    }],
    nftBatchLimit: 500,
    nftBatchPauseMs: 1000,
    isNetWorthSupported: false,
    doesSupportPushNotifications: false,
  },
};

export function getChainConfig(chain: ApiChain): ChainConfig {
  return CHAIN_CONFIG[chain];
}

export function findChainConfig(chain: string | undefined): ChainConfig | undefined {
  return chain ? CHAIN_CONFIG[chain as ApiChain] : undefined;
}

export function getAvailableExplorers(chain: ApiChain): ExplorerConfig[] {
  return getChainConfig(chain).explorers;
}

export function getAvailableMarketplaces(chain: ApiChain): MarketplaceConfig[] {
  return getChainConfig(chain).marketplaces;
}

export function getExplorer(chain: ApiChain, explorerId?: string): ExplorerConfig {
  const explorers = getAvailableExplorers(chain);

  if (explorerId) {
    const explorer = explorers.find((e) => e.id === explorerId);
    if (explorer) return explorer;
  }

  return explorers[0];
}

export function getMarketplace(chain: ApiChain, id?: string): MarketplaceConfig {
  const marketplaces = getAvailableMarketplaces(chain);

  if (id) {
    const marketplace = marketplaces.find((e) => e.id === id);
    if (marketplace) return marketplace;
  }

  return marketplaces[0];
}

export function getChainTitle(chain: ApiChain) {
  return getChainConfig(chain).title;
}

export function getIsSupportedChain(chain?: string): chain is ApiChain {
  return !!findChainConfig(chain);
}

export function getSupportedChains() {
  return Object.keys(CHAIN_CONFIG) as (keyof typeof CHAIN_CONFIG)[];
}

/** Returns the chains supported by the given account in the proper order for showing in the UI */
export function getOrderedAccountChains(byChain: Partial<Record<ApiChain, unknown>>) {
  return getSupportedChains().filter((chain) => chain in byChain);
}

export function getChainsSupportingLedger(): ApiChain[] {
  return (Object.keys(CHAIN_CONFIG) as (keyof typeof CHAIN_CONFIG)[])
    .filter((chain) => CHAIN_CONFIG[chain].isLedgerSupported);
}

export const getChainsSupportingNft = /* #__PURE__ */ withCache((): ReadonlySet<ApiChain> => {
  return new Set(
    (Object.keys(CHAIN_CONFIG) as (keyof typeof CHAIN_CONFIG)[])
      .filter((chain) => CHAIN_CONFIG[chain].isNftSupported),
  );
});

export const getTrustedUsdtSlugs = /* #__PURE__ */ withCache((): ReadonlySet<string> => {
  return new Set(
    Object.values(CHAIN_CONFIG).flatMap(({ usdtSlug }) => {
      return compact([
        usdtSlug.mainnet,
        usdtSlug.testnet,
      ]);
    }),
  );
});

export const getDefaultEnabledSlugs = /* #__PURE__ */ withCache((network: ApiNetwork): ReadonlySet<string> => {
  return new Set(
    Object.values(CHAIN_CONFIG)
      .flatMap((chainConfig) => chainConfig.defaultEnabledSlugs[network]),
  );
});

export const getSlugsSupportingCexSwap = /* #__PURE__ */ withCache((): ReadonlySet<string> => {
  return new Set(
    Object.values(CHAIN_CONFIG)
      .flatMap((chainConfig) => chainConfig.crosschainSwapSlugs),
  );
});

/** Returns the tokens from all the chains to fill the token cache until it's loaded from the backend */
export const getTokenInfo = /* #__PURE__ */ withCache((): Readonly<Record<string, ApiTokenWithPrice>> => {
  const commonToken = {
    isFromBackend: true,
    priceUsd: 0,
    percentChange24h: 0,
  };

  const allTokens = Object.values(CHAIN_CONFIG).flatMap((chainConfig) => {
    return chainConfig.tokenInfo.map((token) => ({ ...commonToken, ...token }));
  });

  return buildCollectionByKey(allTokens, 'slug');
});
