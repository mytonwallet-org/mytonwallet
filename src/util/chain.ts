import type { ApiChain, ApiNetwork, ApiToken, ApiTokenWithPrice } from '../api/types';

import {
  ARBITRUM,
  BASE,
  BASE_USDC_MAINNET,
  BASE_USDT_MAINNET,
  BNB,
  BSC_USDT_MAINNET,
  DEBUG,
  ETH,
  ETH_USDC_MAINNET,
  ETH_USDT_MAINNET,
  HYPERLIQUID,
  HYPERLIQUID_USDC_MAINNET,
  MYCOIN_MAINNET,
  MYCOIN_TESTNET,
  SOLANA,
  SOLANA_USDC_MAINNET,
  SOLANA_USDT_MAINNET,
  TON_TSUSDE,
  TON_USDE,
  TON_USDT_MAINNET,
  TON_USDT_TESTNET,
  TONCOIN,
  TRC20_USDT_MAINNET,
  TRC20_USDT_TESTNET,
  TRX,
} from '../config';
import { EVM_DERIVATION_PATHS } from '../api/chains/evm/constants';
import { SOLANA_DERIVATION_PATHS } from '../api/chains/solana/constants';
import { TON_BIP39_PATH } from '../api/chains/ton/constants';
import { TRON_BIP39_PATH } from '../api/chains/tron/constants';
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
  /** The standard of the chain, e.g. `ethereum` for EVM chains */
  chainStandard?: ApiChain;
  /** Whether the chain supports domain names that resolve to regular addresses */
  isDnsSupported: boolean;
  /** Whether MyTonWallet supports purchasing crypto in that blockchain with a bank card in Russia */
  canBuyWithCardInRussia: boolean;
  /** Whether the chain is supported by the on-ramp widget (Moonpay outside RU, Avanchange in RU) */
  isOnRampSupported: boolean;
  /** Whether the chain is supported by the off-ramp widget (Moonpay) */
  isOffRampSupported: boolean;
  /** Whether the chain supports sending asset transfers with a comment */
  isTransferPayloadSupported: boolean;
  /** Whether the chain supports comment encrypting */
  isEncryptedCommentSupported: boolean;
  /** Whether the chain supports sending the full balance of the native token (the fee is taken from the sent amount) */
  canTransferFullNativeBalance: boolean;
  /** Whether Ledger support is implemented for this chain */
  isLedgerSupported: boolean;
  /** Whether the chain supports multiWallet (e.g. Solana derivations or TON versions) */
  isSubwalletsSupported: boolean;
  /** The default derivation path for the chain */
  defaultDerivationPath?: string;
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
  /** A swap configuration used to buy the native token in this chain. If absent, the "Buy with Crypto" UI is hidden. */
  buySwap?: {
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

// The supported chains are stored in the correct order, the chain with the more specific address (Regex) must be first
export const CHAIN_ORDER: ApiChain[] = [
  'ton',
  'tron',
  'solana',
  'ethereum',
  'base',
  'bnb',
  // 'polygon',
  'arbitrum',
  // 'monad',
  // 'avalanche',
  'hyperliquid',
];

const CHAIN_CONFIG: Record<ApiChain, ChainConfig> = {
  ton: {
    title: 'TON',
    isDnsSupported: true,
    canBuyWithCardInRussia: true,
    isOnRampSupported: true,
    isOffRampSupported: true,
    isTransferPayloadSupported: true,
    isEncryptedCommentSupported: true,
    canTransferFullNativeBalance: true,
    isLedgerSupported: true,
    isSubwalletsSupported: true,
    defaultDerivationPath: TON_BIP39_PATH,
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
      mainnet: [TONCOIN.slug],
      testnet: [TONCOIN.slug],
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
    isOnRampSupported: true,
    isOffRampSupported: true,
    isTransferPayloadSupported: false,
    isEncryptedCommentSupported: false,
    canTransferFullNativeBalance: false,
    isLedgerSupported: false,
    isSubwalletsSupported: true,
    defaultDerivationPath: TRON_BIP39_PATH,
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
      tokenInSlug: TON_USDT_MAINNET.slug,
      amountIn: '50',
    },
    usdtSlug: {
      mainnet: TRC20_USDT_MAINNET.slug,
      testnet: TRC20_USDT_TESTNET.slug,
    },
    defaultEnabledSlugs: {
      mainnet: [TRX.slug],
      testnet: [TRX.slug],
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
    isOnRampSupported: true,
    isOffRampSupported: true,
    isTransferPayloadSupported: true,
    isEncryptedCommentSupported: false,
    canTransferFullNativeBalance: false,
    isLedgerSupported: false,
    isSubwalletsSupported: true,
    defaultDerivationPath: SOLANA_DERIVATION_PATHS.phantom,
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
      mainnet: [SOLANA.slug],
      testnet: [SOLANA.slug],
    },
    crosschainSwapSlugs: [SOLANA.slug, SOLANA_USDT_MAINNET.slug],
    tokenInfo: [
      SOLANA,
      SOLANA_USDT_MAINNET,
      SOLANA_USDC_MAINNET,
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
  ethereum: {
    title: 'Ethereum',
    chainStandard: 'ethereum',
    isDnsSupported: false,
    canBuyWithCardInRussia: false,
    isOnRampSupported: true,
    isOffRampSupported: true,
    isTransferPayloadSupported: false,
    isEncryptedCommentSupported: false,
    canTransferFullNativeBalance: false,
    isLedgerSupported: false,
    isSubwalletsSupported: true,
    defaultDerivationPath: EVM_DERIVATION_PATHS.default,
    addressRegex: /^0x[a-fA-F0-9]{40}$/,
    addressPrefixRegex: /^0x[a-fA-F0-9]{0,40}$/,
    nativeToken: ETH,
    doesBackendSocketSupport: false,
    canImportTokens: false,
    shouldShowScamWarningIfNotEnoughGas: false,
    feeCheckAddress: '0x0000000000000000000000000000000000000000',
    buySwap: {
      tokenInSlug: TON_USDT_MAINNET.slug,
      amountIn: '50',
    },
    usdtSlug: {
      mainnet: ETH_USDT_MAINNET.slug,
      testnet: ETH_USDT_MAINNET.slug,
    },
    defaultEnabledSlugs: {
      mainnet: [ETH.slug],
      testnet: [ETH.slug],
    },
    crosschainSwapSlugs: [ETH.slug, ETH_USDT_MAINNET.slug],
    tokenInfo: [
      ETH,
      ETH_USDT_MAINNET,
      ETH_USDC_MAINNET,
    ],
    explorers: [{
      id: 'etherscan',
      name: 'Etherscan',
      baseUrl: {
        mainnet: 'https://etherscan.io/',
        testnet: 'https://sepolia.etherscan.io/',
      },
      address: '{base}address/{address}',
      token: '{base}token/{address}',
      nft: '{base}nft/{address}',
      transaction: '{base}tx/{hash}',
      doConvertHashFromBase64: false,
    }],
    marketplaces: [{
      id: 'openSea',
      name: 'OpenSea',
      baseUrl: {
        mainnet: 'https://opensea.io/',
        testnet: '', // No testnet support
      },
      nft: '{base}item/{chain}/{address}',
    }],
    isNetWorthSupported: false,
    doesSupportPushNotifications: false,
    isNftSupported: true,
  },
  base: {
    title: 'Base',
    chainStandard: 'ethereum',
    isDnsSupported: false,
    canBuyWithCardInRussia: false,
    isOnRampSupported: true,
    isOffRampSupported: true,
    isTransferPayloadSupported: false,
    isEncryptedCommentSupported: false,
    canTransferFullNativeBalance: false,
    isLedgerSupported: false,
    isSubwalletsSupported: true,
    defaultDerivationPath: EVM_DERIVATION_PATHS.default,
    addressRegex: /^0x[a-fA-F0-9]{40}$/,
    addressPrefixRegex: /^0x[a-fA-F0-9]{0,40}$/,
    nativeToken: BASE,
    doesBackendSocketSupport: false,
    canImportTokens: false,
    shouldShowScamWarningIfNotEnoughGas: false,
    feeCheckAddress: '0x0000000000000000000000000000000000000000',
    buySwap: {
      tokenInSlug: TON_USDT_MAINNET.slug,
      amountIn: '50',
    },
    usdtSlug: {
      mainnet: BASE_USDT_MAINNET.slug,
      testnet: BASE_USDT_MAINNET.slug,
    },
    defaultEnabledSlugs: {
      mainnet: [],
      testnet: [],
    },
    crosschainSwapSlugs: [BASE.slug],
    tokenInfo: [BASE, BASE_USDT_MAINNET, BASE_USDC_MAINNET],
    explorers: [{
      id: 'basescan',
      name: 'BaseScan',
      baseUrl: {
        mainnet: 'https://basescan.org/',
        testnet: 'https://sepolia.basescan.org/',
      },
      address: '{base}address/{address}',
      token: '{base}token/{address}',
      nft: '{base}nft/{address}',
      transaction: '{base}tx/{hash}',
      doConvertHashFromBase64: false,
    }],
    marketplaces: [{
      id: 'openSea',
      name: 'OpenSea',
      baseUrl: {
        mainnet: 'https://opensea.io/',
        testnet: '', // No testnet support
      },
      nft: '{base}item/{chain}/{address}',
    }],
    isNetWorthSupported: false,
    doesSupportPushNotifications: false,
    isNftSupported: true,
  },
  bnb: {
    title: 'BNB',
    chainStandard: 'ethereum',
    isDnsSupported: false,
    canBuyWithCardInRussia: false,
    isOnRampSupported: false,
    isOffRampSupported: false,
    isTransferPayloadSupported: false,
    isEncryptedCommentSupported: false,
    canTransferFullNativeBalance: false,
    isLedgerSupported: false,
    isSubwalletsSupported: true,
    defaultDerivationPath: EVM_DERIVATION_PATHS.default,
    addressRegex: /^0x[a-fA-F0-9]{40}$/,
    addressPrefixRegex: /^0x[a-fA-F0-9]{0,40}$/,
    nativeToken: BNB,
    doesBackendSocketSupport: false,
    canImportTokens: false,
    shouldShowScamWarningIfNotEnoughGas: false,
    feeCheckAddress: '0x0000000000000000000000000000000000000000',
    usdtSlug: {
      mainnet: BSC_USDT_MAINNET.slug,
      testnet: BSC_USDT_MAINNET.slug,
    },
    defaultEnabledSlugs: {
      mainnet: [BNB.slug],
      testnet: [BNB.slug],
    },
    crosschainSwapSlugs: [BNB.slug],
    tokenInfo: [BNB, BSC_USDT_MAINNET],
    explorers: [{
      id: 'bsctrace',
      name: 'BSCTrace',
      baseUrl: {
        mainnet: 'https://bscscan.com/',
        testnet: 'https://testnet.bscscan.com/',
      },
      address: '{base}address/{address}',
      token: '{base}token/{address}',
      nft: '{base}nft/{address}',
      transaction: '{base}tx/{hash}',
      doConvertHashFromBase64: false,
    }],
    marketplaces: [{
      id: 'openSea',
      name: 'OpenSea',
      baseUrl: {
        mainnet: 'https://opensea.io/',
        testnet: '', // No testnet support
      },
      nft: '{base}item/{chain}/{address}',
    }],
    isNetWorthSupported: false,
    doesSupportPushNotifications: false,
    isNftSupported: true,
  },
  // TODO: return this after release
  // polygon: {
  //   title: 'Polygon',
  //   chainStandard: 'ethereum',
  //   isDnsSupported: false,
  //   canBuyWithCardInRussia: false,
  //   isTransferPayloadSupported: false,
  //   isEncryptedCommentSupported: false,
  //   canTransferFullNativeBalance: false,
  //   isLedgerSupported: false,
  //   isSubwalletsSupported: true,
  //   defaultDerivationPath: EVM_DERIVATION_PATHS.default,
  //   addressRegex: /^0x[a-fA-F0-9]{40}$/,
  //   addressPrefixRegex: /^0x[a-fA-F0-9]{0,40}$/,
  //   nativeToken: POLYGON,
  //   doesBackendSocketSupport: false,
  //   canImportTokens: false,
  //   shouldShowScamWarningIfNotEnoughGas: false,
  //   feeCheckAddress: '0x0000000000000000000000000000000000000000',
  //   buySwap: {
  //     tokenInSlug: POLYGON.slug,
  //     amountIn: '100',
  //   },
  //   usdtSlug: {
  //     mainnet: '',
  //     testnet: '',
  //   },
  //   defaultEnabledSlugs: {
  //     mainnet: [],
  //     testnet: [],
  //   },
  //   crosschainSwapSlugs: [POLYGON.slug],
  //   tokenInfo: [POLYGON],
  //   explorers: [{
  //     id: 'polygonscan',
  //     name: 'Polygonscan',
  //     baseUrl: {
  //       mainnet: 'https://polygonscan.com/',
  //       testnet: 'https://testnet.polygonscan.com/',
  //     },
  //     address: '{base}address/{address}',
  //     token: '{base}token/{address}',
  //     nft: '{base}nft/{address}',
  //     transaction: '{base}tx/{hash}',
  //     doConvertHashFromBase64: false,
  //   }],
  //   marketplaces: [{
  //     id: 'openSea',
  //     name: 'OpenSea',
  //     baseUrl: {
  //       mainnet: 'https://opensea.io/',
  //       testnet: '', // No testnet support
  //     },
  //     nft: '{base}item/{chain}/{address}',
  //   }],
  //   isNetWorthSupported: false,
  //   doesSupportPushNotifications: false,
  //   isNftSupported: true,
  // },
  arbitrum: {
    title: 'Arbitrum',
    chainStandard: 'ethereum',
    isDnsSupported: false,
    canBuyWithCardInRussia: false,
    isOnRampSupported: true,
    isOffRampSupported: true,
    isTransferPayloadSupported: false,
    isEncryptedCommentSupported: false,
    canTransferFullNativeBalance: false,
    isLedgerSupported: false,
    isSubwalletsSupported: true,
    defaultDerivationPath: EVM_DERIVATION_PATHS.default,
    addressRegex: /^0x[a-fA-F0-9]{40}$/,
    addressPrefixRegex: /^0x[a-fA-F0-9]{0,40}$/,
    nativeToken: ARBITRUM,
    doesBackendSocketSupport: false,
    canImportTokens: false,
    shouldShowScamWarningIfNotEnoughGas: false,
    feeCheckAddress: '0x0000000000000000000000000000000000000000',
    buySwap: {
      tokenInSlug: TON_USDT_MAINNET.slug,
      amountIn: '50',
    },
    usdtSlug: {
      mainnet: '',
      testnet: '',
    },
    defaultEnabledSlugs: {
      mainnet: [],
      testnet: [],
    },
    crosschainSwapSlugs: [ARBITRUM.slug],
    tokenInfo: [ARBITRUM],
    explorers: [{
      id: 'arbiscan',
      name: 'Arbiscan',
      baseUrl: {
        mainnet: 'https://arbiscan.io/',
        testnet: 'https://sepolia.arbiscan.io/',
      },
      address: '{base}address/{address}',
      token: '{base}token/{address}',
      nft: '{base}nft/{address}',
      transaction: '{base}tx/{hash}',
      doConvertHashFromBase64: false,
    }],
    marketplaces: [{
      id: 'openSea',
      name: 'OpenSea',
      baseUrl: {
        mainnet: 'https://opensea.io/',
        testnet: '', // No testnet support
      },
      nft: '{base}item/{chain}/{address}',
    }],
    isNetWorthSupported: false,
    doesSupportPushNotifications: false,
    isNftSupported: true,
  },
  // monad: {
  //   title: 'Monad',
  //   chainStandard: 'ethereum',
  //   isDnsSupported: false,
  //   canBuyWithCardInRussia: false,
  //   isTransferPayloadSupported: false,
  //   isEncryptedCommentSupported: false,
  //   canTransferFullNativeBalance: false,
  //   isLedgerSupported: false,
  //   isSubwalletsSupported: true,
  //   defaultDerivationPath: EVM_DERIVATION_PATHS.default,
  //   addressRegex: /^0x[a-fA-F0-9]{40}$/,
  //   addressPrefixRegex: /^0x[a-fA-F0-9]{0,40}$/,
  //   nativeToken: MONAD,
  //   doesBackendSocketSupport: false,
  //   canImportTokens: false,
  //   shouldShowScamWarningIfNotEnoughGas: false,
  //   feeCheckAddress: '0x0000000000000000000000000000000000000000',
  //   buySwap: {
  //     tokenInSlug: MONAD.slug,
  //     amountIn: '10',
  //   },
  //   usdtSlug: {
  //     mainnet: '',
  //     testnet: '',
  //   },
  //   defaultEnabledSlugs: {
  //     mainnet: [],
  //     testnet: [],
  //   },
  //   crosschainSwapSlugs: [MONAD.slug],
  //   tokenInfo: [MONAD],
  //   explorers: [{
  //     id: 'monadscan',
  //     name: 'Monadscan',
  //     baseUrl: {
  //       mainnet: 'https://monadscan.com/',
  //       testnet: 'https://testnet.monadscan.com/',
  //     },
  //     address: '{base}address/{address}',
  //     token: '{base}token/{address}',
  //     nft: '{base}nft/{address}',
  //     transaction: '{base}tx/{hash}',
  //     doConvertHashFromBase64: false,
  //   }],
  //   marketplaces: [{
  //     id: 'openSea',
  //     name: 'OpenSea',
  //     baseUrl: {
  //       mainnet: 'https://opensea.io/',
  //       testnet: '', // No testnet support
  //     },
  //     nft: '{base}item/{chain}/{address}',
  //   }],
  //   isNetWorthSupported: false,
  //   doesSupportPushNotifications: false,
  //   isNftSupported: true,
  // },
  // avalanche: {
  //   title: 'Avalanche',
  //   chainStandard: 'ethereum',
  //   isDnsSupported: false,
  //   canBuyWithCardInRussia: false,
  //   isTransferPayloadSupported: false,
  //   isEncryptedCommentSupported: false,
  //   canTransferFullNativeBalance: false,
  //   isLedgerSupported: false,
  //   isSubwalletsSupported: true,
  //   defaultDerivationPath: EVM_DERIVATION_PATHS.default,
  //   addressRegex: /^0x[a-fA-F0-9]{40}$/,
  //   addressPrefixRegex: /^0x[a-fA-F0-9]{0,40}$/,
  //   nativeToken: AVALANCHE,
  //   doesBackendSocketSupport: false,
  //   canImportTokens: false,
  //   shouldShowScamWarningIfNotEnoughGas: false,
  //   feeCheckAddress: '0x0000000000000000000000000000000000000000',
  //   buySwap: {
  //     tokenInSlug: AVALANCHE.slug,
  //     amountIn: '0.1',
  //   },
  //   usdtSlug: {
  //     mainnet: AVALANCHE_USDT_MAINNET.slug,
  //     testnet: AVALANCHE_USDT_MAINNET.slug,
  //   },
  //   defaultEnabledSlugs: {
  //     testnet: [],
  //     mainnet: [],
  //   },
  //   crosschainSwapSlugs: [AVALANCHE.slug],
  //   tokenInfo: [AVALANCHE, AVALANCHE_USDT_MAINNET],
  //   explorers: [{
  //     id: 'snowtrace',
  //     name: 'Snowtrace',
  //     baseUrl: {
  //       mainnet: 'https://snowtrace.io/',
  //       testnet: 'https://testnet.snowtrace.io/',
  //     },
  //     address: '{base}address/{address}',
  //     token: '{base}token/{address}',
  //     nft: '{base}nft/{address}',
  //     transaction: '{base}tx/{hash}',
  //     doConvertHashFromBase64: false,
  //   }],
  //   marketplaces: [{
  //     id: 'openSea',
  //     name: 'OpenSea',
  //     baseUrl: {
  //       mainnet: 'https://opensea.io/',
  //       testnet: '', // No testnet support
  //     },
  //     nft: '{base}item/{chain}/{address}',
  //   }],
  //   isNetWorthSupported: false,
  //   doesSupportPushNotifications: false,
  //   isNftSupported: true,
  // },
  hyperliquid: {
    title: 'Hyperliquid',
    chainStandard: 'ethereum',
    isDnsSupported: false,
    canBuyWithCardInRussia: false,
    isOnRampSupported: false,
    isOffRampSupported: false,
    isTransferPayloadSupported: false,
    isEncryptedCommentSupported: false,
    canTransferFullNativeBalance: false,
    isLedgerSupported: false,
    isSubwalletsSupported: true,
    defaultDerivationPath: EVM_DERIVATION_PATHS.default,
    addressRegex: /^0x[a-fA-F0-9]{40}$/,
    addressPrefixRegex: /^0x[a-fA-F0-9]{0,40}$/,
    nativeToken: HYPERLIQUID,
    doesBackendSocketSupport: false,
    canImportTokens: false,
    shouldShowScamWarningIfNotEnoughGas: false,
    feeCheckAddress: '0x0000000000000000000000000000000000000000',
    buySwap: {
      tokenInSlug: TON_USDT_MAINNET.slug,
      amountIn: '50',
    },
    usdtSlug: {
      mainnet: HYPERLIQUID_USDC_MAINNET.slug,
      testnet: HYPERLIQUID_USDC_MAINNET.slug,
    },
    defaultEnabledSlugs: {
      mainnet: [HYPERLIQUID.slug],
      testnet: [HYPERLIQUID.slug],
    },
    crosschainSwapSlugs: [HYPERLIQUID.slug, HYPERLIQUID_USDC_MAINNET.slug],
    tokenInfo: [HYPERLIQUID, HYPERLIQUID_USDC_MAINNET],
    explorers: [{
      id: 'hyperevmscan',
      name: 'Hyperevmscan',
      baseUrl: {
        mainnet: 'https://hyperevmscan.io/',
        testnet: 'https://hyperevmscan.io/',
      },
      address: '{base}address/{address}',
      token: '{base}token/{address}',
      nft: '{base}nft/{address}',
      transaction: '{base}tx/{hash}',
      doConvertHashFromBase64: false,
    }],
    marketplaces: [{
      id: 'openSea',
      name: 'OpenSea',
      baseUrl: {
        mainnet: 'https://opensea.io/',
        testnet: '', // No testnet support
      },
      nft: '{base}item/{chain}/{address}',
    }],
    isNetWorthSupported: false,
    doesSupportPushNotifications: false,
    isNftSupported: false,
  },
};

export const VIEW_ACCOUNT_EVM_PARAM = 'evm';

if (DEBUG) {
  const configKeys = new Set(Object.keys(CHAIN_CONFIG));
  const supportedSet = new Set(CHAIN_ORDER);
  const missing = [...configKeys].filter((k) => !supportedSet.has(k as ApiChain));
  if (missing.length) {
    throw new Error(`SUPPORTED_CHAINS is missing chains from CHAIN_CONFIG: ${missing.join(', ')}`);
  }
}

export function getChainConfig(chain: ApiChain): ChainConfig {
  // The `ApiChain` parameter type is statically narrow, but persisted storage can hold chain
  // keys from older schemas — guard here so callers see the chain name instead of an opaque
  // `undefined.<prop>` further down the stack.
  const config = CHAIN_CONFIG[chain];
  if (!config) {
    throw new Error(`Unsupported chain "${chain}" — not present in CHAIN_CONFIG`);
  }
  return config;
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
  return CHAIN_ORDER;
}

export function getChainsByStandard(chainStandard: ApiChain) {
  return getSupportedChains().filter((chain) => getChainConfig(chain).chainStandard === chainStandard);
}

export function getEvmChains() {
  return getChainsByStandard('ethereum');
}

/** Returns the chains supported by the given account in the proper order for showing in the UI */
export function getOrderedAccountChains(byChain: Partial<Record<ApiChain, unknown>>) {
  return getSupportedChains().filter((chain) => chain in byChain);
}

export function getChainsSupportingLedger(): ApiChain[] {
  return getSupportedChains()
    .filter((chain) => CHAIN_CONFIG[chain].isLedgerSupported);
}

export const getChainsSupportingNft = /* #__PURE__ */ withCache((): ReadonlySet<ApiChain> => {
  return new Set(
    getSupportedChains()
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
