import type { ApiChain, ApiNetwork, ApiToken, ApiTokenWithPrice } from '../api/types';

import {
  MYCOIN_MAINNET,
  MYCOIN_TESTNET,
  TON_TSUSDE,
  TON_USDE,
  TON_USDT_MAINNET,
  TON_USDT_TESTNET,
  TONCOIN, TRC20_USDT_MAINNET,
  TRC20_USDT_TESTNET,
  TRX,
} from '../config';
import formatTonTransferUrl from './ton/formatTransferUrl';
import { buildCollectionByKey, compact } from './iteratees';
import withCache from './withCache';

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
   * Configuration of the explorer of the chain.
   * The configuration does not contain data for NFT addresses, they must be configured separately.
   */
  explorer: {
    name: string;
    baseUrl: Record<ApiNetwork, string>;
    /** Use `{base}` as the base URL placeholder and `{address}` as the wallet address placeholder */
    address: string;
    /** Use `{base}` as the base URL placeholder and `{address}` as the token address placeholder */
    token: string;
    /** Use `{base}` as the base URL placeholder and `{hash}` as the transaction hash placeholder */
    transaction: string;
    doConvertHashFromBase64: boolean;
  };
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
    canTransferFullNativeBalance: true,
    isLedgerSupported: true,
    addressRegex: /^([-\w_]{48}|0:[\da-h]{64})$/i,
    addressPrefixRegex: /^([-\w_]{1,48}|0:[\da-h]{0,64})$/i,
    nativeToken: TONCOIN,
    doesBackendSocketSupport: true,
    canImportTokens: true,
    shouldShowScamWarningIfNotEnoughGas: false,
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
    explorer: {
      name: 'Tonscan',
      baseUrl: {
        mainnet: 'https://tonscan.org/',
        testnet: 'https://testnet.tonscan.org/',
      },
      address: '{base}address/{address}',
      token: '{base}jetton/{address}',
      transaction: '{base}tx/{hash}',
      doConvertHashFromBase64: true,
    },
    isNetWorthSupported: true,
    formatTransferUrl: formatTonTransferUrl,
  },
  tron: {
    title: 'TRON',
    isDnsSupported: false,
    canBuyWithCardInRussia: false,
    isTransferPayloadSupported: false,
    canTransferFullNativeBalance: false,
    isLedgerSupported: false,
    addressRegex: /^T[1-9A-HJ-NP-Za-km-z]{33}$/,
    addressPrefixRegex: /^T[1-9A-HJ-NP-Za-km-z]{0,33}$/,
    nativeToken: TRX,
    doesBackendSocketSupport: true,
    canImportTokens: false,
    shouldShowScamWarningIfNotEnoughGas: true,
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
    explorer: {
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
    isNetWorthSupported: false,
  },
};

export function getChainConfig(chain: ApiChain): ChainConfig {
  return CHAIN_CONFIG[chain];
}

export function findChainConfig(chain: string | undefined): ChainConfig | undefined {
  return chain ? CHAIN_CONFIG[chain as ApiChain] : undefined;
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
